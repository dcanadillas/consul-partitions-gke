#!/bin/bash

# Script designed to install with GKE clusters

CLUSTER1=$1
CLUSTER2=$2
API_GW_VERSION="0.5.2"
CONSUL_LICENSE=""
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

if ! hash gcloud;then
  echo -e "${RED}There is no \"gcloud\" command in $PATH...${NC}\n"
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
if ! hash helm;then 
  echo "${RED}Please install \"Helm\"...${NC}\n"
  exit 1
fi

# Checking that Consul License is loaded into an environment variable
if [ -z $CONSUL_LICENSE_PATH ];then
  if [ -z $CONSUL_LICENSE ]; then
    echo "There is no Consul license to use. Please put it on \"CONSUL_LICENSE\" environment variable."
    echo "You can also put the license file path in \"CONSUL_LICENSE_PATH\" environment variable"
    exit 1
  else
    CONSUL_LICENSE=$CONSUL_LICENSE
  fi 
else 
  CONSUL_LICENSE="$(cat $CONSUL_LICENSE_PATH)"
fi

echo -e "\n${GRN}==> Checking Consul License...${NC}"
# Showing only the first 15 chars of the license
echo "CONSUL_LICENSE=$(echo ${CONSUL_LICENSE:0:5}... ...${CONSUL_LICENSE:0-15})"


# CTX1=$1
# CTX2=$2

# We set two different Kubeconfig files
KUBECONFIG1="/tmp/${CLUSTER1}-kube.config"
KUBECONFIG2="/tmp/${CLUSTER2}-kube.config"
touch $KUBECONFIG1
touch $KUBECONFIG2

if [[ $MACHTYPE == *"linux"* ]];then
  if [[ $MACHTYPE == *"x86_64"* ]];then
    ARCH_FILE="linux_amd64"
  elif [[ $MACHTYPE == *"arm64"* ]];then
    ARCH_FILE="linux_arm64"
  else
    echo "Not recognized architecture. Exiting..."
    exit 1
  fi
elif [[ $MACHTYPE == *"darwin"* ]];then
  if [[ $MACHTYPE == *"x86_64"* ]];then
    ARCH_FILE="darwin_amd64"
  elif [[ $MACHTYPE == *"arm64"* ]];then
    ARCH_FILE="darwin_arm64"
  else
    echo "Your architecture is \"$MACHTYPE\". Not recognized architecture. Exiting..."
    exit 1
  fi
else
  echo "Your architecture is \"$MACHTYPE\". Not recognized architecture. Exiting..."
  exit 1
fi

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




echo -e "\n${GRN}==> Information from K8s Cluster 1...${NC}}"
kubectl cluster-info --kubeconfig="$KUBECONFIG1"

echo -e "\n${GRN}==> Information from K8s Cluster 2...${NC}"
kubectl cluster-info --kubeconfig=$KUBECONFIG2

configk8s () {
  kubectl create ns consul --kubeconfig=$1
  # kubectl apply --kustomize="github.com/hashicorp/consul-api-gateway/config/crd?ref=v$API_GW_VERSION" --kubeconfig=$1
  kubectl create secret generic consul-ent-license --from-literal key=$CONSUL_LICENSE -n consul --kubeconfig=$1
  kubectl create secret generic consul-bootstrap-token --from-literal token=$CONSUL_TOKEN -n consul --kubeconfig=$1
}

install_consul () {
  local datacenter=$1

  cat - <<EOF | tee /tmp/consul-$1.yaml > /dev/null
global:
  enabled: true
  datacenter: $datacenter
  name: consul
  image: hashicorp/consul-enterprise:$CONSUL_VERSION
  imageK8S: hashicorp/consul-k8s-control-plane:$CONSUL_K8S_VERSION
  logLevel: debug
  # imageEnvoy: envoyproxy/envoy:v1.24.0
  tls:
    enabled: true
    enableAutoEncrypt: true
    verify: false
  acls:
    manageSystemACLs: true
    bootstrapToken:
      secretName: consul-bootstrap-token
      secretKey: token
  peering:
    enabled: true
  adminPartitions:
    enabled: true
  metrics:
    enabled: true
    enableGatewayMetrics: true
  enableConsulNamespaces: true
  enterpriseLicense:
    secretName: consul-ent-license
    secretKey: key
server:
  enabled: true
  replicas: 3
  bootstrapExpect: 3
  # affinity:
  extraConfig: |
    {
      "acl": {
        "tokens": {
          "initial_management": "$CONSUL_TOKEN",
          "dns": "$CONSUL_TOKEN",
          "agent": "$CONSUL_TOKEN"
        }
      }
    }
ui:
  enabled: true
  service:
    enabled: true
    type: LoadBalancer

meshGateway:
  enabled: true
  enableHealthChecks: false
  replicas: 1
  service:
    enabled: true


connectInject:
  enabled: true
  transparentProxy:
    defaultEnabled: true
  consulNamespaces:
    mirroringK8S: true

client:
  enabled: false
  grpc: true

controller:
  enabled: true

prometheus:
  enabled: true

# ingressGateways:
#   enabled: true
#   defaults:
#     replicas: 1
#     service:
#       type: LoadBalancer
#       ports:
#         - port: 443
#           nodePort: null
#         - port: 8080
#           nodePort: null
#     # affinity: ""
#   gateways:
#     - name: ingress-gateway
# terminatingGateways:
#   enabled: true

# apiGateway:
#   enabled: true
#   logLevel: debug
#   image: hashicorp/consul-api-gateway:$API_GW_VERSION
#   managedGatewayClass:
#     enabled: true
#     serviceType: LoadBalancer
EOF

  ./consul-k8s install -namespace $CONSUL_NAMESPACE -f /tmp/consul-$1.yaml -kubeconfig $2
}


