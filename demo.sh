#!/usr/bin/env bash

function hl {
   echo "##############################################################";
}

function next {
  echo ""
  hl
  read -p "next: $1 ? Enter or ^c " -n 1 -r
  hl
}

function subtitle {
  echo "$1"
  hl
  delay ""
}

function title {
  clear
  subtitle "$1"
}

function delay() {
    read -p "$1" -n 1 -r
}

function agenda {
  title "Local development with Kubernetes"
  subtitle "agenda"
  echo "- why"
  echo "- minikube"
  echo "- scripting"
  echo "- homebrew"
  echo "- intellij plugins"
  echo "- telepresence"
  echo "- A real cloud"
  next "minikube"
  minicube
}

function minicube() {
  title "Minikube"
  delay "lets start it up"
  echo "kdemo startMinikube andrew@integral.io"
  next "why"
  why
}

function why() {
  title "Why"
  delay "- consistency"
  delay "- faster cycle time"
  hl
  subtitle "disadvantage"
  delay
  delay "- resource intensive"
  next "shell"
  shell
}

function shell() {
  title "Shell"
  delay "To use kubernetes there is a lot to learn"
  delay "- definitely script everything"
  delay "- serves as documentation"
  delay "- will help you go from dev to production"
  echo ""
  delay " * this presentation is done in bash *"
  next "homebrew"
  homebrew
}

function homebrew() {
    title "Homebrew"
    delay "- kubectl"
    delay "   - powerful command tool"
    delay "   - query or operate on everything in a cluster"
    delay "- kubectx"
    delay "- popeye"
    delay "- k9s"
    delay "- openssl"
    delay "- faas-cli (not demonstrated)"
    delay "- helm"
    delay "   - dependency manager"
    delay "   - not as full featured as kubectl"
    delay "   - easilly deploy pre-built packages"
    delay "   - easilly template release files"
    delay "   - easilly configure multiple environments"
    delay "(and of course there are many more)"
    brew list
    next "homebrew continued: cloud tools"
    cloudTools
}

function cloudTools() {
    title "Cloud Tools"
    echo "- azure cli"
    echo "- google cloud cli"
    echo "- aws cli"
    echo ""
    echo "etc..."
    next "Intellij plugins"
    plugins
}

function plugins() {
    title "Intellij plugins"
    delay "- kubernetes formatting and completion"
    delay "- EnvFile"
    delay "- TeamCity"
    next "kubernetes helm packages"
    kuber
}

function kuber() {
  title "kubernetes helm packages"
  delay "- elk (elastic - Kibana)"
  delay "- prometheus & grafana"
  delay "- openfaas"
  delay "- ci/cd"
  next "Telepresence"
  tele
}

function tele() {
    title "Telepresence"
    delay "- local or remote debugging"
    next "A real cloud"
    real
}

function real() {
    title "A real cloud"
    delay "google cloud"
    next "Done!"
}


# Telepresence
#   - local or remote debugging
#
#kdemo setupMinikube andrew@integral.io
#kubectl get pods --namespace kube-system
#k9s
#telepresence --swap-deployment application-base-application --env-json ratelimit_env.json
#kdemo stopMinikube

"$@"