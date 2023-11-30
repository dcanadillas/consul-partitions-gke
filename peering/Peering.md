# Consul Cluster Peering

## Install Consul Cluster in a third K8s cluster

```
consul-k8s install -f peering/consul-dc2-servers.yaml
```

## Create and configure Peering

Let's configure the Peer through Mest Gateways in the two K8s clusters of default partition:
```
kubectl apply -f peering/mesh-peering.yaml --kubeconfig $KUBECONFIG_DC1
kubectl apply -f peering/mesh-peering.yaml --kubeconfig $KUBECONFIG_DC2
```


Peer DC1 and DC2 clusters with default partitions:

```
kubectl apply -f peering/peering-acceptor.yaml --kubeconfig $KUBECONFIG_DC1
```

Getting the peering token and secret from first DC:
```
TOKEN_STATUS="$(kubectl get peeringacceptors --kubeconfig $KUBECONFIG_DC1 -o jsonpath='{.status.conditions[].status}' dc2-default)"
PEERING_SECRET="$(kubectl get peeringacceptors --kubeconfig $KUBECONFIG_DC1 -o jsonpath='{.status.secret.name}' dc2-default)"
```

And we create the Peering token secret in DC2 from the one created in DC1
  
```
kubectl --kubeconfig $KUBECONFIG_DC1 get secret $PEERING_SECRET -o yaml | kubectl --kubeconfig $KUBECONFIG_DC2 apply -f -
```

Creating the peering:
```
kubectl apply -f peering/peering-dialer.yaml --kubeconfig $KUBECONFIG_DC2
```

Deploy the `backend` application now in `dc2`:
```
kubectl apply -f demo-app/backend-dc2.yaml --kubeconfig $KUBECONFIG_DC2
```

Export the service to DC1:
```
kubectl apply -f peering/exported-backend.yaml --kubeconfig $KUBECONFIG_DC2
```

Apply the intention between peers:
```
kubectl apply -f peering/intention-front_dc1-to-back_dc2.yaml --kubeconfig $KUBECONFIG_DC2
```