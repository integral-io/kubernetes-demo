#!/usr/bin/env bash

#messaging
{
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

    function bail {
        echo " "
        echo "aborted"
        exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    }

    function ask {
      read -p "$1" -n 1 -r
      echo $REPLY
    }

    function yesOrNo {
      if [[ ! $(ask "$1 (y/n)") =~ ^[Yy]$ ]]
      then
        if [ "$2" != false ]
        then
          exit 1 || return 1
        fi
      fi
    }

    function continueReady {
      yesOrNo "Are you ready to continue?" true
    }

    function genMessage {
      hl
      echo "Before continuing ensure you make the following edits to /etc/ssl/openssl.cnf"
      echo " "
      echo "Under [ req ] - if not present set prompt = no"
      echo "Under [ req_distinguished_name ] - accurately set all the fields to the best of your knowledge"
      echo " "
      echo "Ensure the section [ v3_ca ] exists and contains the following properties:"
      echo "basicConstraints = critical,CA:TRUE"
      echo "subjectKeyIdentifier = hash"
      echo "authorityKeyIdentifier = keyid:always,issuer:always"
      echo " "
      hl
    }

    function startGenerating {
      echo "$(continueReady)"
    }
}

# prep
{
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

#Helm
{
    function removeHelmManual() {
        # we know this will be here unless tiller has never been setup before
        kubectl delete deployment tiller-deploy --namespace kube-system
        kubectl delete service tiller-deploy --namespace kube-system
        # This may not be there even if it has
        kubectl delete secret tiller-secret --namespace kube-system
        kubectl delete serviceaccount tiller --namespace kube-system
    #    helm reset --force
    }

    function removeHelm {
      echo "This will remove helm"
      echo "$(continueReady)"
      local CURRENT
      local EXPECTED
      local ACTUAL
      CURRENT="$(pwd)"
      cd ~/.helm/ || exit
      EXPECTED="can't read CA file: $(pwd)/ca.pem"
      ACTUAL=$(helm reset --tls-verify)
      if [[ "$ACTUAL" != "$EXPECTED" ]]
      then
        removeHelmManual
      else
        helm reset --remove-helm-home --tls
      fi
      cd $CURRENT || exit
    }

    function initializeHelm {
      local CURRENT
      CURRENT="$(pwd)"
      checkForCerts
      cd certs || exit
      box "test initialize tiller on the server"
      helm init --dry-run --debug --tiller-tls --tiller-tls-cert ./tiller.cert.pem --tiller-tls-key ./tiller.key.pem --tiller-tls-verify --tls-ca-cert ca.cert.pem --service-account tiller > helm-tiller-setup.yaml
      box "create the helm tiller account binding"
      kubectl apply -f helm-tiller-setup.yaml
      kubectl create serviceaccount tiller --namespace kube-system
      kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
      box "Pausing for 30 seconds for tiller agent to become ready"
      sleep 30s
      box "copying client certs into helm directory"
      cp ca.cert.pem ~/.helm/ca.pem
      cp helm.cert.pem ~/.helm/cert.pem
      cp helm.key.pem ~/.helm/key.pem
      cd "$CURRENT" || exit
    }

    function initializeHelmMini {
      helm init
      box "Pausing for 30 seconds for tiller agent to become ready"
      sleep 30s
    }

}

#Certs
{
    function checkForCerts {
      if [ ! -d "./certs" ]
      then
        mkdir "certs"
      fi
    }

    function removeCerts {
      checkForCerts
      rm -rf certs
    }

    function removeCertManager {
      kubectl delete configMap cert-manager-controller
      kubectl delete namespace cert-manager
    }

    ## create certificate authority
    function generateCA {
      local CURRENT
      CURRENT="$(pwd)"
      checkForCerts
      cd certs || exit
      openssl genrsa -out ./ca.key.pem 4096
      cd "$CURRENT" || exit
    }

    function generateCerts {
  local PASSWORD
  local CURRENT
  CURRENT="$(pwd)"
  PASSWORD=$(getPassword)
  cd certs || exit
  openssl req -key ca.key.pem -new -x509 -days 7300 -sha256 -out ca.cert.pem -extensions v3_ca
  createCertificate "tiller" "$PASSWORD"
  createCertificate "helm" "$PASSWORD"
  cd "$CURRENT" || exit
}

    function createCertificate {
      box "creating $1 certs"
      openssl genrsa -out ./"$1".key.pem 4096 -passin pass:"$2"
      openssl req -key "$1".key.pem -new -sha256 -out "$1".csr.pem -passin pass:"$2"
      openssl x509 -req -CA ca.cert.pem -CAkey ca.key.pem -CAcreateserial -in "$1".csr.pem -out "$1".cert.pem -days 365 -passin pass:"$2"
    }

    function generateCertsNewCA {
    generateCA
    generateCerts
    }

    function generateCertsFromCA {
    local CURRENT
    CURRENT="$(pwd)"
    checkForCerts
    cd certs || exit
    if [ ! -f "ca.key.pem" ]
    then
    echo "Certificate authority does not exist. Get a copy of the CA from the owner of this cluster."
    generateCerts
    fi
    cd "$CURRENT" || exit
    }

    function installCertManager() {
      box "installing cert manager"
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
      helm delete --purge infra --tls
      helm delete --purge application --tls
    }

    function removeAllFromCluster() {
        kubectl delete services,sts,deployments,daemonSets,serviceMonitors,pv,pvc,crd,serviceAccounts,secrets,cm --all
        removeCerts
        removeHelmManual
        removeCertManager
        removeClusterRoleBindings
        removeSecrets
        removeLeftOvers
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
      htpasswd -cb ./certs/auth admin $PASSWORD

      kubectl -n default create secret generic basic-auth \
      --from-literal=basic-auth-user=admin \
      --from-literal=basic-auth-password="$PASSWORD" \
      --from-file certs/auth
    }

    function setupFromCA() {
      removeHelm
      generateCertsFromCA
      setup
    }

    function setup() {
      genMessage
      echo "$(startGenerating)"
      box "Initializing helm with tls."

      initializeHelm
    }

    function setupFirstTime() {
      generateCertsNewCA
      setup
    }
}

#setup local
{

    function setupMinikube() {
      kubectl create clusterrolebinding my-cluster-admin-binding --clusterrole=cluster-admin --user="$1"
      setupBasicAuth
      setupFirstTime
      installDemoMinikube
    }

    function setupCleanMinikube() {
        removeReleasesMini
        removeAllFromCluster
        setupMinikube $1
    }

    function setupPurgeMinikube() {
        removeMinikube
        startMinikube
        setupMinikube $1
    }

}

#setup remote
{
    function setupGKE() {
      kubectl create clusterrolebinding my-cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud info --format="value(config.account)")
      setupBasicAuth
      setupFirstTime
      installDemoGKE
    }

    function setupCleanGKE() {
        removeReleases
        removeAllFromCluster
        setupGKE
    }
}

#install and/or upgrade helm charts
{
    function upgradePackages() {
      box "deploying helm charts"
      helm upgrade infra infrastructure/umbrella -f infrastructure/umbrella/"$1" --install --tls
      helm upgrade application infrastructure/demo -f infrastructure/demo/"$2" --set base-application.image.tag="$BUILD" --install --tls
    }

    function installDemoGKE() {
      installCertManager
      buildCloud "gcr.io/k8frastructure"
      upgradePackages values.yaml values-gke.yaml "$BUILD"
    }

    function installDemoMinikube() {
      installCertManager
      buildLocal "demo"
      upgradePackages values-local.yaml values.yaml "$BUILD"
    }
}

function help() {
  local IFS
  IFS=$'\n'
  for f in $(declare -F); do
     echo "${f:11}"
  done
}

"$@"
