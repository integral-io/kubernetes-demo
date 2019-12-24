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
{
    function removeSecrets {
      kubectl delete secret --all
      kubectl delete secret basic-auth || true
      kubectl delete configMap application.v1 --namespace kube-system
      kubectl delete configMap infra.v1 --namespace kube-system
    }

    function removeClusterRoleBindings() {
        kubectl delete clusterrolebinding my-cluster-admin-binding
        kubectl delete clusterrolebinding tiller-cluster-rule
    }

    function removeLeftOvers() {
        kubectl delete pvc --all
        kubectl delete pv --all
        kubectl delete configMaps --all
        kubectl delete crd -l controller-tools.k8s.io=1.0
        kubectl delete crd alertmanagers.monitoring.coreos.com
        kubectl delete crd podmonitors.monitoring.coreos.com
        kubectl delete crd prometheuses.monitoring.coreos.com
        kubectl delete crd prometheusrules.monitoring.coreos.com
        kubectl delete crd servicemonitors.monitoring.coreos.com
        kubectl delete clusterrole,roles -l app=prometheus-operator-admission
    }

    function removeReleases() {
        box removing universal packages
        helm delete ingress
        helm delete elk
        helm delete metrics
        helm delete accounts
        helm delete demo
        helm delete functions
    }

    function removeCloud() {
        helm delete letsencrypt
        helm delete certificates
    }
    function removeAllFromCluster() {
        kubectl delete services,sts,deployments,daemonSets,serviceMonitors,pv,pvc,crd,serviceAccounts,secrets,cm --all
#        removeCerts
#        removeHelmManual
        removeCertManager
        removeClusterRoleBindings
        removeSecrets
        removeLeftOvers
        removeReleases
    }
}

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
      minikube addons enable ingress
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
      box installing universal packages
      box networking
      helm upgrade ingress infrastructure/networking/ingress -f infrastructure/networking/ingress/"$1" --install -n networking
      hl
      box monitoring
      helm upgrade elk infrastructure/monitoring/elk -f infrastructure/monitoring/elk/"$1" --install -n monitoring
      hl
      helm upgrade metrics infrastructure/monitoring/metrics -f infrastructure/monitoring/metrics/"$1" --install -n monitoring
      box security
      helm upgrade accounts infrastructure/security/accounts -f infrastructure/security/accounts/"$1" --install -n security
      hl

      box applications
      helm upgrade demo infrastructure/applications/demo -f infrastructure/applications/demo/"$1" --set base-application.image.tag="$2" --install -n dev
      hl
      helm upgrade functions infrastructure/applications/functions -f infrastructure/applications/functions/"$1" --install -n dev
    }

    function upgradeCloudPackages() {
      box installing cloud packages
      helm upgrade letsencrypt infrastructure/networking/letsencrypt -f infrastructure/networking/letsencrypt/"$1" --install -n networking # not in local
      helm upgrade certificates infrastructure/security/certificates --install -n security

      upgradePackages $1 $2
    }

}

{
#    function installDemoGKE() {
#      installCertManager
#      buildCloud "gcr.io/k8frastructure"
#      upgradePackages values-gke.yaml "$BUILD"
#    }

    function createNameSpaces() {
        kubectl create namespace networking
        kubectl create namespace dev
        kubectl create namespace security
        kubectl create namespace monitoring
      installCertManager
    }

    function installDemoMinikube() {
      createNameSpaces
      buildLocal "demo"
      upgradePackages values-local.yaml ${BUILD}
    }

    function upgradeDemoMinikube() {
      buildLocal "demo"
      upgradePackages values-local.yaml ${BUILD}
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
