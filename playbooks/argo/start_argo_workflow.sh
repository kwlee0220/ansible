#!/bin/bash

minikube start --memory=no-limit --cpus=no-limit
kubectl -n argo port-forward deployment/argo-server 2746:2746 --address 0.0.0.0