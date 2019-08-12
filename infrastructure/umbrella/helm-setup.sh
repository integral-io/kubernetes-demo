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

function resetHelm {
  local CURRENT
  local EXPECTED
  local ACTUAL
  CURRENT="$(pwd)"
  cd ~/.helm/ || exit
  EXPECTED="can't read CA file: $(pwd)/ca.pem"
  echo "$EXPECTED"
  ACTUAL=$(helm reset --tls-verify)
  cd "$CURRENT" || exit
  if [[ "$ACTUAL" != "$EXPECTED" ]]
  then
    # we know this will be here unless tiller has never been setup before
    kubectl delete deployment tiller-deploy --namespace kube-system
    kubectl delete service tiller-deploy --namespace kube-system
    # This may not be there even if it has
    kubectl delete secret tiller-secret --namespace kube-system
  else
    helm reset --remove-helm-home --tls
  fi
}

function checkForCerts {
  if [ ! -d "./certs" ]
  then
    mkdir "certs"
  fi

  cd certs || exit

  local PASSWORD
  if [ ! -f "pass" ]
  then
    touch "pass"
    PASSWORD=$(head -c 12 /dev/urandom | shasum| cut -d' ' -f1)
    echo "$PASSWORD" >> "pass"
  else
    PASSWORD=$(<pass)
  fi
  echo "$PASSWORD"
}

function createCertificate {
  box "creating $1 certs"
  openssl genrsa -out ./"$1".key.pem 4096 -passin pass:"$2"
  openssl req -key "$1".key.pem -new -sha256 -out "$1".csr.pem -passin pass:"$2"
  openssl x509 -req -CA ca.cert.pem -CAkey ca.key.pem -CAcreateserial -in "$1".csr.pem -out "$1".cert.pem -days 365 -passin pass:"$2"
}

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

continueReady

echo " "
echo "Initializing helm with tls."
echo " "

PASSWORD=$(checkForCerts)

resetHelm

cd certs



## create certificate authority
if [ ! -f "ca.key.pem" ]
then
  echo "Certificate authority does not exist. Get a copy of the CA from the owner of this cluster."
  yesOrNo "If you are the owner and this is an initial setup you can create one now. Create it now?"
  openssl genrsa -out ./ca.key.pem 4096
fi

openssl req -key ca.key.pem -new -x509 -days 7300 -sha256 -out ca.cert.pem -extensions v3_ca

createCertificate "tiller" "$PASSWORD"
createCertificate "helm" "$PASSWORD"
box "test initialize tiller on the server"
helm init --dry-run --debug --tiller-tls --tiller-tls-cert ./tiller.cert.pem --tiller-tls-key ./tiller.key.pem --tiller-tls-verify --tls-ca-cert ca.cert.pem --service-account tiller > helm-tiller-setup.yaml
box "create the helm tiller account binding"
kubectl apply -f helm-tiller-setup.yaml
box "copying client certs into helm directory"
cp helm.cert.pem ~/.helm/cert.pem
cp helm.key.pem ~/.helm/key.pem
