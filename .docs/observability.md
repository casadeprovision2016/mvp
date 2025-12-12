# Observabilidade e SLOs — Cotai

**Versão**: 1.0  
**Data**: Dezembro 2025

---

## 1. Visão Geral

A observabilidade em Cotai é construída sobre **OpenTelemetry** com exportação para **Jaeger** (traces), **Prometheus** (métricas) e **Loki** (logs), unificadas em **Grafana** para dashboards e alertas via **AlertManager**.

### Stack Recomendada

```
Aplicações (SDK OpenTelemetry)
         ↓
OTEL Collector (agregador, sampler)
         ↓
    ├→ Jaeger (traces distribuídos)
    ├→ Prometheus (métricas)
    └→ Loki (logs estruturados)
         ↓
    Grafana (visualização)
    AlertManager (notificações)
```

---

## 2. Traces Distribuídos (Jaeger)

### 2.1 Conceitos Chave

- **Trace**: Caminho completo de uma requisição (ex: API → cotacao-service → fornecedor-service → DB).
- **Span**: Uma operação dentro do trace (ex: "db_query", "http_call", "cache_lookup").
- **Trace ID**: Identificador único do trace (propagado entre serviços).
- **Span ID**: Identificador único do span dentro do trace.
- **W3C Trace Context**: Padrão aberto para propagação (HTTP headers, gRPC metadata).

### 2.2 Instrumentação Obrigatória

Todos os serviços devem tracer:

1. **Entrada HTTP/gRPC** (automatic):
   - Endpoint, método, status, latência.
   - Usuário (user_id), tenant_id.

2. **Operações críticas** (manual):
   - Queries de banco de dados (latência, tipo).
   - Chamadas gRPC para outros serviços.
   - Operações Kafka (publish, consume).
   - Chamadas HTTP externas (APIs terceiros).
   - Processamento OCR/NLP (duração, status).

3. **Eventos de negócio** (manual):
   - "cotacao.resposta_recebida"
   - "fornecedor.avaliado"
   - "edital.extracao_iniciada"

### 2.3 Exemplo: Instrumentação Java

