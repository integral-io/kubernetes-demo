#!/usr/bin/env bash

echo "Redeploying cluster to $(kubectl config current-context)"
read -p "Are you sure? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Redeploy aborted"
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi

function hl {
   echo "##############################################################";
}

function box {
  echo ''
  hl
  echo "# $1"
  hl
  echo ''
}

function tunnel {
  hl

  box "Starting tunnel"

#  trap emptyTunnel ERR
#  trap tunnel EXIT
  (minikube tunnel) &>/dev/null &

  #192.168.99.106  bosch-lsm.loc
  box "Tunnel started"

  hl

  box "Updating hosts file"
  IP=$(minikube ip)
  # route -n add 172.17.0.0/16 <minikube ip>  
  # route -n add 10.0.0.0/24 <minikube ip>

  sed -i "s/^ *[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+( +mini-sample.loc)/$IP)\1/" /etc/hosts
  echo "$IP mini-sample.loc"
}

box "Reinstalling minikube"
#trap emptyTunnel ERR
minikube tunnel -c
# Todo: add conditional check to see if minikube is running, and a timeout/force
minikube stop
minikube delete
minikube start --memory 11000 --insecure-registry localhost:5000

hl

eval $(minikube docker-env)


box "Redeploying infrastructure deployments"
helm repo add elastic https://helm.elastic.co
helm init
helm package -u .
helm install .


tunnel
