#!/usr/bin/env bash

echo "Before continuing ensure you make the following edits to /etc/ssl/openssl.cnf"
echo " "
echo "Under [ req ] - if not present set prompt = no"
echo "Under [ req_distinguished_name ] - accurately set all the fields to the best of your knowledge"
echo " "
echo "Ensure the section [ v3_ca ] exists and contains the following properties:"
echo "basicConstraints = critical,CA:TRUE"
echo "subjectKeyIdentifier = hash"
echo "authorityKeyIdentifier = keyid:always,issuer:always"


#helm reset --remove-helm-home

# create certificate authority
PASSWORD=$(head -c 12 /dev/urandom | shasum| cut -d' ' -f1)
openssl req -key ca.key.pem -new -x509 -days 7300 -sha256 -out ca.cert.pem -extensions v3_ca -passin pass:"$PASSWORD"

# create tiller certificates
openssl genrsa -out ./tiller.key.pem 4096 -passin pass:"$PASSWORD"
openssl req -key tiller.key.pem -new -sha256 -out tiller.csr.pem -passin pass:"$PASSWORD"
openssl x509 -req -CA ca.cert.pem -CAkey ca.key.pem -CAcreateserial -in tiller.csr.pem -out tiller.cert.pem -days 365 -passin pass:"$PASSWORD"

# create helm certificates
openssl genrsa -out ./helm.key.pem 4096 -passin pass:"$PASSWORD"
openssl req -key helm.key.pem -new -sha256 -out helm.csr.pem -passin pass:"$PASSWORD"
openssl x509 -req -CA ca.cert.pem -CAkey ca.key.pem -CAcreateserial -in helm.csr.pem -out helm.cert.pem  -days 365 -passin pass:"$PASSWORD"

# test initialize initialize helm on the server
#helm init --dry-run --debug --tiller-tls --tiller-tls-cert ./tiller.cert.pem --tiller-tls-key ./tiller.key.pem --tiller-tls-verify --tls-ca-cert ca.cert.pem --service-account tiller > helm-tiller-setup.yaml

# create the helm tiller account binding
#kubectl apply -f helm-tiller-setup.yaml