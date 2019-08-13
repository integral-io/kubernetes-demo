#!/usr/bin/env bash

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
    # we know this will be here unless tiller has never been setup before
    kubectl delete deployment tiller-deploy --namespace kube-system
    kubectl delete service tiller-deploy --namespace kube-system
    # This may not be there even if it has
    kubectl delete secret tiller-secret --namespace kube-system
    kubectl delete serviceaccount tiller --namespace kube-system
#    helm reset --force
  else
    helm reset --remove-helm-home --tls
  fi
  cd $CURRENT || exit
}

function checkForCerts {
  if [ ! -d "./certs" ]
  then
    mkdir "certs"
  fi
}

function removeMinikube() {
    minikube tunnel -c
    minikube delete
}

function removeCerts {
  checkForCerts
  rm -rf certs
}

function removeCertManager {
  kubectl delete configMap cert-manager-controller
  kubectl delete namespace cert-manager
}

function removeSecrets {
  kubectl delete secret --all
  kubectl delete secret basic-auth || true
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
    removeReleases
#    kubectl delete deployments,sts,services,daemonSets --all
    removeCerts
#    removeHelm
    removeCertManager
    removeClusterRoleBindings
    removeSecrets
    removeLeftOvers
}

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

function createCertificate {
  box "creating $1 certs"
  openssl genrsa -out ./"$1".key.pem 4096 -passin pass:"$2"
  openssl req -key "$1".key.pem -new -sha256 -out "$1".csr.pem -passin pass:"$2"
  openssl x509 -req -CA ca.cert.pem -CAkey ca.key.pem -CAcreateserial -in "$1".csr.pem -out "$1".cert.pem -days 365 -passin pass:"$2"
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

## create certificate authority
function generateCA {
  local CURRENT
  CURRENT="$(pwd)"
  checkForCerts
  cd certs || exit
  openssl genrsa -out ./ca.key.pem 4096
  cd "$CURRENT" || exit
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
  cp helm.cert.pem ~/.helm/cert.pem
  cp helm.key.pem ~/.helm/key.pem
  cd "$CURRENT" || exit
}


function setupBasicAuth() {
  checkForCerts
  local PASSWORD
  PASSWORD=getPassword
  htpasswd -cb ./certs/auth admin $PASSWORD

  kubectl -n default create secret generic basic-auth \
  --from-literal=basic-auth-user=admin \
  --from-literal=basic-auth-password="$PASSWORD" \
  --from-file certs/auth
}

function setupFromCA() {
  genMessage
  echo "$(startGenerating)"
  box "Initializing helm with tls."

  removeHelm
  generateCertsFromCA
  initializeHelm
}

function setupFirstTime() {
  genMessage
  echo "$(startGenerating)"
  box "Initializing helm with tls."

  generateCertsNewCA
  initializeHelm
}

function setupClean() {
  genMessage
  echo "$(startGenerating)"
  box "Initializing helm with tls."

  removeCerts
  removeHelm
  generateCertsNewCA
  initializeHelm
}

function help() {
  local IFS
  IFS=$'\n'
  for f in $(declare -F); do
     echo "${f:11}"
  done
}

function setupGKE() {
  kubectl create clusterrolebinding my-cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud info --format="value(config.account)")
#  kubectl create clusterrolebinding my-cluster-admin-binding --clusterrole=cluster-admin --user=system:serviceaccount:kube-system:tiller --namespace=kube-system
  setupBasicAuth
  setupFirstTime
  installDemoGKE
}

function setupCleanGKE() {
    removeAllFromCluster
    setupGKE
}

function setupMinikube() {
  kubectl create clusterrolebinding my-cluster-admin-binding --clusterrole=cluster-admin --user="$1"
  setupBasicAuth
  setupFirstTime
  installDemoMinikube
}

function setupCleanMiniKube() {
    removeAllFromCluster
    setupMinikube $1
}

function setupPurgeMiniKube() {
    removeMinikube
    startMinikube
    setupMinikube $1
}

function startMinikube() {
  box "starting minikube"
  minikube start --memory 11000 --insecure-registry localhost:5000
}

function installCertManager() {
  box "installing cert manager"
  kubectl create namespace cert-manager
  kubectl apply \
    -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.9/deploy/manifests/00-crds.yaml
  kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
}

function installDemoGKE() {
  local BUILD
  BUILD="$(getBuild)"
  installCertManager
  box "building docker image"
  docker build application -t gcr.io/k8frastructure/logger:"$BUILD"
  docker push gcr.io/k8frastructure/logger:"$BUILD"
  box "deploying helm chart"
  helm install infrastructure/umbrella -n infra -f infrastructure/demo/values-gke.yaml --tls
  helm install infrastructure/demo -n application -f infrastructure/demo/values-gke.yaml --set base-application.image.tag="$BUILD" --tls
}

function installDemoMinikube() {
  eval $(minikube docker-env)
  local BUILD
  BUILD="$(getBuild)"
  docker build application -t demo/logger:"$BUILD"
  helm install infrastructure/umbrella -n infra -f infrastructure/demo/values.yaml --tls
  helm install infrastructure/demo -n application -f infrastructure/demo/values.yaml --set base-application.image.tag="$BUILD" --tls
}

"$@"
