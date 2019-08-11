#!/usr/bin/env bash

PASSWORD=$(head -c 12 /dev/urandom | shasum| cut -d' ' -f1)
htpasswd -cb ./auth admin $PASSWORD

kubectl delete secret basic-auth || true
kubectl -n default create secret generic basic-auth \
--from-literal=basic-auth-user=admin \
--from-literal=basic-auth-password="$PASSWORD" \
--from-file auth

rm auth

kubectl apply \
    -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.9/deploy/manifests/00-crds.yaml

kubectl create namespace cert-manager
kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true

#kubectl delete secrets elastic-credentials elastic-certificates elastic-certificate-pem || true && \
#vault read -field=value secret/devops-ci/helm-charts/elasticsearch/security/certificates | base64 --decode > elastic-certificates.p12 && \
#vault read -field=value secret/devops-ci/helm-charts/elasticsearch/security/certificate-pem | base64 --decode > elastic-certificate.pem && \
#kubectl create secret generic elastic-credentials  --from-literal=password=changeme --from-literal=username=elastic && \
#kubectl create secret generic elastic-certificates --from-file=elastic-certificates.p12 && \
#kubectl create secret generic elastic-certificate-pem --from-file=elastic-certificate.pem && \
#rm -f elastic-certificates.p12 elastic-certificate.pem
#
#kubectl delete secret kibana-certificates || true && \
#vault read -field=kibana.crt secret/devops-ci/helm-charts/kibana/security/certificates | base64 --decode > kibana.crt && \
#vault read -field=kibana.key secret/devops-ci/helm-charts/kibana/security/certificates | base64 --decode > kibana.key && \
#kubectl create secret generic kibana-certificates --from-file=kibana.crt --from-file=kibana.key && \
#rm -f kibana.crt kibana.key