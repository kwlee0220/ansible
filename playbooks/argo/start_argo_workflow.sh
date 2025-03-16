#!/bin/bash

#kubectl patch deployment -n argo argo-server --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["server", "--auth-mode=server"]}]'
kubectl -n argo port-forward deployment/argo-server 2746:2746 --address 0.0.0.0
#argo server --auth-mode=server