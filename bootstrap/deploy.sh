# Create namespaces
kubectl create namespace confluent
kubectl create namespace argocd
kubectl create namespace kafka-confluent-poc
kubectl create namespace argo-workflows

# Deploy ArgoCD
kustomize build --enable-helm . | kubectl apply -f - # currently command fails with helm@4
kubectl apply -f argocd.yaml

# Deploy CFK
kubectl apply -f cfk.yaml
kubectl apply -f ../dev/cfk-demo.yaml
kubectl apply -f ../dev/cfk-demo-kafka-configuration.yaml
kubectl apply -f ../ldap/ldap.yaml

# Deploy Argo Workflows
kubectl apply -f ../dev/argo-workflows.yaml
kubectl apply -f ../dev/aw-rbac/example-rb.yaml
kubectl apply -f ../dev/aw-rbac/example-role.yaml
kubectl apply -f ../dev/aw-rbac/example-sa.yaml
kubectl apply -f ../dev/aw-rbac/example-clusterrole.yaml
kubectl apply -f ../dev/aw-rbac/example-crb.yaml

# Deploy Minio as an Artifact Repository for Argo Workflows
kubectl apply -f ../dev/argo-workflows-minio.yaml

helm repo add minio https://charts.min.io/
helm repo update

helm install argo-artifacts minio/minio -n argo-workflows \
  --set "fullnameOverride=argo-artifacts" \
  --set "mode=standalone" \
  --set "service.type=ClusterIP" \
  --set "buckets[0].name=argo-artifacts" \
  --set "buckets[0].policy=none"

# Port-forward if you want to access the Minio UI
# export MINIO_POD_NAME=$(kubectl get pods --namespace argo-workflows -l "release=argo-artifacts" -o jsonpath="{.items[0].metadata.name}")
# kubectl port-forward $MINIO_POD_NAME 9000 --namespace argo-workflows &
# kubectl port-forward $MINIO_POD_NAME 9001 --namespace argo-workflows &
