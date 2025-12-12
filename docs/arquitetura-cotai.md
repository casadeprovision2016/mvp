# Arquitetura do Sistema Cotai

**Versão**: 1.0  
**Data**: Dezembro de 2025  
**Status**: Aprovado para Implementação

---

## 1. Visão Geral

O Cotai é um **SaaS de gestão de licitações** (públicas e privadas) multi-tenant que automatiza o ciclo completo de participação em licitações: descoberta, extração de editais, gestão de cotações, fornecedores, estoque, comunicação interna, notificações e conformidade/auditoria.

### Princípios Fundacionais

1. **API-First**: Comunicação estruturada via gRPC (S2S), REST (B2C), protobuf.
2. **Event-Driven**: Processos assíncronos por Kafka (descoberta, notificações, integração ERP).
3. **Multi-Tenant**: Isolamento por tenant via RLS (Row-Level Security) + JWT + X-Tenant-ID.
4. **Escalável**: HPA, cache distribuído, particionamento Kafka por tenant, CQRS onde necessário.
5. **Observável**: OpenTelemetry + Jaeger + Prometheus para traces, métricas e logs estruturados.
6. **Seguro**: mTLS, OAuth2/OIDC, Vault para secrets, auditoria imutável.

---

## 2. Padrões Arquiteturais

### 2.1 Microserviços com Domain-Driven Design (DDD)

Cada serviço tem:
- **Bounded Context**: um domínio bem definido (ex.: `edital-service`, `cotacao-service`, `fornecedor-service`).
- **Banco de dados independente**: Postgres (ou polyglot se justificado: Mongo para docs não-estruturados, Redis para cache).
- **API clara**: gRPC interno, REST externo.
- **Autonomia**: deploy independente, sem sincronização rígida com outros serviços.

**Serviços-chave**:

| Serviço | Domínio | Responsabilidade |
|---------|---------|------------------|
| `edital-service` | Descoberta & Ingestão | Conectores, OCR, normalização, fila de ingestão |
| `extracao-service` | Extração & Estruturação | NLP/OCR, parser de itens, validação humana |
| `cotacao-service` | Cotações & Propostas | Fluxo de cotações, análise de margem, aprovações |
| `fornecedor-service` | Fornecedores & Compras | Cadastro, portal, avaliação, scoring, SRs |
| `estoque-service` | Inventário & Logística | Itens, localizações, reservas, reabastecimento |
| `chat-service` | Colaboração | Chat por contexto, tarefas, registro de decisões |
| `notificacao-service` | Alertas & Agenda | Prazos, calendário, notificações (email, SMS, push) |
| `auth-service` | Autenticação & Autorização | SSO (OAuth2/SAML), JWT, MFA, auditoria de acesso |
| `relatorio-service` | BI & Dashboards | Agregação de dados, relatórios, KPIs, export |
| `integracao-service` | Integrações Externas | ERP, BI, APIs de terceiros |

### 2.2 Event-Driven Architecture (EDA)

**Fluxo de eventos** (Apache Kafka):

```
edital-service → edital.publicado
                   ↓
         extracao-service (consome, extrai itens)
                   ↓
         edital-extracao.concluida
                   ↓
    cotacao-service, estoque-service, notificacao-service (consomem)
                   ↓
      cotacao.criada, estoque.reservado, usuario.notificado
                   ↓
         relatorio-service, chat-service (agregam, rastreiam)
```

**Tópicos Kafka** (particionados por tenant_id):

- `edital.publicado` – edital novo ingerido
- `edital.normalizado` – metadados padronizados
- `edital-extracao.iniciada` – OCR/NLP disparado
- `edital-extracao.concluida` – itens extraídos
- `cotacao.criada` – nova cotação aberta
- `cotacao.respondida` – fornecedor respondeu
- `cotacao.aprovada` – aprovação concedida
- `fornecedor.criado` – novo fornecedor registrado
- `fornecedor.avaliado` – score atualizado
- `estoque.reservado` – material reservado para execução
- `sr.criada` – solicitação de compra gerada
- `notificacao.enviada` – email/SMS/push despachado
- `usuario.autenticado` – login registrado (auditoria)
- `auditoria.acao` – qualquer mudança crítica

**Padrão de Particionamento**: Cada mensagem inclui `tenant_id` na chave para garantir ordem por tenant e balanceamento.

### 2.3 Comunicação Síncrona vs Assíncrona

#### Quando usar gRPC (Síncrono)

