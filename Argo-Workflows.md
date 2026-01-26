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
kubectl create namespace argo-workflows
```

## AppProject Source und Destinations

Das ArgoCD AppProject muss Rechte erhalten, um Argo Workflows aus dem [argo-helm Github Repo](https://github.com/argoproj/argo-helm) in den neu erstellten Namespace zu deployen. 

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
    - namespace: argo-workflows
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
    namespace: argo-workflows
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
          full: true
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
  namespace: argo-workflows
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
  namespace: argo-workflows
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

Für die Verwendung von `ClusterWorkflowTemplates` durch den ServiceAccount bedarf es einer `ClusterRole`:

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

Im `argocd` Namespace läuft ein Pod, dessen Name mit `argocd-server-` beginnt. Für diesen muss Port-Forwarding eingerichtet werden, zum Beispiel mit dem `k9s` Tool. Danach kann ArgoCD auf [localhost:8080](localhost:8080) erreicht werden. Der initiale Benutzer*innenname ist *admin*, das Passwort befindet sich im Secret `argocd-initial-admin-secret` im `argocd` Namespace. 

In ArgoCD muss jetzt die `Application` von Argo Workflows synchronisiert werden.

## Auf Argo Workflows im Browser zugreifen

In `k9s` oder über `kubectl` muss jetzt Port-Forwarding für den im `argo-workflows` Namespace laufenden Pod, dessen Name mit `argo-workflows-server` beginnt, eingerichtet werden. Dann kann Argo Workflows im Browser über [localhost:2746](localhost:2746) erreicht werden.

## Authentifizierung mit Argo Workflows

Für den erstellten ServiceAccount muss jetzt ein Bearer Token generiert werden, mit dem man sich mit Argo Workflows authentifizieren kann.  

https://argo-workflows.readthedocs.io/en/latest/access-token/#access-token

Das Skript `bootstrap/getbearer.sh` implementiert den Prozess und holt einen Bearer Token für den erstellten ServiceAccount, der in das Feld in Argo Workflows gepastet werden kann. 


## Archivierung von Logs

Wenn von einem Workflow ein Pod gestaret wird, werden dessen Logs nach dessen Beendigung nicht standardmäßig archiviert und auch nicht in der Argo Workflows UI angezeigt. 

Dazu muss das *Archive Logs* Feature konfiguriert werden: https://argo-workflows.readthedocs.io/en/latest/configure-archive-logs/

Dafür muss auch ein *Artifact Repository* eingerichtet werden, wo die Logs gespeichert werden. Eine Option dafür könnte **Azure Blob Storage** sein: https://argo-workflows.readthedocs.io/en/latest/configure-artifact-repository/

### POC Setup für Log Archivierung

Für den POC kann auch ein lokales Minio Setup herhalten. Die Installationsschritte sind zusätzlich zu hier auch in `deploy.sh` festgehalten.

Minio installieren:

```
kubectl apply -f ../dev/argo-workflows-minio.yaml

helm repo add minio https://charts.min.io/
helm repo update

helm install argo-artifacts minio/minio -n argo-workflows \
  --set "fullnameOverride=argo-artifacts" \
  --set "mode=standalone" \
  --set "service.type=ClusterIP" \
  --set "buckets[0].name=argo-artifacts" \
  --set "buckets[0].policy=none"
