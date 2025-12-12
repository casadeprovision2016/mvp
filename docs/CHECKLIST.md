# Checklist Cronológico: Ciclo de Vida de Aplicação Cloud‑Native

Este documento apresenta um checklist acionável e sequencial para desenvolver, testar, empacotar e entregar uma aplicação cloud-native do zero à produção. Seguir as fases na ordem apresentada.

Convenções usadas:
- **`[KEY]`**: decisão arquitetural, configuração crítica ou artefato (ex: `[nome_do_app]`).
- **`(PATTERN)`**: padrão, prática ou convenção aplicada (ex: `(GitFlow)`).
- `snake_case`: nomes de arquivos, diretórios, variáveis e recursos.

---

## Fase 0: Concepção e Pré-requisitos
- [ ] **`[MVP]`**: Definir o escopo mínimo, funcionalidades e critérios de sucesso.
- [ ] **`[nome_do_app]`**: Escolher nome canônico do projeto e esquema de artefatos (image/helm/chart names).
- [ ] Arquitetura: decidir `(Microservices vs Monolith)` e documentar trade-offs.
- [ ] Definir `branching_strategy` `(GitFlow | Trunk-Based)` e padrão de commits `(Conventional Commits)`.
- [ ] Definir SLIs/SLOs, requisitos de segurança, conformidade e observabilidade (traces/metrics/logs).
- [ ] Preparar estações de trabalho: instalar e validar `git`, `docker`, `minikube`, `kubectl`, `helm`, `python`/`pip`/`virtualenv`, `go`, `golangci-lint`, `trivy`.
- [ ] Inicializar repositório com `README.md`, `CODEOWNERS`, `CONTRIBUTING.md` e `.gitignore`.

---

## Fase 1: Configuração do Ambiente e Infraestrutura Local

### Seção 1.1: Cluster Kubernetes Local
- [ ] Iniciar cluster Minikube: `minikube start --driver=docker --addons=ingress,metrics-server`.
- [ ] (Opcional) Usar daemon Docker do Minikube para builds locais: `eval $(minikube docker-env)`.
- [ ] Configurar `kubectl` context para Minikube: `kubectl config use-context minikube`.
- [ ] Verificar status do cluster e namespaces: `kubectl get nodes`, `kubectl get ns` (verificar `kube-system`, `default`).

### Seção 1.2: Estrutura do Projeto
- [ ] Criar raiz do repositório: `[nome_do_app]-project/`.
- [ ] Definir layout (exemplos):
  - Go: `cmd/`, `internal/`, `pkg/`, `configs/`, `scripts/`, `charts/`, `proto/`.
  - Python: `src/`, `tests/`, `configs/`, `scripts/`, `charts/`, `proto/`.
- [ ] Criar `Makefile`/`scripts/` com alvos: `local-start`, `build`, `test`, `lint`, `ci-checks`.
- [ ] Criar diretórios: `docker/`, `kubernetes/` ou `charts/`, `docs/`.

---

## Fase 2: Desenvolvimento do Aplicativo e Containerização

### Seção 2.1: Configuração do Serviço Principal
- [ ] Inicializar módulos/ambientes:
  - Go: `go mod init github.com/<org>/<nome_do_app>`
  - Python: `python -m venv venv` e `pip install -r requirements.txt`.
- [ ] Implementar serviço mínimo `[api_server]` com endpoint `/health` e readiness probes.
- [ ] Aplicar `(12-Factor)`: configurações por env vars, logs em stdout (JSON), processos stateless.
- [ ] Instrumentar pontos básicos para observability: OpenTelemetry (traces) e Prometheus (metrics) placeholders.
- [ ] Criar `Dockerfile` multistage otimizado para produção (usar imagens base minimalistas `(distroless|scratch)` quando aplicável).
- [ ] Criar `.dockerignore` e `.gitignore` com entradas padrão (`venv`, `*.pyc`, `coverage`, `vendor`, `node_modules`).
- [ ] Criar `config.template.yaml` ou `env.example` com variáveis de ambiente esperadas (`DATABASE_URL`, `REDIS_URL`, etc.).

