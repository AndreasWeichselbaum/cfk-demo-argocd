kubectl create namespace confluent
kubectl create namespace argocd
kubectl create namespace kafka-confluent-poc
kustomize build --enable-helm . | kubectl apply -f -
kubectl apply -f argocd.yaml
kubectl apply -f cfk.yaml
kubectl apply -f ../dev/cfk-demo.yaml
kubectl apply -f ../ldap/ldap.yaml
