#!/bin/bash
tput setaf 7; 
shopt -s expand_aliases
source <(kubectl completion bash)
[ -f ~/.kubectl_aliases ] && source ~/.kubectl_aliases
alias k=kubectl
function kubectl() {
    if ! type __start_kubectl >/dev/null 2>&1; then
        source <(command kubectl completion zsh)
    fi

    command kubectl "$@"
}
#trap ' ' INT

function setup {
    #test pod egress
    k create ns test
    k create ns test2
    k run nginx --image=nginx --namespace=test --labels app=nginx --expose --port 80 --generator=run-pod/v1
}

function cleanup {
    k delete ns test
    k delete ns test2
}

function test-check {
    prompt=$1
    policy=$2
    if [[ $prompt == "n" || $prompt == "N" || $prompt == "no" || $prompt == "No" ]]
    then
        tput setaf 1; echo "test failed with" $policy; tput setaf 7;
        exit 1
    fi
}

function default-deny-egress {
    policyfile="policies/default-deny-egress.yaml"
    tput setaf 2; echo "Testing" $policyfile; tput setaf 7;
    k apply -f $policyfile
    tput setaf 3; k run test --image=alpine --namespace=test --rm --restart=Never -it  -- sh -c "sleep 3s; wget -qO- -T 3 nginx"
    tput setaf 7; read -p "Did nginx fail to resolve and respond? <Y/n> " prompt
    test-check $prompt ${FUNCNAME[0]}
    tput setaf 3; k run test --image=alpine --namespace=test --rm --restart=Never -it  -- sh -c "sleep 3s; wget -qO- -T 3 1.1.1.1"
    tput setaf 7; read -p "Did 1.1.1.1 fail to resolve and respond? <Y/n> " prompt
    test-check $prompt ${FUNCNAME[0]}
    k delete -f $policyfile
}

function default-allow-egress {
    policyfile="policies/default-allow-egress.yaml"
    tput setaf 2; echo "Testing" $policyfile; tput setaf 7;
    k apply -f $policyfile
    tput setaf 3; k run test --image=alpine --namespace=test --rm --restart=Never -it  -- sh -c "sleep 3s; wget -qO- -T 3 nginx"
    tput setaf 7; read -p "Did nginx resolve and respond? <Y/n> " prompt
    test-check $prompt ${FUNCNAME[0]}
    tput setaf 3; k run test --image=alpine --namespace=test --rm --restart=Never -it  -- sh -c "sleep 3s; wget -qO- -T 3 1.1.1.1"
    tput setaf 7; read -p "Did 1.1.1.1 resolve and respond? <Y/n> " prompt
    test-check $prompt ${FUNCNAME[0]}
    k delete -f $policyfile
}

function port-specific-test {
    policyfile="policies/port-ordering.yaml"
    tput setaf 2; echo "Testing" $policyfile; tput setaf 7;
    k apply -f $policyfile
    tput setaf 3; k run test --image=alpine --namespace=test --rm --restart=Never -it  -- sh -c "sleep 3s; wget -O- -T 3 http://151.101.192.67:80"
    tput setaf 7; read -p "Did http://151.101.192.67 resolve and respond? <Y/n> " prompt
    test-check $prompt ${FUNCNAME[0]}
    tput setaf 3; k run test --image=alpine --namespace=test --rm --restart=Never -it  -- sh -c "sleep 3s; wget -O- -T 3 https://151.101.128.67:443"
    tput setaf 7; read -p "Did https://151.101.128.67 resolve and respond? <Y/n> " prompt
    test-check $prompt ${FUNCNAME[0]}
    k delete -f $policyfile
}


function port-ordering {
    for policyfile in "policies/egress-to-dns-and-internet-order1.yaml" "policies/egress-to-dns-and-internet-order2.yaml"; do
        tput setaf 2; echo "Testing" $policyfile; tput setaf 7;
        k apply -f $policyfile
        coredns=$(k get po -o wide -n kube-system | grep core | awk {'print "" $6'})
        nginx=$(k get po -o wide -n test | grep nginx | awk {'print "" $6'})
        tput setaf 3; k run test --image=alpine --namespace=test --labels=app=test --rm --restart=Never -it  -- sh -c "sleep 3s; ping -W 3 -c 3 $coredns"
        tput setaf 7; read -p "Did coredns ($coredns) respond? <Y/n> " prompt
        test-check $prompt ${FUNCNAME[0]}
        tput setaf 3; k run test --image=alpine --namespace=test --labels=app=test --rm --restart=Never -it  -- sh -c "sleep 3s; ping -W 3 -c 3 $nginx"
        tput setaf 7; read -p "Did nginx ($nginx) fail to respond? <Y/n> " prompt
        test-check $prompt ${FUNCNAME[0]}
        tput setaf 3; k run test --image=alpine --namespace=test --labels=app=test --rm --restart=Never -it  -- sh -c "sleep 3s; ping -W 3 -c 3 1.1.1.1"
        tput setaf 7; read -p "Did 1.1.1.1 respond? <Y/n> " prompt
        test-check $prompt ${FUNCNAME[0]}
        k delete -f $policyfile
    done 
}


if [ "$#" -ne 1 ]
then
    cleanup
    setup
    default-deny-egress
    default-allow-egress
    cleanup
else
    "$@"
fi