install_partition () {

  local datacenter="$1"
  # local default_consul_server_ip="$(kubectl get svc -n consul consul-expose-servers -o jsonpath='{.status.loadBalancer.ingress[].ip}' --kubeconfig $KUBECONFIG1)"
  # if [ "$default_consul_serevr_ip" == "" ];then 
  #   echo ""
  #   echo "Consul servers does not have a LoadBalancer IP for \"consul-expose-servers\" service"
  #   echo ""
  #   exit 1
  # fi
  local external_ip=""

  while [ -z $external_ip ]; do 
    echo "Waiting for endpoint..."
    external_ip=$(kubectl get svc consul-expose-servers --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}" -n $CONSUL_NAMESPACE --kubeconfig $KUBECONFIG1)
    [ -z "$external_ip" ] && sleep 5
  done
  
  echo "... \"consul-expose-servers\" External IP is: " && echo $external_ip



  cat - <<EOF | tee /tmp/consul-$1-partition.yaml > /dev/null
global:
  enabled: true
  datacenter: $datacenter
  name: consul
  image: hashicorp/consul-enterprise:$CONSUL_VERSION
  imageK8S: hashicorp/consul-k8s-control-plane:$CONSUL_K8S_VERSION
  logLevel: debug
  tls:
    verify: false
    enabled: true
    enableAutoEncrypt: true
    caKey:
      secretName: $CONSUL_CA_KEY_SECRET
      secretKey: tls.key
    caCert:
      secretName: $CONSUL_CA_CERT_SECRET
      secretKey: tls.crt
  acls:
    manageSystemACLs: true
    bootstrapToken:
      secretName: consul-bootstrap-token
      secretKey: token
    partitionToken:
      secretName: consul-partitions-acl-token
      secretKey: token
  peering:
    enabled: true
  adminPartitions:
    enabled: true
    name: $CONSUL_PARTITION
  metrics:
    enabled: true
    enableGatewayMetrics: true
  enableConsulNamespaces: true
  enterpriseLicense:
    secretName: consul-ent-license
    secretKey: key
dns:
  enabled: true
  enableRedirection: true

server:
  enabled: false
externalServers:
  enabled: true
  hosts: ["$external_ip"]
  tlsServerName: server.dc1.consul
  k8sAuthMethodHost: "https://$CLUSTER2_ENDPOINT:443"
  # httpsPort: 8501

meshGateway:
  enabled: true
  enableHealthChecks: false
  replicas: 1
  service:
    enabled: true

connectInject:
  enabled: true
  transparentProxy:
    defaultEnabled: true
  consulNamespaces:
    mirroringK8S: true
client:
  enabled: false
  grpc: true
controller:
  enabled: true

# ingressGateways:
#   enabled: true
#   defaults:
#     replicas: 1
#     service:
#       type: LoadBalancer
#       ports:
#         - port: 443
#           nodePort: null
#         - port: 8080
#           nodePort: null
#     # affinity: ""
#   gateways:
#     - name: ingress-gateway
terminatingGateways:
  enabled: true
EOF

  helm repo add hashicorp https://helm.releases.hashicorp.com
  helm repo update
  helm install consul -n $CONSUL_NAMESPACE \
  -f /tmp/consul-$1-partition.yaml \
  hashicorp/consul \
  --kubeconfig $2 \
  --version $CONSUL_K8S_VERSION \
  --debug --wait
}