- Chamadas entre serviços com resposta imediata necessária (ex.: validar permissão, buscar dados de referência).
- Fluxos de aprovação que requerem feedback imediato.
- Consultas de dados (read-through cache).

**Exemplo**: `cotacao-service` chama `fornecedor-service` para validar qualificação do fornecedor antes de aceitar cotação.

#### Quando usar Kafka (Assíncrono)

- Processamento de lote (OCR em background).
- Notificações (email, SMS, Slack, push).
- Projeções CQRS e agregação de dados.
- Auditoria e trilhas imutáveis.
- Reabastecimento automático de estoque.
- Sincronização eventual com ERP/BI.

**Exemplo**: Após submissão de cotação, evento `cotacao.respondida` acionador de:
1. Análise de margem (assíncrono, `cotacao-service`).
2. Notificação de gestor (assíncrono, `notificacao-service`).
3. Atualização de dashboard (assíncrono, `relatorio-service` constrói projeção).

### 2.4 API-First Design

**Contrato-primeiro com protobuf + buf**:

1. Definir `.proto` com mensagens de domínio.
2. Validar com `buf lint` (estilo, nomes, campos obrigatórios).
3. Verificar compatibilidade backward com `buf breaking`.
4. Gerar código (Go, Java, Python, TS) via `protoc` + plugins.

**Exemplo estrutura**:

```
proto/
├── buf.yaml
├── buf.gen.yaml
├── google/
│   └── type/
├── cotai/
│   ├── common/
│   │   └── v1/
│   │       └── types.proto         # tipos comuns (Tenant, User, Audit)
│   ├── edital/
│   │   └── v1/
│   │       ├── service.proto       # gRPC service
│   │       └── messages.proto      # domain messages
│   ├── cotacao/
│   │   └── v1/
│   │       ├── service.proto
│   │       └── messages.proto
│   └── ...
└── README.md
```

**Validação em CI**:

```bash
buf lint proto/
buf breaking --against .
```

### 2.5 Domain-Driven Design (DDD) – Bounded Contexts

Cada serviço encapsula seu **ubíquous language** e **domain model**:

- `edital-service`: Edital, Publicador, FonteIngestão, NormalizadorMetadados.
- `extracao-service`: ItemEdital, EspecificacaoTécnica, ValidadorHumano, Classificação.
- `cotacao-service`: Cotação, CotacaoItem, AnáliseMargem, RegraProduto, FluxoAprovação.
- `fornecedor-service`: Fornecedor, Certificação, Score, HistóricoDesempenho.
- `estoque-service`: Lote, Localização, NívelMínimo, ReservaMaterial.

**Comunicação entre contextos**: via eventos Kafka ou gRPC com DTO genéricos (sem exposição de domain model).

---

## 3. Modelo Multi-Tenant

### 3.1 Estratégias de Isolamento

| Estratégia | Vantagens | Desvantagens | Recomendação MVP |
|-----------|-----------|--------------|-----------------|
| **RLS (Row-Level Security)** | Compartilha tabelas, fácil backup, reduz custo infra | Complexo audit trail, pode ter leak por erro SQL | ✅ **Recomendado** |
| **Schema-per-Tenant** | Isolamento forte, auditoria simples | Muitos objetos DB, backup granular complexo | Escalabilidade futura |
| **DB-per-Tenant** | Isolamento completo, compliance forte | Alto custo operacional, backup/restore volumoso | Apenas premium tiers |

### 3.2 Implementação MVP: RLS + JWT + X-Tenant-ID

#### Fluxo de Propagação

1. **Autenticação** (`auth-service`):
   - OAuth2/OIDC → JWT com claim `tenant_id`.
   - Retorna: `token = JWT(sub=user_id, tenant_id=123, roles=[...])`.

2. **API Gateway / Proxy**:
   - Extrai `tenant_id` do JWT → header `X-Tenant-ID: 123`.
   - Propaga para todos os serviços.

3. **Serviço (ex: `cotacao-service`)**:
   - Lê `X-Tenant-ID` do contexto HTTP.
   - Injeta `tenant_id` em toda query SQL.
   - **RLS Policy**: `SELECT * FROM cotacao WHERE tenant_id = current_setting('app.tenant_id')`.

#### Configuração PostgreSQL