```java
@Slf4j
@RestController
@RequestMapping("/api/cotacao")
public class CotacaoController {
  
  @Autowired
  private CotacaoService cotacaoService;
  
  private final Tracer tracer = GlobalOpenTelemetry.getTracer(
    "com.cotai.cotacao", "1.0.0");
  
  @PostMapping
  public ResponseEntity<CotacaoDTO> criar(
      @RequestBody CotacaoRequest request,
      @RequestHeader("X-Tenant-ID") String tenantId) {
    
    Span span = tracer.spanBuilder("cotacao.criar")
      .setAttribute("http.method", "POST")
      .setAttribute("http.url", "/api/cotacao")
      .setAttribute("tenant_id", tenantId)
      .setAttribute("user_id", getCurrentUserId())
      .startSpan();
    
    try (Scope scope = span.makeCurrent()) {
      log.info("Criando cotação", Map.of(
        "tenant_id", tenantId,
        "trace_id", span.getSpanContext().getTraceId(),
        "num_itens", request.getItens().size()
      ));
      
      CotacaoDTO result = cotacaoService.criar(tenantId, request);
      
      span.setAttribute("http.status_code", 201);
      span.setAttribute("result.id", result.getId());
      span.setStatus(StatusCode.OK);
      
      return ResponseEntity.status(201).body(result);
      
    } catch (Exception e) {
      span.recordException(e);
      span.setAttribute("http.status_code", 500);
      span.setStatus(StatusCode.ERROR, e.getMessage());
      log.error("Erro ao criar cotação", e);
      throw e;
    } finally {
      span.end();
    }
  }
}

@Slf4j
@Service
public class CotacaoService {
  
  @Autowired
  private CotacaoRepository repository;
  
  @Autowired
  private FornecedorServiceClient fornecedorClient;
  
  private final Tracer tracer = GlobalOpenTelemetry.getTracer(
    "com.cotai.cotacao.service", "1.0.0");
  
  public CotacaoDTO criar(String tenantId, CotacaoRequest request) {
    Span span = tracer.spanBuilder("cotacao.service.criar")
      .setAttribute("tenant_id", tenantId)
      .startSpan();
    
    try (Scope scope = span.makeCurrent()) {
      
      // 1. Validar fornecedor (gRPC call)
      Span validationSpan = tracer.spanBuilder("fornecedor.validacao")
        .setAttribute("fornecedor_id", request.getFornecedorId())
        .startSpan();
      
      try (Scope valScope = validationSpan.makeCurrent()) {
        boolean isQualified = fornecedorClient.isQualified(
          tenantId, request.getFornecedorId());
        
        if (!isQualified) {
          throw new BusinessException("Fornecedor não qualificado");
        }
        
        validationSpan.setStatus(StatusCode.OK);
      } catch (Exception e) {
        validationSpan.recordException(e);
        validationSpan.setStatus(StatusCode.ERROR);
        throw e;
      } finally {
        validationSpan.end();
      }
      
      // 2. Persistir cotação (DB call)
      Span dbSpan = tracer.spanBuilder("db.insert.cotacao")
        .setAttribute("db.system", "postgresql")
        .setAttribute("db.operation", "INSERT")
        .startSpan();
      
      try (Scope dbScope = dbSpan.makeCurrent()) {
        Cotacao cotacao = Cotacao.builder()
          .tenantId(UUID.fromString(tenantId))
          .fornecedorId(UUID.fromString(request.getFornecedorId()))
          .itens(request.getItens())
          .status(CotacaoStatus.RASCUNHO)
          .build();
        
        Cotacao saved = repository.save(cotacao);
        
        dbSpan.setAttribute("db.rows_affected", 1);
        dbSpan.setStatus(StatusCode.OK);
        
        span.setAttribute("cotacao_id", saved.getId());
        span.setStatus(StatusCode.OK);
        
        return mapToDTO(saved);
        
      } catch (Exception e) {
        dbSpan.recordException(e);
        dbSpan.setStatus(StatusCode.ERROR);
        throw e;
      } finally {
        dbSpan.end();
      }
      
    } catch (Exception e) {
      span.recordException(e);
      span.setStatus(StatusCode.ERROR);
      throw e;
    } finally {
      span.end();
    }
  }
}
```

### 2.4 Propagação de Trace Context

**HTTP (REST)**:

```
Request A → Service 1
  traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
  tracestate: vendor-specific-data

Service 1 → Service 2 (gRPC)
  Metadata:
    traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-<new_span_id>-01
    tracestate: ...
```

**Configuração automática (Spring Cloud Sleuth)**:

```java
// build.gradle
dependencies {
  implementation 'org.springframework.cloud:spring-cloud-starter-sleuth:3.1.0'
  implementation 'org.springframework.cloud:spring-cloud-sleuth-otel:3.1.0'
}

// application.yml
spring:
  sleuth:
    otel:
      enabled: true
```

### 2.5 Dashboard Jaeger

**Consultar traces**:

1. Jaeger UI: `http://jaeger.cotai.com:16686`
2. Buscar por tag:
   - `tenant_id = "abc123"`
   - `span.kind = "INTERNAL"`
   - `http.status_code = "500"`
3. Visualizar fluxo completo (timeline de spans).

---

## 3. Métricas (Prometheus)

### 3.1 Métricas Obrigatórias

Todos os serviços devem exportar:

#### HTTP/gRPC Metrics

```
# Latência de requisição
http_request_duration_seconds{method="POST", endpoint="/api/cotacao", status="201"}
grpc_server_handling_seconds{method="CotacaoService/Criar", status="OK"}

# Taxa de requisição
http_requests_total{method="POST", endpoint="/api/cotacao", status="201"}

# Taxa de erro
http_requests_total{status="5xx"}
```

