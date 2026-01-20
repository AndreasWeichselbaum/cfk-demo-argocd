
# source 
# https://argo-workflows.readthedocs.io/en/latest/access-token/#token-creation

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: testuser.service-account-token
  annotations:
    kubernetes.io/service-account.name: argo-workflow-testuser
type: kubernetes.io/service-account-token
EOF

ARGO_TOKEN="Bearer $(kubectl get secret testuser.service-account-token -o=jsonpath='{.data.token}' | base64 --decode)"
echo $ARGO_TOKEN