```sql
-- Tabela com tenant_id
CREATE TABLE cotacao (
  id UUID PRIMARY KEY,
  tenant_id UUID NOT NULL,
  descricao TEXT,
  created_at TIMESTAMP,
  CONSTRAINT fk_cotacao_tenant FOREIGN KEY(tenant_id) REFERENCES tenant(id)
);

-- RLS Policy
ALTER TABLE cotacao ENABLE ROW LEVEL SECURITY;

CREATE POLICY cotacao_tenant_policy ON cotacao
  USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Connection setup (per request)
SET app.tenant_id = '<tenant_uuid_from_header>';
```

#### Implementação em Java/Go

**Java (Spring)**:
```java
@Component
public class TenantFilter implements Filter {
  @Override
  public void doFilter(ServletRequest request, ServletResponse response, 
                       FilterChain chain) throws IOException, ServletException {
    String tenantId = ((HttpServletRequest) request).getHeader("X-Tenant-ID");
    TenantContext.setTenant(UUID.fromString(tenantId));
    try {
      chain.doFilter(request, response);
    } finally {
      TenantContext.clear();
    }
  }
}

@Repository
public class CotacaoRepository {
  private final JdbcTemplate jdbc;
  
  public List<Cotacao> findAllForTenant() {
    jdbc.execute("SET app.tenant_id = '" + TenantContext.getTenant() + "'");
    return jdbc.query("SELECT * FROM cotacao", new CotacaoRowMapper());
  }
}
```

**Go**:
```go
func WithTenant(tenantID string) context.Context {
  return context.WithValue(context.Background(), "tenant_id", tenantID)
}

func (r *CotacaoRepository) FindAll(ctx context.Context) ([]Cotacao, error) {
  tenantID := ctx.Value("tenant_id").(string)
  // Set RLS policy
  _, err := r.db.ExecContext(ctx, fmt.Sprintf("SET app.tenant_id = '%s'", tenantID))
  // Query (RLS policy applies automatically)
  rows, err := r.db.QueryContext(ctx, "SELECT * FROM cotacao")
  // ...
}
```

#### Testes e Validação

- **Unit Tests**: Mock `X-Tenant-ID` em cada request.
- **Integration Tests**: Criar dois tenants de teste, verificar isolamento (tenant A não vê dados de tenant B).
- **Audit**: Logar todas as queries com tenant_id e user_id.

---

## 4. Estratégias de Escalabilidade

### 4.1 Escalabilidade por Componente

#### Serviços Stateless (HPA - Horizontal Pod Autoscaler)

Todos os serviços devem ser stateless:

```yaml
# Exemplo: cotacao-service HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: cotacao-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: cotacao-service
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

#### Particionamento Kafka

**Por tenant_id**: garante ordem por tenant e distribuição balanceada.

```bash
# Criar tópico com 20 partições
kafka-topics --create --topic edital.publicado \
  --partitions 20 --replication-factor 3

# Keying em producer (Java)
ProducerRecord<String, EditalPublicado> record = 
  new ProducerRecord<>("edital.publicado", tenantId, evento);
kafkaTemplate.send(record);

# Consumer Group Strategy
@KafkaListener(topics = "edital.publicado", groupId = "extracao-group")
public void processarEdital(EditalPublicado evento) {
  // Processamento paralelo garantido por partição/tenant
}
```

#### Caching Strategy

- **Redis** para cache distribuído (sessões, RLS policies cache, dados de referência).
- **L1 Cache** (aplicação local): guarded by TTL, invalidação por evento.
- **Cache Keys**: `tenant:<tenant_id>:<resource>:<id>`.

```java
@Cacheable(value = "fornecedor", key = "'tenant:' + #tenantId + ':' + #id")
public Fornecedor getFornecedor(UUID tenantId, UUID id) {
  return repository.findById(id, tenantId);
}

// Invalidação via evento
@EventListener(condition = "#evento.tenantId != null")
public void onFornecedorAvaliado(FornecedorAvaliado evento) {
  cacheManager.getCache("fornecedor")
    .evict("tenant:" + evento.tenantId + ":" + evento.fornecedorId);
}
```

#### Database Sharding (Futura Escalabilidade)

Se volume crescer (ex.: > 100TB por tenant):

- **Sharding Key**: `tenant_id` (cada tenant → shard único).
- **Schema**: Idêntico em cada shard, gateway de roteamento em cima.
- **Tools**: Citus (Postgres), Vitess (MySQL), ou custom com `pgBouncer`.

### 4.2 Escalabilidade de Pipeline de Documentos (OCR/NLP)

- **Fila de ingestão**: Kafka com worker pool.
- **Workers**: stateless, escaláveis via HPA; processam um documento por vez.
- **Retry**: exponential backoff, dead-letter topic para falhas permanentes.
- **Monitoramento**: métricas de latência, taxa de erro, throughput.

```
edital-service (publica) → edital-extracao.iniciada
                             ↓
            extracao-worker pool (HPA escala por lag Kafka)
                             ↓
                   edital-extracao.concluida
