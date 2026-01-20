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
