---
applyTo: '**'
---
# **Fase 3: Guia de Implementação para Infraestrutura como Código (IaC) e Dependências**

### 🎯 **Princípios Norteadores**
- **Declarativo & Parametrizado**: Todo ambiente deve ser definido como código e configurável via parâmetros.
- **Ambiente Agnóstico**: A mesma definição (`Deployment`, `Service`) deve funcionar em Dev, Staging e Prod, variando apenas os valores.
- **Segurança "Shift-Left"**: Segredos e configurações sensíveis são injetados no runtime, nunca embutidos no código-fonte ou nos manifests.
- **Clareza e Reuso**: Utilizar helpers e templates padronizados para reduzir duplicação e facilitar a manutenção.

---

## **Seção 3.1: Helm Charts Estruturados**

### **Objetivo**: Criar um pacote Helm portável, seguro e configurável que encapsule toda a aplicação.

### **Tarefas Detalhadas e Melhores Práticas**:

**1. Estrutura do Chart Base**
```bash
# Criar a estrutura inicial
helm create meuapp-chart
cd meuapp-chart
# A estrutura gerada é um bom ponto de partida. Remova o que não for usar.
rm -rf ./templates/tests/ # Exemplo: remover testes de exemplo
```

**2. Parametrização Avançada dos Templates**
O segredo está no `values.yaml` e nos conditionais nos templates. Seu `values.yaml` global deve definir todos os parâmetros possíveis, mesmo que vazios. Os arquivos de ambiente (`values-dev.yaml`) sobrescrevem apenas o necessário.

- **Exemplo de `values.yaml` com boas práticas**:
```yaml
# values.yaml (template principal)
image:
  repository: "gcr.io/meu-projeto/meuapp" # *Sempre* parametrizado
  tag: "latest" # Tag padrão, SEMPRE sobrescrita em CI/CD
  pullPolicy: IfNotPresent

resources:
  enabled: false # Habilitar apenas em produção
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "500m"

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 80

ingress:
  enabled: false
  className: "nginx"
  annotations: {}
  hosts:
    - host: "meuapp.local"
      paths:
        - path: /
          pathType: Prefix
```

- **No template `deployment.yaml`**, use essas variáveis de forma condicional:
```yaml
# templates/deployment.yaml (trecho)
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          {{- if .Values.resources.enabled }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          {{- end }}
          livenessProbe:
            {{- toYaml .Values.livenessProbe | nindent 12 }}
```

**3. Helpers e Nomenclatura (`_helpers.tpl`)**
O arquivo `_helpers.tpl` é essencial para lógica reutilizável e nomes consistentes.

```tpl
{{/* Nome completo do app */}}
{{- define "meuapp.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Labels padrão */}}
{{- define "meuapp.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
```
*Use nos templates:* `{{ include "meuapp.fullname" . }}`

**4. `Chart.yaml` Completo e com Dependências**
```yaml
# Chart.yaml
apiVersion: v2
name: meuapp
description: A Helm chart for MeuApp Microservice
type: application
version: 0.1.0 # Use SemVer. Aumente na CI.
appVersion: "1.0.0" # Versão da sua aplicação

# Dependências IMPORTANTES: Banco, Cache, etc.
dependencies:
  - name: postgresql
    version: "~12.0.0"
    repository: "https://charts.bitnami.com/bitnami"
    condition: postgresql.enabled
    tags:
      - database
  - name: redis
    version: "~17.0.0"
    repository: "https://charts.bitnami.com/bitnami"
    condition: redis.enabled
    tags:
      - cache
```

**Comando para atualizar dependências:**
```bash
helm dependency update ./meuapp-chart
```

---

## **Seção 3.2: Gerenciamento de Dependências do Cluster**

### **Objetivo**: Definir e provisionar serviços de suporte de forma confiável e segura.

### **Decisão Crítica: Local vs. Gerenciado**