### Seção 2.2: Build e Teste Local
- [ ] Lint: Go `golangci-lint run ./...`; Python `ruff`/`flake8` e `black` para formatação.
- [ ] Testes unitários:
  - Go: `go test ./... -coverprofile=coverage.out` (exigir coverage mínimo definido).
  - Python: `pytest --cov=src`.
- [ ] Construir imagem localmente: `docker build -t [container_registry]/[nome_do_app]:local .` (ou build direto no Minikube se `eval $(minikube docker-env)`).
- [ ] Executar container local para validação: `docker run -p 8080:8080 [container_registry]/[nome_do_app]:local` e checar `/health`.
- [ ] Criar smoke tests (`tests/smoke/`) para validação rápida pós-deploy.

---

## Fase 3: Definição de Infraestrutura como Código (IaC) e Dependências

### Seção 3.1: Helm Charts
- [ ] Criar chart base: `helm create [nome_do_app]-chart` em `charts/`.
- [ ] Manter perfis de valores: `values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`.
- [ ] Parametrizar templates (`Deployment`, `Service`, `Ingress`, `ConfigMap`, `Secret`) evitando hardcodes.
- [ ] Seguir `(Helm Best Practices)`: helpers em `_helpers.tpl`, valores parametrizáveis para `image.repository` e `image.tag`, recursos e probes configuráveis.
- [ ] Preencher `Chart.yaml` com `name`, `version`, `appVersion` e dependências.

### Seção 3.2: Dependências do Cluster
- [ ] Listar dependências: `[postgres_db]`, `[redis_cache]`, `[rabbitmq_queue]`, observability services (OTEL, Prometheus, Jaeger).
- [ ] Decidir: provisionar via `(Bitnami/Community Helm Charts)` no cluster ou usar serviço gerenciado — documentar decisão por dependência.
- [ ] Se provisão local para dev, instalar dependências no Minikube via `helm repo add` e `helm install`.
- [ ] Nunca comitar secrets; usar Vault/External-Secrets/Secret Manager para produção.

---

## Fase 4: Integração, Testes e Pipeline de Entrega

### Seção 4.1: Pipeline de CI/CD Conceitual
- [ ] Definir stages do pipeline: `Lint -> Test -> Build -> Containerize -> Security_Scan -> Helm_Lint -> Deploy_To_Dev -> Integration_Test -> Promote_To_Staging -> Manual_Approval -> Deploy_To_Prod`.
- [ ] Escolher `[CI/CD_TOOL]` (recomendado: `GitHub_Actions`) e documentar secrets: `DOCKER_REGISTRY`, `REGISTRY_USER`, `REGISTRY_PASS`, `KUBECONFIG_STAGING`, `HELM_REPO_CREDS`.
- [ ] No CI, garantir:
  - Linting: `golangci-lint run` / `ruff` / `flake8`.
  - Testes unitários + coverage (falhar se abaixo do threshold).
  - Build imutável: gerar `image_tag = ${GIT_SHA}`.
  - Container scan: `trivy image --severity HIGH,CRITICAL ${IMAGE}` (falhar em findings críticos).
  - Helm lint: `helm lint charts/[nome_do_app]-chart`.
  - Validar templates: `helm template ... | kubeval --strict`.
- [ ] Gerar e armazenar SBOM quando possível e aplicar SCA em dependências.
- [ ] Script de build/push: `scripts/build_and_push.sh` que recebe `IMAGE_TAG` e publica em `[container_registry]`.

### Seção 4.2: Implantação no Ambiente de Desenvolvimento (Local/Dev)
- [ ] Instalar chart no Minikube (dev):
  - `helm upgrade --install [nome_do_app]-dev ./charts/[nome_do_app]-chart -f charts/[nome_do_app]/values-dev.yaml --namespace dev --create-namespace --set image.tag=[image_tag] --wait`.