# meshconsul () {
#   # Applying Proxydefaults to go through local mesh gateways
#   kubectl apply -f - --kubeconfig=$1 <<EOF
# apiVersion: consul.hashicorp.com/v1alpha1
# kind: ProxyDefaults
# metadata:
#   name: global
# spec:
#   meshGateway:
#     mode: local
#   config:
#     protocol: http
# EOF

# }

copy_secrets () {
  # Function to copy secrets from Kubeconfig in $1 to Kubeconfig in $2. We are modifying the secret certs names to not be the default ones, which will be used
  # in the partition deployment (server-ca-cert and server-ca-key)

  # Let's delete any previous secrets that might exists in cluster 2
  kubectl delete secret consul-partitions-acl-token -n $CONSUL_NAMESPACE --kubeconfig $2
  kubectl delete secret $CONSUL_CA_CERT_SECRET -n $CONSUL_NAMESPACE --kubeconfig $2
  kubectl delete secret $CONSUL_CA_KEY_SECRET -n $CONSUL_NAMESPACE --kubeconfig $2
  kubectl delete secret consul-enterprise-license-acl-token -n $CONSUL_NAMESPACE --kubeconfig $2

  # Copying partition token from GKE 1 to GKE 2
  kubectl get secret consul-partitions-acl-token -n $CONSUL_NAMESPACE -o yaml --kubeconfig $1 | kubectl apply -n $CONSUL_NAMESPACE --kubeconfig $2 -f - 

  # Copying CA cert from K8s 1 to K8s 2 and naming it "server-ca-cert"
  kubectl get secret -n $CONSUL_NAMESPACE consul-ca-cert -o yaml --kubeconfig $1 | sed -e "s/name\: consul-ca-cert/name\: $CONSUL_CA_CERT_SECRET/g" | kubectl apply -n $CONSUL_NAMESPACE --kubeconfig $2 -f -

  # Copying CA Key from K8s 1 to K8s 2 and naming it ""
  kubectl get secret -n $CONSUL_NAMESPACE consul-ca-key -o yaml --kubeconfig $1 | sed -e "s/name\: consul-ca-key/name\: $CONSUL_CA_KEY_SECRET/g" | kubectl apply -n $CONSUL_NAMESPACE --kubeconfig $2 -f -
}

create_demo () {
  mkdir -p $DEMO_TMP

  # Creating a backend service manifest
  cat - <<EOF | tee $DEMO_TMP/backend.yaml > /dev/null
apiVersion: v1
kind: Service
metadata:
  name: backend
  labels:
    app: dcanadillas-demo
    tier: backend
spec:
  selector:
    myapp: dcanadillas-demo
    tier: backend
  ports:
  - protocol: TCP
    port: 8080
    targetPort: http
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend
  labels:
    app: dcanadillas-demo
    tier: back
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  labels:
    app: dcanadillas-demo
    myapp: dcanadillas-demo
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      myapp: dcanadillas-demo
      tier: backend
  template:
    metadata:
      labels:
        app: dcanadillas-demo
        myapp: dcanadillas-demo
        tier: backend
      annotations:
        consul.hashicorp.com/connect-inject: "true"
        consul.hashicorp.com/connect-service: "backend"
    spec:
      serviceAccount: backend
      containers:
      - name: backend
        image: hcdcanadillas/pydemo-back:v1.2
        imagePullPolicy: Always
        ports:
          - name: http
            containerPort: 8080
        env:
          - name: PORT
            value: "8080"
EOF

  # Creating a demo frontend service manifest
  cat - <<EOT | tee $DEMO_TMP/frontend.yaml > /dev/null
apiVersion: v1
kind: Service
metadata:
  name: frontend
  labels:
    myapp: dcanadillas-demo
    tier: front
spec:
  selector:
    myapp: dcanadillas-demo
    tier: front
  ports:
  - protocol: TCP
    port: 8080
    targetPort: http
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: frontend
  labels:
    app: dcanadillas-demo
    tier: front
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: dcanadillas-demo
    #myapp: dcanadillas-demo
    tier: front
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dcanadillas-demo
      tier: front
  template:
    metadata:
      labels:
        app: dcanadillas-demo
        tier: front
        myapp: dcanadillas-demo
      annotations:
        consul.hashicorp.com/connect-inject: "true"
        consul.hashicorp.com/connect-service: "frontend"
        consul.hashicorp.com/service-tags: v1.3
        # consul.hashicorp.com/connect-service-upstreams: "backend:9090"
    spec:
      serviceAccountName: frontend
      containers:
        - name: frontend
          image: hcdcanadillas/pydemo-front:v1.3
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: PORT
              value: "8080"
            - name: BACKEND_URL
              # value: "http://backend:8080"
              value: "http://backend.virtual.second.ap.consul:8080"
EOT

  cat - <<EOF | tee $DEMO_TMP/proxydefaults.yaml > /dev/null
apiVersion: consul.hashicorp.com/v1alpha1
kind: ProxyDefaults
metadata:
  name: global
spec:
  meshGateway:
    mode: local
  config:
    protocol: http
EOF

  cat - <<EOF | tee $DEMO_TMP/exported-backend.yaml > /dev/null
apiVersion: consul.hashicorp.com/v1alpha1
kind: ExportedServices
metadata:
  name: second ## The name of the partition containing the service
spec:
  services:
    - name: backend ## The name of the service you want to export
      namespace: default
      consumers:
      - partition: default ## The name of the partition connection that receives the service
    - name: mesh-gateway
      namespace: default
      consumers:
        - partition: default
EOF

  cat - <<EOF | tee $DEMO_TMP/intention-frontend_default-backend_$CONSUL_PARTITION.yaml > /dev/null
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: frontend-default-to-backend-second
spec:
  destination:
    name: backend
  sources:
   - name: frontend
     action: allow
     partition: default
EOF

  echo ""
  echo "All demo yaml files have been saved in directory \"$DEMO_TMP\": "
  ls -l $DEMO_TMP
  echo ""

}

