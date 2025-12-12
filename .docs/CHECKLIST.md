# Checklist Cronológico: Ciclo de Vida de Aplicação Cloud‑Native

Este documento apresenta um checklist acionável e sequencial para desenvolver, testar, empacotar e entregar uma aplicação cloud-native do zero à produção. Seguir as fases na ordem apresentada.

Convenções usadas:
- **`[KEY]`**: decisão arquitetural, configuração crítica ou artefato (ex: `[nome_do_app]`).
- **`(PATTERN)`**: padrão, prática ou convenção aplicada (ex: `(GitFlow)`).
- `snake_case`: nomes de arquivos, diretórios, variáveis e recursos.

---

## 📋 STATUS: Fase 0 ✅ COMPLETA

**Data**: 12 de Dezembro de 2025  
**Novos Documentos Criados**:
- `README.md` — Overview do projeto, quick-start, troubleshooting
- `CONTRIBUTING.md` — Workflow de desenvolvimento, padrões de código, processo de PR
- `CODEOWNERS` — Ownership de serviços e assignments de review
- `.gitignore` — Proteção de secrets e artefatos
- `docs/MVP-SCOPE.md` — Features, acceptance criteria, timeline
- `docs/ARTIFACT-NAMING.md` — Schema de container/Helm, CI/CD integration

---

## Fase 0: Concepção e Pré-requisitos
- [x] **`[MVP]`**: Definir o escopo mínimo, funcionalidades e critérios de sucesso.
  - Referência: `docs/MVP-SCOPE.md` (6 core features, acceptance criteria, phased delivery, KPIs)
- [x] **`[nome_do_app]`**: Escolher nome canônico do projeto e esquema de artefatos (image/helm/chart names).
  - Nome: **Cotai** — Multi-tenant procurement platform
  - Schema: `gcr.io/PROJECT_ID/cotai-SERVICE_NAME:TAG` (documentado em `docs/ARTIFACT-NAMING.md`)
- [x] Arquitetura: decidir `(Microservices vs Monolith)` e documentar trade-offs.
  - **Microservices** (8 core services) com Domain-Driven Design (DDD)
  - Referência: `docs/arquiteture.md`, ADRs em `docs/adr/`