- [ ] Verificar deployment e pods: `kubectl get all -n dev -l app=[nome_do_app]` e `kubectl rollout status deployment/[nome_do_app] -n dev`.
- [ ] Executar testes de integração contra o ambiente dev.
- [ ] Configurar acesso local: `kubectl port-forward` ou configurar `ingress` com `minikube tunnel`/`ingress-nginx`.
- [ ] Capturar logs e métricas: `kubectl logs -f deployment/[nome_do_app] -n dev` / ver traces no OTEL.

---

## Fase 5: Preparação para Produção e Entrega Final

### Seção 5.1: Hardening e Configuração para Produção
- [ ] `values-prod.yaml`: ajustar `replicaCount >= 2`, `resources.requests/limits`, `readinessProbe`/`livenessProbe`.
- [ ] Security: aplicar `securityContext` (ex.: `runAsNonRoot`, `readOnlyRootFilesystem`), revisar `PodSecurity` policies.
- [ ] Networking: aplicar `NetworkPolicy` para segregar tráfego; criar `PodDisruptionBudget`.
- [ ] Autoscaling: configurar `HorizontalPodAutoscaler` com métricas e thresholds.
- [ ] Ingress & TLS: configurar `Ingress` com `cert-manager` para gerenciamento automatizado de certificados.
- [ ] Secrets: integrar com Vault/Secret Manager; usar `external-secrets` em k8s para sincronizar secrets.
- [ ] RBAC: revisar `ServiceAccounts`, `Roles` e `RoleBindings`.
- [ ] Supply chain security: assinatura de imagens e geração de SBOM; escaneamento automático em CI.

### Seção 5.2: Entrega e Documentação
- [ ] Versionar artefatos finais: Git tag `v{app_version}`, atualizar `Chart.yaml` `version` e `appVersion`, e tag da imagem (`v{app_version}` ou `${GIT_SHA}`).
- [ ] Publicar chart: `helm push ./charts/[nome_do_app] oci://registry/charts` ou enviar para `ChartMuseum`/`Harbor`.
- [ ] Documentar deploy em `README.md` com comando de produção:
  - `helm install [nome_do_app] oci://registry/charts/[nome_do_app] -f values-prod.yaml`.
- [ ] Documentar rollback e runbooks: `helm history`, `helm rollback`, observability runbooks e troubleshooting steps.
- [ ] Verificar backups e procedimentos de restore para bancos e recursos stateful.
- [ ] Checklist pré-lançamento: health checks, dashboards, alertas, backups validados e testes de carga/signature.

---

## Extras e Boas Práticas (incluir nos fluxos apropriados)
- [ ] Armazenar credenciais em secrets do `[CI/CD_TOOL]` e usar access tokens temporários quando disponível.
- [ ] Build imutável: build once, tag com SHA e usar mesmo tag no deploy Helm.
- [ ] Pin de dependências e lockfiles (`go.sum`, `requirements.txt`) para reproducibility.
- [ ] Automatizar testes de contrato (contract tests) e checks de compatibilidade de API (se usar gRPC, incluir `buf lint` e `buf breaking`).
- [ ] Incluir `helm lint`, `kubeval` e `ct lint` no CI para validação de charts.
- [ ] Implementar estratégia de deploy progressivo (canary/blue-green) com automação de smoke tests antes do full-promote.

---

## Próximos passos sugeridos
- [ ] Revisar e aprovar este checklist; se aprovado, movê-lo para `docs/CHECKLIST.md` e referenciá-lo no `README.md`.
- [ ] (Opcional) Scaffolder: gerar um exemplo mínimo em `charts/[nome_do_app]`, `Dockerfile` de exemplo e `proto/` skeleton — posso criar esses artefatos se desejar.

---

Arquivo gerado automaticamente por assistente — adaptar nomes e valores para seu contexto antes de executar comandos em produção.