#### Métricas de Negócio

```
# Cotações criadas
cotacao_created_total{tenant_id="abc", status="rascunho"}

# Aprovações
cotacao_approved_total{tenant_id="abc", approver_role="director"}

# Tempo médio de resposta do fornecedor
fornecedor_response_time_seconds{quantile="0.95", fornecedor_id="xyz"}

# Itens extraídos (OCR)
edital_items_extracted_total{tenant_id="abc", status="sucesso"}
edital_extraction_duration_seconds{tenant_id="abc", quantile="0.99"}
```

#### Infraestrutura Metrics

```
# Cache
redis_hits_total
redis_misses_total
redis_evictions_total

# Database
postgres_connections{instance="primary"}
postgres_slow_queries_total
postgres_replication_lag_seconds

# Kafka
kafka_consumer_lag_sum{topic="edital.publicado"}
kafka_messages_consumed_total{topic="edital.publicado"}
```

### 3.2 Exemplo: Instrumentação Go

```go
package main

import (
  "github.com/prometheus/client_golang/prometheus"
  "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
  cotacaoCreatedTotal = prometheus.NewCounterVec(
    prometheus.CounterOpts{
      Name: "cotacao_created_total",
      Help: "Total cotações criadas",
    },
    []string{"tenant_id", "status"},
  )
  
  cotacaoApprovalDuration = prometheus.NewHistogramVec(
    prometheus.HistogramOpts{
      Name: "cotacao_approval_duration_seconds",
      Help: "Tempo para aprovação de cotação",
      Buckets: []float64{0.1, 0.5, 1, 5, 10, 30},
    },
    []string{"tenant_id", "approver_role"},
  )
  
  fornecedorResponseTime = prometheus.NewHistogramVec(
    prometheus.HistogramOpts{
      Name: "fornecedor_response_time_seconds",
      Help: "Tempo de resposta do fornecedor",
      Buckets: []float64{3600, 7200, 86400},  // 1h, 2h, 1d
    },
    []string{"fornecedor_id"},
  )
)

func init() {
  prometheus.MustRegister(cotacaoCreatedTotal)
  prometheus.MustRegister(cotacaoApprovalDuration)
  prometheus.MustRegister(fornecedorResponseTime)
}

func (h *CotacaoHandler) Create(ctx context.Context, req *CreateRequest) (*CreateResponse, error) {
  start := time.Now()
  
  cotacao, err := h.service.Create(ctx, req)
  if err != nil {
    return nil, err
  }
  
  // Registrar métrica
  tenantID := ctx.Value("tenant_id").(string)
  cotacaoCreatedTotal.WithLabelValues(tenantID, "rascunho").Inc()
  
  return &CreateResponse{Cotacao: cotacao}, nil
}

func main() {
  http.Handle("/metrics", promhttp.Handler())
  http.ListenAndServe(":8080", nil)
}
```

---

## 4. Logs Estruturados (Loki)

### 4.1 Formato JSON

Todos os logs devem ser JSON com contexto:

```json
{
  "timestamp": "2025-12-12T14:30:45.123Z",
  "level": "INFO",
  "service": "cotacao-service",
  "message": "Cotação criada com sucesso",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "tenant_id": "abc123",
  "user_id": "user-xyz",
  "cotacao_id": "cotacao-999",
  "duration_ms": 245,
  "status": "success"
}
```

### 4.2 Configuração Logback (Java)

```xml
<!-- logback-spring.xml -->
<configuration>
  <appender name="jsonStdout" class="ch.qos.logback.core.ConsoleAppender">
    <encoder class="net.logstash.logback.encoder.LogstashEncoder">
      <customFields>{"service":"cotacao-service","environment":"production"}</customFields>
    </encoder>
  </appender>
  
  <root level="INFO">
    <appender-ref ref="jsonStdout"/>
  </root>
</configuration>
```