```

---

## 5. Observabilidade e SLOs

### 5.1 Stack OpenTelemetry + Prometheus + Jaeger

#### Estrutura

```
Aplicação (OpenTelemetry SDK)
    ↓
OTEL Collector (agregador)
    ↓
    ├→ Jaeger (traces)
    ├→ Prometheus (métricas)
    └→ Loki (logs)
    
    ↓
Grafana (dashboards)
AlertManager (alertas)
```

#### Instrumentação Obrigatória

**Traces** (Jaeger):
- Toda requisição HTTP/gRPC tem span raiz com `trace_id`.
- Spans filhos para: DB query, chamada gRPC, operação Kafka, chamada externa.
- Atributos: `tenant_id`, `user_id`, `action`, `status`, `duration_ms`.

**Métricas** (Prometheus):
- `http_request_duration_seconds` – latência por endpoint, status.
- `grpc_server_handling_seconds` – latência gRPC.
- `kafka_messages_consumed_total` – mensagens processadas.
- `database_query_duration_seconds` – latência DB por operação.
- `cache_hit_ratio` – efetividade do cache.
- `tenant_storage_bytes` – espaço consumido por tenant.

**Logs**:
- JSON estruturado com `trace_id`, `span_id`, `tenant_id`, `user_id`, `level`, `timestamp`.
- Exportados para Loki (ou CloudLogging em GCP).

#### Exemplo: Instrumentação Java Spring Boot

```java
@Configuration
public class OpenTelemetryConfig {
  @Bean
  public OpenTelemetry openTelemetry() {
    return OpenTelemetrySdk.builder()
      .setTracerProvider(
        SdkTracerProvider.builder()
          .addSpanProcessor(
            OtlpGrpcSpanExporter.builder()
              .setEndpoint("http://otel-collector:4317")
              .build())
          .build())
      .setMeterProvider(
        SdkMeterProvider.builder()
          .addMetricReader(
            PeriodicMetricReader.builder(
              OtlpGrpcMetricExporter.builder()
                .setEndpoint("http://otel-collector:4317")
                .build())
              .build())
          .build())
      .build();
  }
}

@RestController
public class CotacaoController {
  private final Tracer tracer;
  
  @GetMapping("/cotacoes")
  public List<Cotacao> list() {
    Span span = tracer.spanBuilder("cotacao.list")
      .setAttribute("tenant_id", getTenantId())
      .startSpan();
    try (Scope scope = span.makeCurrent()) {
      // lógica
      span.setStatus(StatusCode.OK);
      return cotacaoService.listAll();
    } catch (Exception e) {
      span.recordException(e);
      span.setStatus(StatusCode.ERROR);
      throw e;
    }
  }
}
```

### 5.2 SLOs Mínimos e Alertas

| Métrica | SLO | Alerta Crítico | Alerta Aviso |
|---------|-----|----------------|--------------|
| **Latência P95 (API)** | < 500ms | > 2s | > 1s |
| **Taxa de erro (5xx)** | < 0.5% | > 2% | > 1% |
| **Disponibilidade** | 99.5% | < 99% | < 99.5% |
| **Latência P95 (OCR)** | < 60s | > 120s | > 90s |
| **Taxa de processamento Kafka** | > 1000 msg/s | < 500 msg/s | < 750 msg/s |

**Exemplo AlertManager**:

```yaml
groups:
- name: cotai_alerts
  rules:
  - alert: HighErrorRate
    expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.02
    for: 5m
    annotations:
      summary: "Taxa de erro alta em {{ $labels.service }}"
  - alert: HighLatency
    expr: histogram_quantile(0.95, http_request_duration_seconds) > 2
    for: 10m
    annotations:
      summary: "Latência elevada em {{ $labels.endpoint }}"
