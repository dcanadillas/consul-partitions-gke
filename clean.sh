#!/bin/bash

CLUSTER1=$1
CLUSTER2=$2
CONSUL_K8S_VERSION="1.3.0"
CONSUL_VERSION="1.17.0-ent"
CONSUL_TOKEN="$(uuidgen)"
DC1="dc1"
# DC2="dc2"
CONSUL_NAMESPACE="consul"
CONSUL_CA_CERT_SECRET="server-ca-cert"
CONSUL_CA_KEY_SECRET="server-ca-key"
CONSUL_PARTITION="second"
DEMO_TMP="/tmp/cross_partition_demo"

# Color
RED=$(tput setaf 1)
BLUE=$(tput setaf 4)
DGRN=$(tput setaf 2)
GRN=$(tput setaf 10)
YELL=$(tput setaf 3)
NC=$(tput sgr0) #No color


if [ -z "$1" ] || [ -z "$2" ];then
  echo -e "${RED}Need to define GKE clusters or Minikube profiles as arguments.\n\t\"$ $0 [<gke_name_1> <gke_name_2> || <minikube_profile_1> <minikube_profile_2>]\"${NC}"
  exit 1
fi
if ! hash kubectl;then
  echo "${RED}Please install \"kubectl\" command in $PATH...${NC}\n"
  exit 1
fi
if ! hash jq;then 
  echo "${RED}Please install \"jq\" command in $PATH...${NC}\n"
  exit 1
fi


KUBECONFIG1="/tmp/${CLUSTER1}-kube.config"
KUBECONFIG2="/tmp/${CLUSTER2}-kube.config"

uninstall_consul () {
  echo -e "${BLUE}Uninstalling Consul from $1...${NC}"
  consul-k8s uninstall --kubeconfig $2
}

delete_resources () {
  echo -e "${BLUE}Deleting resources from $1...${NC}"
  kubectl delete -n $CONSUL_NAMESPACE serviceintentions $1 --kubeconfig $2 || true
  kubectl delete -n $CONSUL_NAMESPACE httproute $1 --kubeconfig $2 || true
  kubectl delete -n $CONSUL_NAMESPACE gateway $1 --kubeconfig $2 || true
  kubectl delete -n $CONSUL_NAMESPACE proxydefaults $1 --kubeconfig $2 || true
}


echo -e "\n${GRN}==> Selecting K8s deployment type...${NC}"
read -p "${YELL}Are you on \"Minikube\" or \"GKE\"?: ${NC}" K8S_TYPE
echo ""

case $K8S_TYPE in
  Minikube)
    echo -e"\nYou are working with Minikube profiles \"$1\" and \"$2\". \n"
    # Fetching clusters endpoints
    CLUSTER1_ENDPOINT="$(minikube ip -p $CLUSTER1)"
    CLUSTER2_ENDPOINT="$(minikube ip -p $CLUSTER2)"

    # Creating 2 different Kubeconfigs by updating contexts from Minikube profiles
    KUBECONFIG=$KUBECONFIG1 minikube update-context -p $CLUSTER1
    KUBECONFIG=$KUBECONFIG2 minikube update-context -p $CLUSTER2
    K8S_PORT="8443"
    ;;
  GKE)
    # Fetching locations in a variable for the two clusters
    CLUSTER1_ZONE="$(gcloud container clusters list --filter "name:$CLUSTER1" --format "[]value(location)")"
    CLUSTER2_ZONE="$(gcloud container clusters list --filter="name:$CLUSTER2" --format "[]value(location)")"

    # Fetching clusters endpoints
    CLUSTER1_ENDPOINT="$(gcloud container clusters list --filter="name:$CLUSTER1" --format "[]value(endpoint)")"
    CLUSTER2_ENDPOINT="$(gcloud container clusters list --filter="name:$CLUSTER2" --format "[]value(endpoint)")"

    # Creating 2 different Kubeconfigs by getting credentials from GKE with GCloud
    echo "Getting credentials for cluster \"$CLUSTER1\"..."
    KUBECONFIG=$KUBECONFIG1 gcloud container clusters get-credentials $CLUSTER1 --zone $CLUSTER1_ZONE
    echo "Getting credentials for cluster \"$CLUSTER2\"..."
    KUBECONFIG=$KUBECONFIG2 gcloud container clusters get-credentials $CLUSTER2 --zone $CLUSTER2_ZONE
    K8S_PORT="443"
    ;;
  *)
    echo -e "\nNot recognized K8s deployment. Please, type \"GKE\" or \"Minikube\"..."
    exit 1
    ;;
esac

echo -e "\n${GRN}==> Cleaning $CLUSTER1...${NC}"
delete_resources --all $KUBECONFIG1
kubectl delete namespace $CONSUL_NAMESPACE --kubeconfig $KUBECONFIG1 || true

echo -e "\n${GRN}==> Cleaning $CLUSTER2...${NC}"
delete_resources --all $KUBECONFIG2
kubectl delete namespace $CONSUL_NAMESPACE --kubeconfig $KUBECONFIG2 || true

echo -e "\n${GRN}==> Uninstalling Consul from $CLUSTER1...${NC}"
uninstall_consul $CLUSTER1 $KUBECONFIG1

echo -e "\n${GRN}==> Uninstalling Consul from $CLUSTER2...${NC}"
uninstall_consul $CLUSTER2 $KUBECONFIG2