### 4.3 Loki Query

```
{job="cotacao-service", tenant_id="abc123"}
  | json
  | level="ERROR"
  | logfmt
```

---

## 5. SLIs (Service Level Indicators)

**SLI** = Métrica quantificável que mede o desempenho de um serviço.

### 5.1 SLIs Obrigatórios por Serviço

Cada serviço deve exportar no mínimo:

#### A. Latência (Request Duration)

**O quê**: Tempo entre recebimento de requisição e envio de resposta (incluindo processamento + I/O)

**Como medir**:
```
histogram_quantile(0.95, http_request_duration_seconds_bucket)  # P95
histogram_quantile(0.99, http_request_duration_seconds_bucket)  # P99
```

**Buckets padrão**: 0.005s, 0.01s, 0.025s, 0.05s, 0.1s, 0.25s, 0.5s, 1s, 2.5s, 5s, 10s

**Por serviço**:
- `edital-service`: P95 < 300ms, P99 < 500ms
- `cotacao-service`: P95 < 400ms, P99 < 800ms (mais complexo)
- `auth-service`: P95 < 100ms, P99 < 200ms (crítico, deve ser rápido)
- `notificacao-service`: P95 < 5s, P99 < 10s (async, menos crítico)

#### B. Taxa de Erro (Error Rate)

**O quê**: % de requisições que resultam em erro (5xx, timeout, exceção)

**Como medir**:
```
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])
```

**Target**: < 0.5% (99.5% de sucesso)

**Por endpoint crítico**:
- POST `/api/edital` (criação): < 0.1%
- POST `/api/cotacao` (submissão): < 0.1%
- GET `/api/edital/{id}` (leitura): < 0.5%

#### C. Disponibilidade (Uptime)

**O quê**: % de tempo que o serviço está acessível (healthcheck HTTP 200)

**Como medir**:
```
avg_over_time(up{job="cotacao-service"}[30d])  # Uptime mensal
```

**Target**: 99.5% mensal (máx ~216 minutos de downtime/mês)

#### D. Taxa de Sucesso (Success Rate)

**O quê**: % de operações de negócio completadas com sucesso

**Como medir** (exemplos por domínio):
```
# Tenders criados com sucesso
rate(tenders_created_total[5m]) / rate(tender_creation_requests_total[5m])

# Cotações submetidas com sucesso
rate(quotations_submitted_total[5m]) / rate(quotation_submission_requests_total[5m])

# Fornecedores onboarded com sucesso
rate(vendors_registered_success_total[5m]) / rate(vendor_registration_requests_total[5m])
```

**Target**: > 99%

#### E. Throughput (Requests Per Second)

**O quê**: Número de requisições processadas por segundo

**Como medir**:
```
rate(http_requests_total[5m])
```

**Target** (por ambiente):
- Dev: 100 req/s
- Staging: 1k req/s
- Prod: 10k req/s (scalable via autoscaling)

#### F. Duração de Operações Críticas (Business SLIs)

Para operações de negócio importantes, adicione SLIs específicas:

**Exemplo: Processamento OCR**

```
# Duração do OCR (percentis)
histogram_quantile(0.95, ocr_processing_duration_seconds_bucket)  # P95

# Sucesso de OCR
rate(ocr_processing_success_total[5m]) / rate(ocr_processing_requests_total[5m])
```

**Target**: P95 < 60s, sucesso > 98%

**Exemplo: Submissão de Quotação**

```
# Latência de submissão
histogram_quantile(0.95, quotation_submission_duration_seconds_bucket)  # P95

# Taxa de erro
rate(quotation_submission_errors_total[5m]) / rate(quotation_submission_requests_total[5m])
```

**Target**: P95 < 500ms, erro < 0.5%

### 5.2 Instrumentação: Como Exportar SLIs

#### Go Example