```

---

## 6. Diagrama de Componentes (Alto Nível)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Frontend (Web/Mobile)                     │
│                        (React/Vue + Redux)                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ↓ (REST/gRPC)
┌─────────────────────────────────────────────────────────────────┐
│                      API Gateway (Kong/Envoy)                    │
│         JWT Validation, Rate Limit, Tenant Routing               │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ↓
        ┌────────────────────────────────┐
        │   Service Mesh (Istio/Linkerd) │ (mTLS, telemetry)
        └────────────────────────────────┘
                         │
      ┌──────────────────┼──────────────────────┬──────────────────┐
      ↓                  ↓                      ↓                  ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ edital-svc   │  │ cotacao-svc  │  │ fornecedor-sv│  │ estoque-svc  │
│ (gRPC)       │  │ (gRPC)       │  │ (gRPC)       │  │ (gRPC)       │
└──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘
      │                │                │                │
      ↓                ↓                ↓                ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  PostgreSQL  │  │  PostgreSQL  │  │  PostgreSQL  │  │  PostgreSQL  │
│  (RLS)       │  │  (RLS)       │  │  (RLS)       │  │  (RLS)       │
└──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘
      │                │                │                │
      └────────────────┼────────────────┼────────────────┘
                       ↓
         ┌─────────────────────────────┐
         │   Apache Kafka (Event Bus)  │
         │   Topics (by tenant_id)     │
         └─────────────────────────────┘
            │        │        │        │
      ┌─────┴────────┼────────┼────────┴─────┐
      ↓              ↓        ↓              ↓
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│extracao-svc  │ │chat-service  │ │notif-service │
│(OCR/NLP)     │ │(collaborate) │ │(email/SMS)   │
└──────────────┘ └──────────────┘ └──────────────┘
      │
      ↓
┌──────────────┐
│ Redis Cache  │
│ (sessions,   │
│  ref data)   │
└──────────────┘

┌──────────────────────────────────────────────────┐
│      Observability & Monitoring                   │
│  ┌─────────────────────────────────────────────┐ │
│  │  OTEL Collector (Prometheus, Jaeger, Loki)  │ │
│  └─────────────────────────────────────────────┘ │
│       ↓           ↓           ↓                   │
│  Jaeger(Traces) Prometheus  Loki(Logs)          │
│       ↓           ↓           ↓                   │
│      └─────────────┬───────────┘                  │
│                    ↓                              │
│               Grafana                             │
│            (Dashboards)                           │
│                    ↓                              │
│            AlertManager                           │
│            (Slack/PagerDuty)                      │
└──────────────────────────────────────────────────┘
```

---

## 7. Fluxos Principais

### 7.1 Pipeline de Descoberta e Ingestão de Edital

```
1. Conectores (web scraping, API, email, manual)
   ↓
2. edital-service → Kafka: edital.publicado
   ↓
3. extracao-service (consome, inicia OCR/NLP)
   ↓
4. Fila de processamento (worker pool, HPA)
   ↓
5. Parser & Classificação
   ↓
6. Validação humana (UI assistida)
   ↓
7. edital-extracao.concluida → Kafka
   ↓
8. cotacao-service, estoque-service, chat-service (consomem)
   ↓
9. Gestor recebe notificação + tarefa em chat
```

### 7.2 Fluxo de Cotações e Aprovações

```
1. Cotacao.Criar (gestor clica em "Preparar Proposta")
   ↓
2. cotacao-service → Kafka: cotacao.criada
   ↓
3. Solicitar cotações a fornecedores (email + portal)
   → notificacao-service envia
   → fornecedor-service registra envio
   ↓
4. Fornecedor responde (portal ou email)
   ↓
5. cotacao-service recebe → Kafka: cotacao.respondida
   ↓
6. Análise automática (margem, preço, conformidade)
   ↓
7. Fluxo de aprovação (regras por valor)
   → Se < 10k: aprovação automática
   → Se 10k-50k: aprovação supervisor
   → Se > 50k: aprovação diretor + CFO
   ↓
8. cotacao.aprovada → Kafka
   ↓
9. Gerar ordem de compra (SR + integracao ERP)
   ↓
10. Atualizar estoque (reserva, rastreamento)
```

### 7.3 Autenticação e Propagação de Tenant

```
1. Usuário login (OAuth2/OIDC)
   ↓
2. auth-service valida credenciais
   ↓
3. JWT gerado: {sub: user_id, tenant_id: 123, roles: [...]}
   ↓
4. Frontend recebe token, armazena em localStorage/sessionStorage
   ↓
5. Cada requisição HTTP: Authorization: Bearer <JWT>
   ↓
6. API Gateway: extrai tenant_id do JWT → X-Tenant-ID header
   ↓
7. Serviço recebe request:
   - Lê X-Tenant-ID
   - Injeta em context (Java: TenantContext; Go: context.Context)
   - Qualquer query DB: RLS policy aplica-se automaticamente
   ↓
8. Audit log: user_id + tenant_id + ação + timestamp
```

