#!/usr/bin/env bash

# prep
{
    source "$HOME/.brew/messaging.sh"
    source "$HOME/.brew/certs.sh"

    function getPassword {
      local PASSWORD
      local CURRENT
      checkForCerts
      CURRENT="$(pwd)"
      cd certs || exit
      if [ ! -f "pass" ]
      then
        touch "pass"
        PASSWORD=$(head -c 12 /dev/urandom | shasum| cut -d' ' -f1)
        echo "$PASSWORD" >> "pass"
      else
        PASSWORD=$(<pass)
      fi
      cd "$CURRENT" || exit
      echo "$PASSWORD"
    }

    function getBuild {
        echo "$(head -c 6 /dev/urandom | shasum| cut -d' ' -f1)"
    }
    BUILD=$(getBuild)

}

#Certs
{
    function removeCertManager {
      kubectl delete configMap cert-manager-controller
      kubectl delete namespace cert-manager
    }

    function installCertManager() {
      box "installing cert  manager"
      kubectl create namespace cert-manager
      kubectl apply \
        -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.9/deploy/manifests/00-crds.yaml
      kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
    }
}

#resetting a cluster
#{
#    function removeSecrets {
#      kubectl delete secret --all
#      kubectl delete secret basic-auth || true
#      kubectl delete configMap application.v1 --namespace kube-system
#      kubectl delete configMap infra.v1 --namespace kube-system
#    }
#
#    function removeClusterRoleBindings() {
#        kubectl delete clusterrolebinding my-cluster-admin-binding
#        kubectl delete clusterrolebinding tiller-cluster-rule
#    }
#
#    function removeLeftOvers() {
#        kubectl delete pvc --all
#        kubectl delete pv --all
#        kubectl delete configMaps --all
#        kubectl delete crd -l controller-tools.k8s.io=1.0
#        kubectl delete crd alertmanagers.monitoring.coreos.com
#        kubectl delete crd podmonitors.monitoring.coreos.com
#        kubectl delete crd prometheuses.monitoring.coreos.com
#        kubectl delete crd prometheusrules.monitoring.coreos.com
#        kubectl delete crd servicemonitors.monitoring.coreos.com
#        kubectl delete clusterrole,roles -l app=prometheus-operator-admission
#    }
#
#    function removeReleases() {
#      helm delete --purge infra
#      helm delete --purge application
#    }
#
#    function removeAllFromCluster() {
#        kubectl delete services,sts,deployments,daemonSets,serviceMonitors,pv,pvc,crd,serviceAccounts,secrets,cm --all
#        removeCerts
#        removeHelmManual
#        removeCertManager
#        removeClusterRoleBindings
#        removeSecrets
#        removeLeftOvers
#    }
#}

#minikube
{

    function removeMinikube() {
        minikube tunnel -c
        minikube delete
    }

    function removeReleasesMini() {
      helm delete --purge infra
      helm delete --purge application
    }

    function startMinikube() {
      box "starting minikube"
      minikube start --memory 11000 --cpus=4
      minikube tunnel
    }

    function stopMinikube() {
      box "stopping minikube"
      echo " "
      echo "have you stopped the tunnel yet?"
      echo " "
      continueReady
      minikube tunnel -c
      minikube stop
    }

}

#application
{
    function getImageName() {
      local IMAGE
      IMAGE="$1"/logger:"$BUILD"
      echo "$IMAGE"
    }

    function buildImage() {
      box "building docker image $(getImageName "$1")"
      docker build application -t "$(getImageName "$1")"
    }

    function buildCloud() {
      buildImage "$1"
      docker push "$(getImageName "$1")"
    }

    function buildLocal() {
      eval $(minikube docker-env)
      buildImage "$1"
    }
}

#setup a cluster
{
    function setupBasicAuth() {
      checkForCerts
      local PASSWORD
      PASSWORD="$(getPassword)"
      htpasswd -cb ./certs/auth admin ${PASSWORD}

      kubectl -n default create secret generic basic-auth \
      --from-literal=basic-auth-user=admin \
      --from-literal=basic-auth-password="$PASSWORD" \
      --from-file certs/auth
    }

    function setupFromCA() {
#      removeHelm
#      generateCertsFromCA
      setup
    }

    function setup() {
#      genMessage
#      echo "$(startGenerating)"
#      box "Initializing helm with tls."
      box "starting"

#      initializeHelm
    }

    function setupFirstTime() {
#      generateCertsNewCA
      setup
    }
}

#setup local
{

    function cycleMinikube() {
        stopMinikube
        removeMinikube
        startMinikube
    }

    function setupMinikube() {
      kubectl create clusterrolebinding my-cluster-admin-binding --clusterrole=cluster-admin --user="andrew@integral.io"
      setupBasicAuth
#      setupFirstTime
      installDemoMinikube
    }

    function setupCleanMinikube() {
        removeReleasesMini
        removeAllFromCluster
        setupMinikube
    }

    function setupPurgeMinikube() {
        removeMinikube
        startMinikube
        setupMinikube
    }

}

#setup remote
#{
##    function setupGKE() {
##      kubectl create clusterrolebinding my-cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud info --format="value(config.account)")
##      setupBasicAuth
##      setupFirstTime
##      installDemoGKE
##    }
##
##    function setupCleanGKE() {
##        removeReleases
##        removeAllFromCluster
##        setupGKE
##    }
#}

#install and/or upgrade helm charts
{
    function upgradePackages() {
      box "deploying helm charts"
      box $1
      box $2
      box $3
#      helm template infra infrastructure/umbrella -f infrastructure/umbrella/"$1"
#      helm upgrade infra infrastructure/umbrella -f infrastructure/umbrella/"$1" --install
#      helm template application infrastructure/demo -f infrastructure/demo/"$2" --set base-application.image.tag="$3"
      helm upgrade application infrastructure/demo -f infrastructure/demo/"$2" --set base-application.image.tag="$3" --install
    }

#    function installDemoGKE() {
#      installCertManager
#      buildCloud "gcr.io/k8frastructure"
#      upgradePackages values.yaml values-gke.yaml "$BUILD"
#    }

    function installDemoMinikube() {
      installCertManager
      buildLocal "demo"
      upgradePackages values-local.yaml values.yaml ${BUILD}
    }
}

function hhelp() {
  local IFS
  IFS=$'\n'
  for f in $(declare -F); do
     echo "${f:11}"
  done
}

"$@"