```go
import "github.com/prometheus/client_golang/prometheus"

// Request duration histogram
var httpDuration = prometheus.NewHistogramVec(
  prometheus.HistogramOpts{
    Name: "http_request_duration_seconds",
    Help: "Duration of HTTP requests",
    Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
  },
  []string{"method", "endpoint", "status"},
)

// Error counter
var httpErrors = prometheus.NewCounterVec(
  prometheus.CounterOpts{
    Name: "http_requests_total",
    Help: "Total HTTP requests",
  },
  []string{"method", "endpoint", "status"},
)

// Business metric: quotations submitted
var quotationsSubmitted = prometheus.NewCounterVec(
  prometheus.CounterOpts{
    Name: "quotations_submitted_total",
    Help: "Total quotations successfully submitted",
  },
  []string{"tenant_id", "vendor_id", "status"},
)

// Middleware: record metrics
func metricsMiddleware(next http.Handler) http.Handler {
  return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
    start := time.Now()
    
    // Wrap response writer to capture status
    wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}
    
    next.ServeHTTP(wrapped, r)
    
    duration := time.Since(start).Seconds()
    httpDuration.WithLabelValues(
      r.Method,
      r.URL.Path,
      strconv.Itoa(wrapped.statusCode),
    ).Observe(duration)
    
    if wrapped.statusCode >= 500 {
      httpErrors.WithLabelValues(
        r.Method,
        r.URL.Path,
        strconv.Itoa(wrapped.statusCode),
      ).Inc()
    }
  })
}
```

#### Java Example (Micrometer + Prometheus)

```java
import io.micrometer.prometheus.PrometheusMeterRegistry;
import io.micrometer.core.instrument.Timer;
import io.micrometer.core.instrument.Counter;

@Configuration
public class MetricsConfig {
  
  @Bean
  public MeterRegistry meterRegistry() {
    return new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);
  }
  
  @Bean
  public Timer httpRequestDuration(MeterRegistry registry) {
    return Timer.builder("http.request.duration")
      .description("HTTP request duration in seconds")
      .publishPercentiles(0.5, 0.95, 0.99)
      .register(registry);
  }
  
  @Bean
  public Counter quotationsSubmitted(MeterRegistry registry) {
    return Counter.builder("quotations.submitted.total")
      .description("Total quotations successfully submitted")
      .register(registry);
  }
}

@RestController
@RequestMapping("/api/quotations")
public class QuotationController {
  
  @Autowired
  private MeterRegistry meterRegistry;
  
  @PostMapping
  public ResponseEntity<QuotationDTO> submit(
      @RequestBody QuotationRequest request,
      @RequestHeader("X-Tenant-ID") String tenantId) {
    
    Timer timer = Timer.start(meterRegistry);
    
    try {
      QuotationDTO result = quotationService.submit(tenantId, request);
      
      meterRegistry.counter("quotations.submitted.total",
        "tenant_id", tenantId,
        "status", "success"
      ).increment();
      
      return ResponseEntity.status(201).body(result);
    } catch (Exception e) {
      meterRegistry.counter("quotations.submitted.total",
        "tenant_id", tenantId,
        "status", "error"
      ).increment();
      throw e;
    } finally {
      timer.stop(meterRegistry.timer("http.request.duration",
        "method", "POST",
        "endpoint", "/api/quotations"
      ));
    }
  }
}
```

### 5.3 SLI Dashboard (Grafana)

Crie um painel com as seguintes queries:

```json
{
  "panels": [
    {
      "title": "Request Latency P95",
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, endpoint))"
        }
      ]
    },
    {
      "title": "Error Rate (%)",
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{status=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m])) * 100"
        }
      ]
    },
    {
      "title": "Success Rate (%)",
      "targets": [
        {
          "expr": "sum(rate(quotations_submitted_total{status=\"success\"}[5m])) / sum(rate(quotations_submitted_total[5m])) * 100"
        }
      ]
    },
    {
      "title": "Uptime (30-day rolling)",
      "targets": [
        {
          "expr": "avg_over_time(up{job=\"~.*-service\"}[30d]) * 100"
        }
      ]
    }
  ]
}
```