deploy_demoapp () {
  kubectl apply -f $DEMO_TMP/proxydefaults.yaml --kubeconfig $KUBECONFIG1
  kubectl apply -f $DEMO_TMP/proxydefaults.yaml --kubeconfig $KUBECONFIG2
  kubectl apply -f $DEMO_TMP/frontend.yaml --kubeconfig $KUBECONFIG1
  kubectl apply -f $DEMO_TMP/backend.yaml --kubeconfig $KUBECONFIG2
  kubectl apply -f $DEMO_TMP/exported-backend.yaml --kubeconfig $KUBECONFIG2
  kubectl apply -f $DEMO_TMP/intention-frontend_default-backend_$CONSUL_PARTITION.yaml --kubeconfig $KUBECONFIG2
}


# FUN STARTS HERE
curl -Ls https://releases.hashicorp.com/consul-k8s/${CONSUL_K8S_VERSION}/consul-k8s_${CONSUL_K8S_VERSION}_${ARCH_FILE}.zip -o consul_k8s.zip
unzip -o consul_k8s.zip

echo -e "\n${GRN}==> Configuring K8s cluster $CLUSTER1... ${NC}"
configk8s $KUBECONFIG1
echo -e "\n${GRN}==> Configuring K8s cluster $CLUSTER2... ${NC}"
configk8s $KUBECONFIG2

echo ""
read -p "${YELL}Continue to install Consul (Ctrl-C to cancel)...${NC}"
echo ""

# ---- Installing Consul in firts K8s cluster----
echo -e "\n${GRN}==> Installing Consul \"$DC1\" in K8s cluster \"$CLUSTER1\"... ${NC}"
install_consul $DC1 $KUBECONFIG1
# ---------------------------

# ---- Creating required secret in second K8s cluster----
echo -e "\n${GRN}==> Copying required K8s secrets for the Admin Partition installation... ${NC}"
copy_secrets $KUBECONFIG1 $KUBECONFIG2
# ---------------------------


echo -e "\n${GRN}==> Listing pods and secrets in namespace \"$CONSUL_NAMESPACE\" in cluster \"$CLUSTER1\"... ${NC}"
kubectl get po,secrets -n $CONSUL_NAMESPACE --kubeconfig $KUBECONFIG1

echo ""
read -p "${YELL}Continue to install Consul partition \"$CONSUL_PARTITION\" (Ctrl-C to cancel)... ${NC}"
echo ""


echo -e "\n${GRN}==> Installing Consul partition \"$CONSUL_PARTITION\" in K8s cluster \"$CLUSTER2\"... ${NC}"
install_partition $DC1 $KUBECONFIG2


echo -e "\n${GRN}==> Saving yaml files in \"$DEMO_TMP\"... ${NC}"
create_demo

echo ""
read -p "${YELL}Do you want to deploy demo applications manifests in \"$DEMO_TMP\"? (You need to type: \"yes\" or \"y\"): ${NC}" DEPLOY_APP
echo "" 

case $DEPLOY_APP in
  [Yy]es|[Yy])
    deploy_demoapp
    ;;
  *)
    echo -e "\n${DGRN}Don't forget to deploy your yaml files in \"$DEMO_TMP\"... ${NC}\n"
    ;;
esac
