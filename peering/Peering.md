# Consul Cluster Peering

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
kubectl apply -f peering/peering-dialer --kubeconfig $KUBECONFIG_DC2
```