---

## 6. SLOs (Service Level Objectives)

**SLO** = Meta quantificável baseada em SLIs. Exemplo: "99.5% de uptime" ou "P95 < 500ms"

### 6.1 Definições

| Métrica | SLO | Target | Alertar se |
|---------|-----|--------|-----------|
| **Latência API P95** | 500ms | 99% das requisições | > 2s por 10min |
| **Latência API P99** | 1s | 99% das requisições | > 3s por 10min |
| **Taxa de erro (5xx)** | < 0.5% | 99.5% sucesso | > 2% por 5min |
| **Disponibilidade** | 99.5% | 99.5% uptime | < 99% por 1h |
| **Latência OCR P95** | 60s | 99% dos PDFs | > 120s por 10min |
| **Throughput Kafka** | > 1000 msg/s | 99% do tempo | < 500 msg/s por 5min |
| **Replicação DB lag** | < 100ms | 99% do tempo | > 1s por 5min |

### 6.2 Cálculo de SLO (Error Budget)

```
Uptime SLO: 99.5%
Error Budget mensal: (1 - 0.995) * 43200 minutos = 216 minutos
```

**Interpretação**: Você tem 3.6 horas/mês de "downtime aceitável".

### 6.3 Recording Rules (Prometheus)

```yaml
groups:
  - name: cotai_slos
    interval: 30s
    rules:
      # Latência P95
      - record: slo:http_latency:p95_5m
        expr: histogram_quantile(0.95,
          sum(rate(http_request_duration_seconds_bucket[5m])) by (le, endpoint))
      
      # Taxa de erro
      - record: slo:http_error_rate:5m
        expr: sum(rate(http_requests_total{status=~"5.."}[5m])) by (endpoint) /
              sum(rate(http_requests_total[5m])) by (endpoint)
      
      # Disponibilidade (rolling window 30d)
      - record: slo:availability:30d
        expr: (1 - (sum_over_time(slo:http_error_rate:5m[30d]) /
               count_over_time(slo:http_error_rate:5m[30d]))) * 100
```

---

## 6. Alertas Críticos

### 6.1 AlertManager Rules

```yaml
groups:
  - name: cotai_alerts
    interval: 1m
    rules:
      
      - alert: HighLatency
        expr: slo:http_latency:p95_5m > 2
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Latência elevada em {{ $labels.endpoint }}"
          description: "P95 > 2s por 10 minutos"
          playbook: "runbooks/high-latency.md"
      
      - alert: HighErrorRate
        expr: slo:http_error_rate:5m > 0.02
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Taxa de erro elevada em {{ $labels.endpoint }}"
          description: "Taxa de erro > 2%"
          action: "pagerduty"
      
      - alert: KafkaConsumerLag
        expr: kafka_consumer_lag_sum{topic="edital.publicado"} > 100000
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Kafka lag elevado no tópico {{ $labels.topic }}"
      
      - alert: PostgreSQLConnectionPoolExhausted
        expr: postgres_connections > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Connection pool PostgreSQL quase cheio"
          action: "scale_up"
      
      - alert: OTELCollectorExportFailure
        expr: rate(otelcol_exporter_send_failed_spans_total[5m]) > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Falha ao exportar traces para Jaeger"
          description: "OTEL Collector não consegue alcançar Jaeger"
```

### 6.2 Roteamento de Alertas

```yaml
# alertmanager.yml
global:
  resolve_timeout: 5m

route:
  receiver: default
  group_by: [alertname, endpoint]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  routes:
    - match:
        severity: critical
      receiver: pagerduty
      repeat_interval: 5m
    
    - match:
        severity: warning
      receiver: slack
      repeat_interval: 2h

receivers:
  - name: default
    slack_configs:
      - api_url: ${SLACK_WEBHOOK_URL}
        channel: #alerts
  
  - name: pagerduty
    pagerduty_configs:
      - service_key: ${PAGERDUTY_SERVICE_KEY}
        description: "{{ .GroupLabels.alertname }}"
```