| Dependência | Provisão Local (Dev/Minikube) | Provisão Gerenciada (GCP Prod) | Justificativa |
| :--- | :--- | :--- | :--- |
| **PostgreSQL** | Bitnami Helm Chart | **Cloud SQL** | Gerenciado oferece backups automáticos, alta disponibilidade, patches de segurança e menor custo operacional. |
| **Redis** | Bitnami Helm Chart | **Memorystore** | Baixa latência garantida, failover automático e integração nativa de segurança com IAM. |
| **RabbitMQ** | Bitnami Helm Chart | **Cloud Pub/Sub** ou **Cloud Run para RMQ** | Para novas apps, prefira Pub/Sub (serverless, escalável). Para migrações, considere o Cloud Run. |
| **Observabilidade (OTEL, Prometheus, Jaeger)**| Helm Charts da Comunidade | **Cloud Monitoring + Cloud Trace + Managed Service for Prometheus** | Centralização de métricas, logs e traços, sem overhead de gerenciamento. Otimizado para custo e performance. |

### **Provisionamento Local para Desenvolvimento**
Crie um script `scripts/setup-dependencies.sh` para padronizar:

```bash
#!/bin/bash
# Adicionar repositórios
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Instalar dependências no namespace 'deps'
kubectl create namespace deps --dry-run=client -o yaml | kubectl apply -f -

# Instalar PostgreSQL para Dev
helm install postgres-dev bitnami/postgresql \
  --namespace deps \
  --set auth.database=meuappdb \
  --set auth.username=devuser \
  --set auth.password=devpass123 # EM PROD, USE SECRETS!

# Instalar Redis
helm install redis-dev bitnami/redis \
  --namespace deps \
  --set architecture=standalone

# Instalar Prometheus Stack (Opcional, para observabilidade local)
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace deps \
  --set grafana.enabled=true
```

### **Gestão de Segredos: A Regra de Ouro**
**NUNCA, em hipótese alguma, comitar segredos em repositórios Git.**

**Solução para Produção no GCP:**

1.  **Armazenar** os segredos (senhas de DB, chaves API) no **Google Secret Manager**.
2.  **Sincronizar** os segredos para o cluster Kubernetes usando o **External Secrets Operator**.
3.  **Referenciar** nos seus pods via volumes ou variáveis de ambiente.

**Exemplo de uso no `values-prod.yaml`**:
```yaml
# values-prod.yaml
database:
  host: "10.10.10.10" # IP Privado do Cloud SQL
  secretName: "meuapp-db-credentials" # Este Secret será criado pelo External Secrets
  # O password NÃO está aqui!

redis:
  host: "10.10.10.20" # Endpoint do Memorystore
  secretName: "meuapp-redis-credentials"
```

### 🔑 **Key Conventions (Checklist Final)**

1.  **Versionamento Semântico**: A versão do Chart (`Chart.yaml`) deve ser incrementada automaticamente na pipeline de CI a cada merge na main.
2.  **"Um Chart por App"**: Cada microserviço independente deve ter seu próprio Chart. Para apps monolíticas complexas, considere subcharts.
3.  **Valores Sensíveis em Arquivos Separados**: Mantenha `values-dev.yaml`, `values-staging.yaml` e `values-prod.yaml` em um diretório `environments/`. O CI/CD injeta o correto no `helm install/upgrade`.
4.  **Teste seus Templates**: Use `helm template ./meuapp-chart -f environments/values-dev.yaml` para renderizar e validar os manifests YAML finais antes de aplicar.
5.  **Documentação Viva**: Crie um `README.md` dentro do chart explicando parâmetros críticos, dependências e como fazer deploy.

### **Referências**
- **[Helm Best Practices](https://helm.sh/docs/chart_best_practices/)**: Guia oficial.
- **[Bitnami Helm Charts](https://github.com/bitnami/charts)**: Charts de produção de alta qualidade.
- **[External Secrets Operator](https://external-secrets.io/)**: Integração entre Kubernetes e provedores de secrets como GCP Secret Manager.
- **[Artifact Registry](https://cloud.google.com/artifact-registry)**: Repositório privado para suas imagens Docker no GCP.

Seguindo esta estrutura, você terá uma base de IaC robusta, segura e pronta para escalar do desenvolvimento local até a produção na nuvem.