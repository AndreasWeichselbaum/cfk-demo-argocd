# Argo Workflows

Writeup / Überblick über den lokalen Setup Prozess

## Vorbedingungen

- Lokaler Kubernetes Cluster (z.B Rancher, k3d, minikube...)
- ArgoCD im lokalen k8s Cluster aufgesetzt (siehe `bootstrap/argocd.yaml`)
- Für Kafka-spezifische Workflows: CFK lokal aufgesetzt (siehe `bootstrap/cfk.yaml`)

Für das Aufsetzen von ArgoCD und CFK können die Befehle in `bootstrap/deploy.sh` verwendet werden. 

## Kubernetes Namespace

Argo Workflows wird in einem eigenen Kubernetes Namespace deployed:

```
kubectl create namespace argoworky
```

## AppProject Source und Destinations

Das ArgoCD AppProject muss Rechte erhalten, Argo Workflows aus dem [argo-helm Github Repo](https://github.com/argoproj/argo-helm) in den neu erstellten Namespace zu deployen. 

```
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: kafka-confluent-poc-dev
  namespace: argocd
...
spec:
...
  sourceRepos:
    - 'https://argoproj.github.io/argo-helm'
...
  destinations:
    - namespace: argoworky
      server: https://kubernetes.default.svc
      name: in-cluster
...
```

## Argo Application 

Argo Workflows wird über eine ArgoCD Application deployed. Diese ist in diesem Repository unter `dev/argo-workflows.yaml` zu finden. Beispielsconfig:

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-workflows
  namespace: argocd
spec:
  project: kafka-confluent-poc-dev
  destination:
    #server: https://kubernetes.default.svc
    namespace: argoworky
    name: in-cluster
  syncPolicy:
    syncOptions:
    - ServerSideApply=true
  source:
    chart: argo-workflows
    repoURL: https://argoproj.github.io/argo-helm
    targetRevision: 0.47.0
    helm:
      values: |
        crds:
          full: false
```

```
kubectl apply -f ../dev/argo-workflows.yaml
```

## RBAC

Für diesen POC ist eine LDAP Anbindung out-of-scope. Stattdessen wird als Argo Workflows User ein ServiceAccount angelegt und ihm Rechte vergeben. Die Manifeste befinden sich in `dev/aw-rbac`.

### ServiceAccount

```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argo-workflow-testuser
  namespace: default
```

```
kubectl apply -f ../dev/aw-rbac/example-sa.yaml
```

### Rechte an namespaced Argo Workflow Ressourcen

Role:

```
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argo-workflow-testuser
  namespace: default
rules:
- apiGroups:
    - argoproj.io
    - ""
  resources:
    - cronworkflows
    - eventsources
    - sensors
    - workflows
    - workfloweventbindings
    - workflowtemplates
    - workflowtaskresults
    - pods
    - secrets
  verbs:
    - get
    - list
    - watch
    - create
    - update
    - patch
    - delete
```

```
kubectl apply -f ../dev/aw-rbac/example-role.yaml
kubectl apply -f ../dev/aw-rbac/example-rb.yaml
```


Die `Role` kann mit einem `RoleBinding` dem ServiceAccount vergeben werden (siehe `dev/aw-rbac/example-rb.yaml`).


### Cluster-weite Rechte an Cluster Workflow Templates

Für die Verwendung von `ClusterWorkflowTemplates` durch den ServiceAccount bedarf es eines `ClusterRole`s:

```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argo-workflows-clusterworkflowtemplates
rules:
  - apiGroups:
      - argoproj.io
    resources:
      - clusterworkflowtemplates
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete
```

```
kubectl apply -f ../dev/aw-rbac/example-clusterrole.yaml
kubectl apply -f ../dev/aw-rbac/example-crb.yaml
```

Die `ClusterRole` kann mit einem `ClusterRoleBinding` dem ServiceAccount vergeben werden (siehe `dev/aw-rbac/example-crb.yaml`).

## Argo Workflows über ArgoCD deployen

Im `argocd` Namespace läuft ein Pod, dessen Name mit `argocd-server-` beginnt. Für diesen muss Port-Forwarding eingerichtet werden, zum Beispiel mit dem `k9s` tool. Danach kann ArgoCD auf [localhost:8080](localhost:8080) erreicht werden. Der initiale Benutzer*innename ist *admin*, das Passwort befindet sich im Secret `argocd-initial-admin-secret` im `argocd` Namespace. 

In ArgoCD kann jetzt die `Application` von Argo Workflows synchronisiert werden.

## Auf Argo Workflows im Browser zugreifen

In `k9s` oder über `kubectl` muss jetzt Port-Forwarding für den im `argoworky` Namespace laufenden Pod, dessen Name mit `argo-workflows-server` beginnt, eingerichtet werden. Dann kann Argo Workflows im Browser über [localhost:2746](localhost:2746) erreicht werden.

## Authentifizierung mit Argo Workflows

Für den erstellten ServiceAccount muss jetzt ein Bearer Token generiert werden, mit dem man sich mit Argo Workflows authentifizieren kann.  

https://argo-workflows.readthedocs.io/en/latest/access-token/#access-token

Das Skript `bootstrap/getbearer.sh` implementiert den Prozess und holt einen Bearer Token für den erstellten ServiceAccount, der in das Feld in Argo Workflows gepastet werden kann. 


## Archivierung von Logs

Wenn von einem Workflow ein Pod gestaret wird, werden dessen Logs nach dessen Beendigung nicht standardmäßig archiviert und auch nicht in der Argo Workflows UI angezeigt. 

Dazu muss das *Archive Logs* Feature konfiguriert werden: https://argo-workflows.readthedocs.io/en/latest/configure-archive-logs/

Dafür muss auch ein *Artifact Repository* eingerichtet werden, wo die Logs gespeichert werden. Eine Option dafür könnte Azure Blob Storage sein: https://argo-workflows.readthedocs.io/en/latest/configure-artifact-repository/

### POC Setup für Log Archivierung

Für den POC kann auch ein lokales Minio Setup herhalten. Die Installationsschritte sind zusätzlich zu hier auch in `deploy.sh` festgehalten.

Minio installieren:

```
helm repo add minio https://charts.min.io/
helm repo update

helm install argo-artifacts minio/minio \
  --set fullnameOverride=argo-artifacts \
  --set mode=standalone \
  --set service.type=LoadBalancer
```

Minio UI port-forwarden (alternativ über k9s):

```
kubectl port-forward pod/argo-artifacts-<ID> 9001:9001 &
```

Jetzt sollte Minio über `localhost:9001` erreichbar sein.

Um sich anzumelden, muss das Kubernetes Secret mit den Credentials dekodiert werden:

```
kubectl get secret argo-artifacts -o jsonpath="{.data.rootUser}" | base64 --decode

kubectl get secret argo-artifacts -o jsonpath="{.data.rootPassword}" | base64 --decode

```

Mit diesen Credentials kann man sich in der Minio UI anmelden.

Über die UI muss jetzt das Bucket `my-bucket` unter *Administrator -> Buckets -> Create Bucket* angelegt werden.


Der Zugriff auf Minio wird über eine ConfigMap konfiguriert, in diesem Repo befindet sie sich in `dev/argo-workflows-minio.yaml`. 

Im Workflow selber muss `archiveLogs` aktiviert und die ConfigMap der Minio Artifact Registry referenziert werden. Beispiel aus `dev/argo-workflows-examples.yaml`:

```
...
kind: Workflow
...
spec:
  archiveLogs: true
  artifactRepositoryRef:
    configMap: workflow-controller-configmap
    key: artifactRepository
```