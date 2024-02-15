kustomize build --enable-helm . | kubectl apply -f -
kubectl apply -f argocd.yaml