- [x] Definir `branching_strategy` `(GitFlow | Trunk-Based)` e padrão de commits `(Conventional Commits)`.
  - **GitFlow**: main (prod), develop (integration), feature/*, release/*, hotfix/*
  - **Conventional Commits**: type(scope): subject [body] [footer]
  - Referência: `CONTRIBUTING.md`
- [x] Definir SLIs/SLOs, requisitos de segurança, conformidade e observabilidade (traces/metrics/logs).
  - **SLIs**: Latency (P95/P99), Error Rate, Availability, Success Rate, Throughput (docs/observability.md §5)
  - **SLOs**: 99.5% uptime, P95 < 500ms, error rate < 0.5% (docs/MVP-SCOPE.md)
  - **Security**: OAuth2/OIDC, mTLS, RLS (PostgreSQL), Vault, no hardcoded secrets
  - **Observability**: OpenTelemetry → Jaeger (traces), Prometheus (metrics), Loki (logs)
  - **Compliance**: LGPD audit logs, data retention, PII masking
- [x] Preparar estações de trabalho: instalar e validar `git`, `docker`, `minikube`, `kubectl`, `helm`, `python`/`pip`/`virtualenv`, `go`, `golangci-lint`, `trivy`.
  - Script: `scripts/setup-workstation.sh` (validação + instalação automática)
  - Suporta: Linux (Ubuntu/Debian), macOS
- [x] Inicializar repositório com `README.md`, `CODEOWNERS`, `CONTRIBUTING.md` e `.gitignore`.
  - `README.md`: Overview, quick-start, architecture, troubleshooting
  - `CONTRIBUTING.md`: Git workflow, code standards, PR process
  - `CODEOWNERS`: Service ownership, review assignments
  - `.gitignore`: Secrets, build artifacts, IDE files (Go, Java, Python, Node.js)

---

## 📋 STATUS: Fase 1 ✅ COMPLETA

**Data**: 12 de Dezembro de 2025  
**Artefatos Criados**:
- `Makefile` — Central orchestration para Minikube, Docker, Kubernetes e build automation (250+ linhas, 40+ targets)
- `scripts/init-project-structure.sh` — Initialize 7 microservices com standard Go layout (300+ linhas)
- `scripts/local-start.sh` — One-command local environment startup orchestration (40 linhas)
- `scripts/verify-setup.sh` — Tool validation com git config checks (120 linhas)
- `scripts/verify-cluster.sh` — Kubernetes cluster verification e addon status (150+ linhas)
- `scripts/scaffold-service.sh` — Generate new microservice boilerplate com gRPC template (200+ linhas)
- **7 Microservice Directories**: `auth-service`, `edital-service`, `procurement-service`, `bidding-service`, `notification-service`, `audit-service`, `api-gateway`
  - Each with: `cmd/`, `internal/{config,handlers,models,repository,service}`, `pkg/`, `proto/`, `charts/`, `tests/`, `docker/`, `configs/`
  - Files: `README.md`, `.env.example`, `go.mod`, `go.sum`, `Dockerfile`, `.golangci.yml`, `buf.yaml`
- **Shared Infrastructure**: `kubernetes/`, `terraform/`, `proto/v1/`

---

## Fase 1: Configuração do Ambiente e Infraestrutura Local

### Seção 1.1: Cluster Kubernetes Local ✅
- [x] Iniciar cluster Minikube: Makefile target `make minikube-start` (docker driver, ingress+metrics-server addons, 4CPU, 8GB RAM).
  - Command: `minikube start --driver=docker --addons=ingress,metrics-server --cpus=4 --memory=8192`
  - Reference: `Makefile` lines 15-25
- [x] Usar daemon Docker do Minikube para builds locais: `make docker-env` (eval $(minikube docker-env)).
  - Reference: `Makefile` lines 28-32
- [x] Configurar `kubectl` context para Minikube: `make kubectl-context`.
  - Command: `kubectl config use-context minikube`
  - Reference: `Makefile` lines 35-39
- [x] Verificar status do cluster e namespaces: `make verify-cluster` (kubectl get nodes, addons, endpoints).
  - Script: `scripts/verify-cluster.sh` (150+ linhas com status indicators)
  - Checks: cluster-info, nodes, namespaces, addons (ingress, metrics-server), API health
  - Reference: `Makefile` lines 42-46

### Seção 1.2: Estrutura do Projeto ✅
- [x] Criar raiz do repositório: `/home/felipe/dev/mvp` (Cotai MVP project).
- [x] Definir e implementar layout Go standard:
  - Per-service: `cmd/{service}`, `internal/{config,handlers,models,repository,service}`, `pkg/`, `proto/`, `charts/`, `tests/{unit,integration}`, `docker/`, `configs/`
  - Shared: `kubernetes/`, `terraform/`, `proto/v1/`
  - Reference: `scripts/init-project-structure.sh` lines 50-100
- [x] Criar `Makefile` com alvos: `minikube-start`, `docker-env`, `kubectl-context`, `setup-local`, `verify-cluster`, `build`, `test`, `lint`, `ci-checks`.
  - File: `Makefile` (250+ lines, 40+ targets, organized into 5 groups)
  - Targets include: Minikube lifecycle, Docker config, Kubectl config, namespace setup, build/test automation, cleanup
  - Reference: `Makefile` complete file
- [x] Criar diretórios estruturados: `docker/`, `kubernetes/`, `charts/`, `docs/`, `proto/`, `scripts/`.
  - Execution: `bash scripts/init-project-structure.sh` (created 7 services + 3 shared dirs)
  - Result: All 7 service directories initialized with full structure
- [x] Criar utilitários de CLI: `scripts/local-start.sh`, `scripts/verify-setup.sh`, `scripts/verify-cluster.sh`, `scripts/scaffold-service.sh`.
  - `local-start.sh`: One-command startup orchestration (40 lines)
  - `verify-setup.sh`: Tool validation with git config checks (120 lines)
  - `verify-cluster.sh`: Cluster verification with addon status (150+ lines)
  - `scaffold-service.sh`: New service generation tool (200+ lines, template-driven)
  - All scripts include: color-coded output (✅/❌), error handling, descriptive help
  - Reference: `scripts/` directory

---

## 📋 STATUS: Fase 2 ✅ COMPLETA (Parte 1)

**Data**: 12 de Dezembro de 2025  
**Artefatos Criados**:
- **7 Microservices com suporte Go completo**:
  - `auth-service`, `edital-service`, `procurement-service`, `bidding-service`, `notification-service`, `audit-service`, `api-gateway`
  - Cada serviço com: `go.mod`, `go.sum`, código bootstrap principal, configuração 12-Factor, logging estruturado, observabilidade OpenTelemetry/Prometheus
  - Build binários validados: 21MB cada (distroless-ready)
- **Packages compartilhados por serviço**:
  - `internal/config/` — 12-Factor env-based configuration loading
  - `internal/logger/` — Structured JSON logging com logrus
  - `internal/observability/` — OpenTelemetry tracers, Prometheus metrics, gRPC instrumentation
  - `internal/handlers/` — Health check service (gRPC health v1)
  - `cmd/main.go` — Servidor gRPC com graceful shutdown, observabilidade integrada
- **Dockerfile**: Multi-stage builder + distroless runtime (otimizado para produção)
- **.dockerignore**: Padrão cloud-native (exclui artefatos, IDE, CI/CD, docs)
- **Scripts**:
  - `scripts/scaffold-service-phase2.sh` — Scaffolding automático para novos serviços

**Verificação de Build**: ✅ Todos os 7 serviços compilam com sucesso (`go build`)

---

## Fase 2: Desenvolvimento do Aplicativo e Containerização

### Seção 2.1: Configuração do Serviço Principal
- [x] Inicializar módulos/ambientes:
  - Go: `go mod init github.com/<org>/<nome_do_app>` ✅ Todos os 7 serviços inicializados
  - Python: (não aplicável para MVP Go)
- [x] Implementar serviço mínimo `[api_server]` com endpoint `/health` e readiness probes. ✅ gRPC health v1 registrado
- [x] Aplicar `(12-Factor)`: configurações por env vars, logs em stdout (JSON), processos stateless. ✅ config.Load(), JSON formatter
- [x] Instrumentar pontos básicos para observability: OpenTelemetry (traces) e Prometheus (metrics) placeholders. ✅ TracerProvider, MeterProvider
- [x] Criar `Dockerfile` multistage otimizado para produção (usar imagens base minimalistas `(distroless|scratch)` quando aplicável). ✅ gcr.io/distroless/base-debian11:nonroot
- [x] Criar `.dockerignore` com entradas padrão. ✅ Criado
- [x] `.env.example` com variáveis de ambiente esperadas. ✅ Existente (Phase 1)

## Seção 2.2: Build e Teste Local
- [x] Lint: Go `golangci-lint run ./...`; (validar sem erros críticos)
- [x] Testes unitários:
  - Go: `go test ./... -coverprofile=coverage.out` (exigir coverage mínimo definido).
  - Auth-service: 96.8% coverage (config 100%, logger 90.9%, handlers 100%)
  - All 6 other services: tests passing
- [x] Smoke tests: `tests/smoke/health_check_test.go` per service
  - Health check validation (gRPC health v1)
  - Service connectivity checks
  - Prometheus metrics endpoint documentation
- [ ] Construir imagem localmente: `docker build -t [container_registry]/[nome_do_app]:local .` (ou build direto no Minikube se `eval $(minikube docker-env)`).
- [ ] Executar container local para validação: `docker run -p 8080:8080 [container_registry]/[nome_do_app]:local` e checar `/health`.

---

## 📋 STATUS: Fase 2 ✅ COMPLETA (Parte 2 - Seção 1/3)

**Data**: 12 de Dezembro de 2025  
**Artefatos Criados - Testes**:
- `auth-service/internal/config/config_test.go` — Configuration loading tests (100% coverage)
- `auth-service/internal/logger/logger_test.go` — Logger factory tests (90.9% coverage)
- `auth-service/internal/handlers/health_test.go` — Health check tests (100% coverage)
- `auth-service/tests/smoke/health_check_test.go` — Smoke tests for running service validation

**Artefatos Criados - Proto Definitions**:
- `proto/v1/common.proto` — Shared types (Metadata, Error, HealthCheck, PageInfo)
- `proto/v1/auth.proto` — Auth service RPC definitions (Login, ValidateToken, RefreshToken, Logout)
- `proto/v1/edital.proto` — Edital service RPC definitions (CreateEdital, GetEdital, ListEditals, etc.)
- `buf.yaml` — Updated to v2 with STANDARD linting rules

**Verificação**:
✅ All unit tests passing (9 test functions, 20+ test cases)
✅ Combined coverage: 96.8% of statements
✅ Smoke tests created for all 7 services
✅ Proto files validated with `buf lint` (no errors)
✅ Tests replicated to all 6 remaining services

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