---

## 8. Decisões Arquiteturais (ADRs)

Veja detalhes em [`./docs/adr/`](./adr/):

- **ADR-001**: Kafka como Event Bus (vs RabbitMQ, Event Grid)
- **ADR-002**: PostgreSQL como DB Principal (vs Mongo polyglot, MySQL)
- **ADR-003**: OpenTelemetry para Observabilidade (vs Datadog, New Relic)
- **ADR-004**: RLS + JWT para Multi-Tenancy (vs schema-per-tenant)
- **ADR-005**: gRPC + Protobuf para S2S (vs REST, GraphQL)

---

## 9. Implementação e Próximos Passos

### Fase 1 (MVP - 3 meses)

- [ ] Infraestrutura base: GKE, Postgres, Kafka, OTEL Collector, Jaeger, Prometheus.
- [ ] Serviços: `auth-service`, `edital-service`, `cotacao-service`, `notificacao-service`.
- [ ] Frontend: Dashboard principal, gestão de editais, cotações.
- [ ] Modelo multi-tenant: RLS + JWT (sem schema-per-tenant).
- [ ] CI/CD: buf lint, helm lint, trivy, Snyk, test coverage.

### Fase 2 (Q2 2026)

- [ ] `extracao-service` (OCR/NLP robusto).
- [ ] `fornecedor-service` + portal.
- [ ] `estoque-service` + integração ERP.
- [ ] CQRS para relatórios (read model separado).
- [ ] Schema-per-tenant para clientes enterprise.

### Fase 3 (Q3 2026+)

- [ ] Sharding de banco de dados por tenant.
- [ ] IA/ML: sugestões automáticas, análise de risco de proposta.
- [ ] Integrações avançadas: Diários Oficiais, APIs de licitação internacionais.
- [ ] Marketplace de fornecedores.

---

## 10. Convenções de Desenvolvimento

### Projeto Layout (Java/Gradle)

```
service-name/
├── build.gradle
├── settings.gradle
├── gradlew
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/cotai/servicename/
│   │   │       ├── api/
│   │   │       │   └── CotacaoController.java
│   │   │       ├── service/
│   │   │       │   └── CotacaoService.java
│   │   │       ├── repository/
│   │   │       │   └── CotacaoRepository.java
│   │   │       ├── domain/
│   │   │       │   └── Cotacao.java
│   │   │       ├── config/
│   │   │       │   └── OpenTelemetryConfig.java
│   │   │       └── Application.java
│   │   └── resources/
│   │       ├── application.yml
│   │       └── logback-spring.xml
│   └── test/
│       └── java/
│           └── com/cotai/servicename/
│               ├── api/
│               ├── service/
│               └── repository/
├── Dockerfile
├── charts/
│   └── service-name/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           └── hpa.yaml
└── README.md
```

### Projeto Layout (Go)

```
service-name/
├── go.mod
├── go.sum
├── main.go
├── Dockerfile
├── Makefile
├── internal/
│   ├── api/
│   │   └── handler.go
│   ├── service/
│   │   └── service.go
│   ├── repository/
│   │   └── repository.go
│   └── domain/
│       └── model.go
├── pkg/
│   └── shared/
│       └── util.go
├── test/
│   └── integration_test.go
├── charts/
│   └── service-name/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
└── README.md
```

### Qualidade de Código

- **Testing**: Unit tests (80%+ coverage), integration tests, E2E smoke tests.
- **Linting**: golangci-lint (Go), checkstyle/spotbugs (Java), sonarqube.
- **Dependencies**: Snyk scan, OWASP dependency-check.
- **Security**: Static analysis (SAST), no hardcoded secrets, Vault integration.
- **Documentation**: GoDoc / Javadoc, architecture ADRs, runbooks para operações.

---

## 11. Referências e Links

- [Protobuf Style Guide](https://developers.google.com/protocol-buffers/docs/style)
- [OpenTelemetry Documentation](https://opentelemetry.io/)
- [Kafka Best Practices](https://kafka.apache.org/documentation/#bestpractices)
- [PostgreSQL RLS](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- [Kubernetes HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Go Interfaces Best Practices](https://golang.org/blog/error-handling-and-go)
- [Spring Boot Actuator](https://spring.io/guides/gs/actuator-service/)

---

**Versão**: 1.0 | **Última Atualização**: Dezembro 2025 | **Mantido por**: DevOps + Architecture Team
