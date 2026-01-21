kubectl create namespace confluent
kubectl create namespace argocd
kubectl create namespace kafka-confluent-poc

kustomize build --enable-helm . | kubectl apply -f - # currently command fails with helm@4
kubectl apply -f argocd.yaml
kubectl apply -f cfk.yaml
kubectl apply -f ../dev/cfk-demo.yaml
kubectl apply -f ../dev/cfk-demo-kafka-configuration.yaml
kubectl apply -f ../ldap/ldap.yaml

# deploy argo workflows
kubectl create namespace argoworky

kubectl apply -f ../dev/argo-workflows.yaml
kubectl apply -f ../dev/aw-rbac/example-rb.yaml
kubectl apply -f ../dev/aw-rbac/example-role.yaml
kubectl apply -f ../dev/aw-rbac/example-sa.yaml
kubectl apply -f ../dev/aw-rbac/example-clusterrole.yaml
kubectl apply -f ../dev/aw-rbac/example-crb.yaml


helm repo add minio https://charts.min.io/
helm repo update

helm install argo-artifacts minio/minio \
  --set fullnameOverride=argo-artifacts \
  --set mode=standalone \
  --set service.type=LoadBalancer

kubectl port-forward pod/argo-artifacts-<POD-ID> 9001:9001

Decode the argo-artifacts secret with k9s, log in to minio UI at localhost:9001

Create a bucket named "my-bucket"