```

(Optional) Minio UI port-forwarden, um auf die UI Zugriff zu erhalten (alternativ über k9s). Danach sollte Minio über `localhost:9001` erreichbar sein.

```
export MINIO_POD_NAME=$(kubectl get pods --namespace argo-workflows -l "release=argo-artifacts" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward $MINIO_POD_NAME 9000 --namespace argo-workflows &
kubectl port-forward $MINIO_POD_NAME 9001 --namespace argo-workflows &
```


Um sich anzumelden, muss das Kubernetes Secret mit den Credentials dekodiert werden:

```
kubectl get secret argo-artifacts -o jsonpath="{.data.rootUser}" | base64 --decode

kubectl get secret argo-artifacts -o jsonpath="{.data.rootPassword}" | base64 --decode
```

Mit diesen Credentials kann man sich in der Minio UI anmelden, insofern das Port Forwarding aktiviert wurde.


Der Zugriff auf Minio durch Argo Workflows wird über eine ConfigMap konfiguriert, in diesem Repo befindet sie sich in `dev/argo-workflows-minio.yaml`. 

In den Workflows und WorkflowTemplates selber muss `archiveLogs` aktiviert und die ConfigMap der Minio Artifact Registry referenziert werden. Damit die ConfigMap referenziert werden kann, müssen die Workflows und WorkflowTemplates im gleichen Namespace liegen. 

Beispiel aus `dev/argo-workflows-examples.yaml`:

```
...
kind: Workflow
metadata:
    namespace: argo-workflows
...
spec:
  archiveLogs: true
  artifactRepositoryRef:
    configMap: workflow-controller-configmap
    key: artifactRepository
```

## Workflows und WorkflowTemplates anlegen

Ein Argo Workflow definiert eine konkrete ausführbare Pipeline, während ein Argo WorkflowTemplate eine wiederverwendbare Vorlage ist, aus der Workflows erst instanziiert werden.

Man kann sowohl Workflows, als auch WorkflowTemplates deklarativ anlegen, wobei für unseren Anwendungszweck WorkflowTemplates geeigneter sind. Wird ein Workflow deklarativ angelegt, wird er sofort ausgeführt und verschwindet nach einer konfigurierten Zeit. Ein WorkflowTemplate hingegen ist persistent, und aus ihm können über die Argo Workflows UI Instanzen eines Workflows mit vor der Ausführung konfigurierbaren Parametern gestartet werden.

Ein Beispiel eines Workflows befindet sich in `dev/argo-workflows-examples.yaml`.

In `dev/argo-workflows-kafka-template.yaml` sind zwei minimale WorkflowTemplates implementiert, mit der Operationen auf dem Kafka Cluster ausgeführt werden können.

Das WorkflowTemplate zum Auflisten von Topics benutzt ein Skript, welches als ConfigMap hinterlegt ist. Das WorkflowTemplate zur Änderung der Retention Zeit eines Topics verwendet ein Inline Skript direkt im Template. Der Vorteil dessen ist, dass so einfach Parameter angegeben werden können, wie in dem Fall z.B die Retention Zeit und der Name des Zieltopics. 

Der lokale POC Kafka Cluster verlangt keine Authentifizierung. In einem Production Setup könnte man das für die Authentifizierung nötige Properties File vorab in einem Secret in OpenShift ablegen, und in den Workflow als Volume einbinden. Der Vorgang ist (abgesehen vom eingecheckten Secret) in den Kommentaren skizziert:

```
kubectl apply -f dev/argo-workflows-kafka-template.yaml 
```

```
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: kafka-poc-list-topics
  namespace: argo-workflows
spec:
  archiveLogs: true
  artifactRepositoryRef:
    configMap: workflow-controller-configmap
    key: artifactRepository
  serviceAccountName: argo-workflow-testuser
  entrypoint: list-topics
  templates:
    - name: list-topics
      container:
        name: main
        image: confluentinc/cp-server:7.5.0
        command: ["/bin/bash"]
        args: ["-c", 'cd / && ./tmp/list-topics.sh']
        volumeMounts:
          - mountPath: "/tmp"
            name: kafka-poc-commands
 #         - mountPath: "/mnt"
 #           name: kafka-poc-user-properties
      volumes:
        - name: kafka-poc-commands
          configMap:
            name: kafka-poc-commands
            defaultMode: 0755
  #      - name: kafka-poc-user-properties
  #        secret:
  #          secretName: kafka-poc-user-properties
  ttlStrategy:
    secondsAfterCompletion: 300
  podGC:
    strategy: OnPodCompletion
---
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: kafka-poc-change-retention
  namespace: argo-workflows
spec:
  archiveLogs: true
  artifactRepositoryRef:
    configMap: workflow-controller-configmap
    key: artifactRepository
  serviceAccountName: argo-workflow-testuser
  entrypoint: change-retention
  arguments:
    parameters:
      - name: topic
      - name: retention_ms
  templates:
    - name: change-retention
      container:
        image: confluentinc/cp-server:7.5.0
        command: ["/bin/bash"]
        args:
          - -c
          - |
            echo "=== BEFORE ==="
            kafka-configs \
              --bootstrap-server kafka-poc.kafka-confluent-poc.svc.cluster.local:9092 \
              --entity-type topics \
              --entity-name {{workflow.parameters.topic}} \
              --describe

            echo ""
            echo "=== APPLY NEW RETENTION ==="
            kafka-configs \
              --bootstrap-server kafka-poc.kafka-confluent-poc.svc.cluster.local:9092 \
              --entity-type topics \
              --entity-name {{workflow.parameters.topic}} \
              --alter \
              --add-config retention.ms={{workflow.parameters.retention_ms}}

            echo ""
            echo "=== AFTER ==="
            kafka-configs \
              --bootstrap-server kafka-poc.kafka-confluent-poc.svc.cluster.local:9092 \
              --entity-type topics \
              --entity-name {{workflow.parameters.topic}} \
              --describe
  ttlStrategy:
    secondsAfterCompletion: 300
  podGC:
    strategy: OnPodCompletion
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-poc-commands
  namespace: argo-workflows
data:
  list-topics.sh: >-
    #!/bin/bash 

    cd /bin

    echo 'list topics:'

    kafka-topics --list --bootstrap-server kafka-poc.kafka-confluent-poc.svc.cluster.local:9092
#---
#kind: Secret
#apiVersion: v1
#metadata:
#  name: kafka-poc-user-properties
#  namespace: argo-workflows
#data:
#  kafka_user.properties: c2FzbC5qYWFzLmNvbmZpZz1vcmcuYXBhY2hlLmthZmthLmNvbW1vbi5zZWN1cml0eS5wbGFpbi5QbGFpbkxvZ2luTW9kdWxlIHJlcXVpcmVkIHVzZXJuYW1lPSJrYWZrYSIgcGFzc3dvcmQ9ImthZmthIjsKc2FzbC5tZWNoYW5pc209UExBSU4Kc2VjdXJpdHkucHJvdG9jb2w9U0FTTF9QTEFJTlRFWFQ=
#type: Opaque

# Example for kafka_user.properties in case authentification to kafka was necessary
# sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="kafka" password="kafka";
# sasl.mechanism=PLAIN
# security.protocol=SASL_PLAINTEXT
```

## LDAP Anbindung und Auth

Die Anbindung an LDAP erfolgt in Argo Workflows indirekt über den Dex‑Identity‑Provider von Argo CD, der als OIDC‑Brücke dient und Benutzeranfragen gegen das LDAP‑Verzeichnis authentifiziert, während Argo Workflows anschließend dessen SSO‑Token zur Anmeldung verwendet.

Zur Einrichtung sind auf Argo Workflows Seite paar Änderungen in der `workflow-controller-configmap.yaml` ConfigMap notwendig, auf ArgoCD Seite in der `argocd-cm` ConfigMap. Diese sind hier dokumentiert:

https://argo-workflows.readthedocs.io/en/latest/argo-server-sso/

https://argo-workflows.readthedocs.io/en/latest/argo-server-sso-argocd/

Optional kann auch RBAC zur SSO hinzugefügt werden. 