---

## 7. Dashboards Grafana

### 7.1 Dashboard Principal

**Painel 1: Health Check**
- Availability (%).
- Error rate (%).
- P95 latência.

**Painel 2: Throughput**
- Requisições/s por endpoint.
- Mensagens Kafka/s por tópico.

**Painel 3: Latência**
- P50, P95, P99 por endpoint.
- Traces mais lentos (links para Jaeger).

**Painel 4: Recursos**
- CPU/Memória dos pods.
- Disk usage PostgreSQL.
- Conexões Redis.

**Painel 5: Tenants**
- Top 10 tenants por requisições.
- Uso de storage por tenant.
- Ações críticas por tenant (audit).

### 7.2 JSON Model

```json
{
  "dashboard": {
    "title": "Cotai - Main Dashboard",
    "panels": [
      {
        "title": "Availability",
        "targets": [
          {
            "expr": "slo:availability:30d"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "min": 0,
            "max": 100,
            "unit": "percent"
          }
        }
      },
      {
        "title": "Error Rate (5min)",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{status=~\"5..\"}[5m])) by (endpoint)"
          }
        ]
      },
      {
        "title": "Trace Waterfall",
        "type": "jaeger-traces-panel",
        "datasource": "Jaeger"
      }
    ]
  }
}
```

---

## 8. Runbooks (On-Call Guide)

### 8.1 High Latency

```markdown
# High Latency Alert

## Sintomas
- P95 latência > 2s por 10 minutos

## Investigação
1. Jaeger: filtrar por `status="OK"` e `duration > 2000ms`
2. Identificar span mais lento (DB? gRPC call? OCR?)
3. Verificar logs: `grep "duration_ms > 2000"`

## Mitigações
- Escalar pods (HPA deve fazer automaticamente)
- Aumentar cache (Redis) para queries repetitivas
- Checklist slow queries: `SELECT * FROM pg_stat_statements LIMIT 10`
```

### 8.2 High Error Rate

```markdown
# High Error Rate Alert

## Sintomas
- Taxa de erro > 2% por 5 minutos

## Investigação
1. AlertManager: verificar qual endpoint
2. Grafana: dashboard de erro (status code 5xx)
3. Logs: `level="ERROR"` + `endpoint="/api/xyz"`
4. Jaeger: traces com `status="ERROR"`

## Mitigações
- Rollback última versão
- Escalar database connections (verificar pool)
- Chamar on-call engineers
```

---

## 9. Checklist de Implementação

- [ ] Instalar OTEL Collector, Jaeger, Prometheus, Loki, Grafana via Helm.
- [ ] Adicionar OpenTelemetry SDK aos serviços (Java/Go/Python).
- [ ] Implementar TenantContext + tenant_id em traces/métricas/logs.
- [ ] Criar dashboards Grafana (health, throughput, latência, tenants).
- [ ] Configurar AlertManager (Slack, PagerDuty).
- [ ] Definir SLO inicial: 99.5% uptime, P95 < 500ms, error rate < 0.5%.
- [ ] Testar end-to-end: requisição API → trace em Jaeger → métrica em Prometheus.
- [ ] Treinar time em debugging com Jaeger + logs estruturados.
- [ ] Documentar runbooks para alertas críticos.

---

## 10. Referências

- [OpenTelemetry Best Practices](https://opentelemetry.io/docs/best-practices/)
- [Prometheus Alerting](https://prometheus.io/docs/alerting/latest/overview/)
- [Grafana Dashboards Library](https://grafana.com/grafana/dashboards/)
- [Google SRE Book - SLOs](https://sre.google/sre-book/service-level-objectives/)

---

**Status**: Approved for Implementation  
**Mantido por**: DevOps + Platform Team
