# ADR-003: OpenTelemetry para Observabilidade

**Status**: Aprovado  
**Data**: Dezembro 2025  
**Decisores**: DevOps Team, Platform Engineers

---

## Contexto

Cotai precisa de observabilidade completa (traces, métricas, logs) para:
- Debugging distribuído (rastrear um request através de 5+ serviços).
- Performance profiling (latência P95, P99).
- Alertas proativos (SLO violations).
- Compliance: auditoria de ações críticas.

### Opções Consideradas

1. **OpenTelemetry + Jaeger + Prometheus + Loki** ✅
2. Datadog
3. New Relic
4. Dynatrace
5. ELK (Elasticsearch, Logstash, Kibana)

---

## Decisão

**OpenTelemetry como padrão de observabilidade**, com:
- **Jaeger** para traces distribuídos.
- **Prometheus** para métricas.
- **Loki** para logs estruturados.
- **Grafana** para dashboards unificados.

### Rationale

| Critério | OpenTelemetry | Datadog | New Relic | Dynatrace | ELK |
|----------|--|--|--|--|--|
| **Licença** | ✅ Open source | ❌ SaaS comercial | ❌ SaaS comercial | ❌ SaaS comercial | ✅ Open source |
| **Custo** | Baixo (self-hosted) | Alto (volume) | Alto (volume) | Alto (premium) | Médio |
| **Traces distribuído** | ✅ Nativo (Jaeger) | ✅ Excelente | ✅ Excelente | ✅ Excelente | ⚠️ Customizado |
| **Metrics** | ✅ Prometheus | ✅ Nativo | ✅ Nativo | ✅ Nativo | ⚠️ Customizado |
| **Logs** | ✅ Loki | ✅ Nativo | ✅ Nativo | ✅ Nativo | ✅ Native (Kibana) |
| **Vendor lock-in** | ✅ Nenhum | ❌ Alto | ❌ Alto | ❌ Alto | ⚠️ Médio |
| **Community** | ✅ CNCF, muito grande | ✅ Grande | ✅ Grande | ✅ Grande | ✅ Grande |
| **Escalabilidade** | ✅ Horizontal | ✅ Escalável | ✅ Escalável | ✅ Escalável | ⚠️ Requer tuning |

**Vencedor**: OpenTelemetry oferece **portabilidade** (sem vendor lock-in), **padrão aberto** (fácil migração), **integração Kubernetes nativa**, e **custo previsível**.

---

## Implicações

### Positivas

1. ✅ **Vendor-agnostic**: Exportar para Jaeger, Datadog, Grafana Cloud, etc. sem recodificar.
2. ✅ **CNCF standard**: Comunidade enorme, suporte em todos os frameworks (Spring, Go, Python, Node).
3. ✅ **Observabilidade completa**: Traces, métricas, logs em um stack coeso.
4. ✅ **Context propagation**: W3C trace context, baggage para tenant_id, user_id.
5. ✅ **Performance**: Sampling configurável (reduz volume em produção).
6. ✅ **Segments/Attributes**: Rastrear tenant_id, user_id, action automaticamente.

### Negativas

1. ❌ **Curva de aprendizado**: Configuração inicial requer entender traces, spans, exporters.
2. ❌ **Overhead**: Se não tuned corretamente, pode gerar lixo de spans (verbose).
3. ❌ **Múltiplos backends**: Gerenciar Jaeger, Prometheus, Loki separadamente (vs Datadog all-in-one).

### Mitigações

- **Aprendizado**: Começar com padrão simples (traces básicos); evoluir para custom spans/attributes.
- **Overhead**: Usar sampling (ex: 10% in production, 100% in staging) e batch exporters.
- **Gerenciamento**: Usar Grafana Cloud (hosted) para Prometheus/Loki se preferir managed.

---

## Arquitetura da Stack

```
┌─────────────────────────────────────────────────┐
│         Aplicações (Serviços Cotai)              │
│    OpenTelemetry SDK (Tracer, Meter, Logger)    │
└──────────────────────┬──────────────────────────┘
                       │
                       ↓
         ┌──────────────────────────────┐
         │   OTEL Collector (Kubernetes) │
         │  (Batch processor, Sampler)   │
         └──────────────┬────────────────┘
                        │
         ┌──────────────┼──────────────┬─────────────┐
         ↓              ↓              ↓             ↓
    ┌─────────┐   ┌──────────┐  ┌─────────┐  ┌────────┐
    │  Jaeger │   │Prometheus│  │  Loki   │  │ OTLP   │
    │(Traces) │   │ (Metrics)│  │ (Logs)  │  │(Buffer)│
    └────┬────┘   └────┬─────┘  └────┬────┘  └────────┘
         │              │             │
         └──────────────┼─────────────┘
                        ↓
                   ┌─────────────┐
                   │   Grafana   │
                   │(Dashboards) │
                   └──────┬──────┘
                          ↓
                   ┌─────────────┐
                   │AlertManager │
                   │(Slack/Email)│
                   └─────────────┘
```

---

## Configuração Helm (Stack Observabilidade)

```yaml
# charts/observability/values.yaml

# OTEL Collector
otelCollector:
  enabled: true
  image:
    repository: otel/opentelemetry-collector-k8s
    tag: "0.88.0"
  
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      
      # Para métricas Prometheus
      prometheus:
        config:
          scrape_configs:
            - job_name: 'kubernetes-pods'
              kubernetes_sd_configs:
                - role: pod
    
    processors:
      batch:
        timeout: 10s
        send_batch_size: 1024
      
      sampling:
        sampling_percentage: 10  # 10% in prod
      
      attributes:
        actions:
          - key: environment
            value: production
            action: insert
          - key: service.version
            from_attribute: service.version
            action: insert
    
    exporters:
      jaeger:
        endpoint: jaeger-collector:14250
      
      prometheus:
        endpoint: 0.0.0.0:8888
      
      loki:
        endpoint: http://loki:3100/loki/api/v1/push
    
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch, sampling, attributes]
          exporters: [jaeger]
        
        metrics:
          receivers: [otlp, prometheus]
          processors: [batch, attributes]
          exporters: [prometheus]
        
        logs:
          receivers: [otlp]
          processors: [batch, attributes]
          exporters: [loki]

# Jaeger
jaeger:
  enabled: true
  strategy: allInOne  # MVP; escalar para distributed em produção
  image:
    tag: "1.50.0"
  
  persistence:
    enabled: true
    size: 50Gi
    storageClassName: fast-ssd
  
  ingester:
    cassandra:
      enabled: false  # Use Elasticsearch em escala
  
  queryService:
    nodePort: 30686  # Acessível externamente

# Prometheus
prometheus:
  enabled: true
  image:
    tag: "v2.47.2"
  
  persistence:
    size: 100Gi
    storageClassName: fast-ssd
  
  retention: 30d
  
  additionalScrapeConfigs:
    - job_name: 'kubernetes-nodes'
      kubernetes_sd_configs:
        - role: node
    
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
        - role: pod

# Loki
loki:
  enabled: true
  image:
    tag: "2.9.4"
  
  persistence:
    enabled: true
    size: 50Gi
    storageClassName: fast-ssd
  
  config:
    limits_config:
      retention_period: 720h  # 30 dias
    
    schema_config:
      configs:
        - from: 2024-01-01
          store: boltdb-shipper
          object_store: filesystem
          index:
            prefix: index_
            period: 24h

# Grafana
grafana:
  enabled: true
  image:
    tag: "10.2.0"
  
  datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus:9090
    
    - name: Jaeger
      type: jaeger
      url: http://jaeger-collector:16686
    
    - name: Loki
      type: loki
      url: http://loki:3100
  
  persistence:
    enabled: true
    size: 10Gi
```

---

## Instrumentação em Código

### Java (Spring Boot + OpenTelemetry)

```java
// Dependências (build.gradle)
dependencies {
  implementation 'io.opentelemetry:opentelemetry-api:1.31.0'
  implementation 'io.opentelemetry:opentelemetry-sdk:1.31.0'
  implementation 'io.opentelemetry.instrumentation:opentelemetry-spring-boot-starter:1.31.0'
  implementation 'io.opentelemetry.exporter:opentelemetry-exporter-otlp:1.31.0'
}

// Configuração automática via Spring Boot starter (auto-config)
// application.yml
otel:
  sdk:
    disabled: false
  exporter:
    otlp:
      endpoint: "http://otel-collector:4317"
  metrics:
    export:
      interval: 10000
  logs:
    exporter: otlp
  traces:
    exporter: otlp
    sampler:
      type: parentbased_traceidratio
      arg: "0.1"  # 10% sampling in prod
  resource:
    attributes:
      service.name: "cotacao-service"
      environment: "production"

// Instrumentation customizada
@Component
public class CotacaoInstrumentation {
  private final Tracer tracer = GlobalOpenTelemetry.getTracer(
    "com.cotai.cotacao.service", "1.0.0");
  
  public List<Cotacao> listarPorTenant(UUID tenantId) {
    Span span = tracer.spanBuilder("cotacao.listar")
      .setAttribute("tenant_id", tenantId.toString())
      .setAttribute("action", "list")
      .startSpan();
    
    try (Scope scope = span.makeCurrent()) {
      List<Cotacao> cotacoes = repository.findAll(tenantId);
      span.setAttribute("result.count", cotacoes.size());
      span.setStatus(StatusCode.OK);
      return cotacoes;
    } catch (Exception e) {
      span.recordException(e);
      span.setStatus(StatusCode.ERROR, e.getMessage());
      throw e;
    } finally {
      span.end();
    }
  }
}

// Logging estruturado com context
@Slf4j
@Service
public class CotacaoService {
  private final Tracer tracer;
  
  public void aprovarCotacao(UUID tenantId, UUID cotacaoId) {
    Span span = tracer.spanBuilder("cotacao.aprovar")
      .setAttribute("tenant_id", tenantId.toString())
      .setAttribute("cotacao_id", cotacaoId.toString())
      .setAttribute("user_id", getCurrentUserId())
      .startSpan();
    
    try (Scope scope = span.makeCurrent()) {
      // Log com trace context
      log.info("Aprovando cotação", 
        Map.of(
          "tenant_id", tenantId,
          "cotacao_id", cotacaoId,
          "trace_id", span.getSpanContext().getTraceId()
        )
      );
      
      repository.updateStatus(cotacaoId, CotacaoStatus.APROVADA);
      
      // Métrica
      meter.counter("cotacao.aprovacoes_total")
        .add(1, Attributes.of(
          AttributeKey.stringKey("tenant_id"), tenantId.toString()
        ));
      
      span.setStatus(StatusCode.OK);
    } catch (Exception e) {
      span.recordException(e);
      span.setStatus(StatusCode.ERROR);
      log.error("Erro ao aprovar cotação", e);
      throw e;
    } finally {
      span.end();
    }
  }
}
```

### Go (OpenTelemetry SDK)

```go
package main

import (
  "context"
  "go.opentelemetry.io/otel"
  "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
  "go.opentelemetry.io/otel/sdk/resource"
  "go.opentelemetry.io/otel/sdk/trace"
  semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
)

func initTracer() (*trace.TracerProvider, error) {
  exporter, err := otlptracegrpc.New(context.Background(),
    otlptracegrpc.WithEndpoint("otel-collector:4317"),
  )
  if err != nil {
    return nil, err
  }
  
  tp := trace.NewTracerProvider(
    trace.WithBatcher(exporter),
    trace.WithResource(resource.NewWithAttributes(
      context.Background(),
      semconv.ServiceNameKey.String("cotacao-service"),
      semconv.ServiceVersionKey.String("1.0.0"),
    )),
  )
  
  otel.SetTracerProvider(tp)
  return tp, nil
}

// Usar em handler
func (h *CotacaoHandler) List(ctx context.Context, req *ListRequest) (*ListResponse, error) {
  tracer := otel.Tracer("com.cotai.cotacao.handler")
  
  ctx, span := tracer.Start(ctx, "cotacao.list",
    trace.WithAttributes(
      attribute.String("tenant_id", req.TenantId),
    ),
  )
  defer span.End()
  
  cotacoes, err := h.service.ListByTenant(ctx, req.TenantId)
  if err != nil {
    span.RecordError(err)
    return nil, err
  }
  
  span.SetAttributes(
    attribute.Int("result.count", len(cotacoes)),
  )
  
  return &ListResponse{Cotacoes: cotacoes}, nil
}
```

---

## SLOs e Alertas

```yaml
# Prometheus recording rules
groups:
  - name: cotai_slos
    rules:
      - record: slo:api_request_duration:p95
        expr: histogram_quantile(0.95, 
          sum(rate(http_request_duration_seconds_bucket[5m])) 
          by (le, endpoint))
      
      - record: slo:error_rate:5m
        expr: sum(rate(http_requests_total{status=~"5.."}[5m])) 
          by (endpoint)
      
      - record: slo:availability:1h
        expr: (1 - (sum(rate(http_requests_total{status=~"5.."}[1h])) / 
          sum(rate(http_requests_total[1h])))) * 100

# Alert rules
  - name: cotai_alerts
    rules:
      - alert: HighLatencyP95
        expr: slo:api_request_duration:p95 > 0.5
        for: 10m
        annotations:
          summary: "Latência elevada detectada"
          description: "P95 > 500ms por 10 minutos"
      
      - alert: HighErrorRate
        expr: slo:error_rate:5m > 0.02
        for: 5m
        annotations:
          summary: "Taxa de erro acima do SLO"
          description: "Erro rate > 2%"
      
      - alert: TraceExportFailure
        expr: rate(otelcol_exporter_send_failed_spans_total[5m]) > 100
        for: 5m
        annotations:
          summary: "Falha ao exportar traces"
```

---

## Checklist de Implementação

- [ ] Instalar OTEL Collector via Helm.
- [ ] Configurar Jaeger, Prometheus, Loki.
- [ ] Adicionar OpenTelemetry SDK aos serviços.
- [ ] Implementar instrumentação automática (auto-config).
- [ ] Adicionar spans customizados para domínio (aprovação, extração, etc).
- [ ] Configurar sampling (10% prod, 100% staging).
- [ ] Testar propagação de trace_id através de múltiplos serviços.
- [ ] Criar dashboards Grafana (latência, throughput, erros, tenant metrics).
- [ ] Configurar AlertManager (Slack, PagerDuty).
- [ ] Treinar time em debugging com Jaeger.

---

## Referências

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Jaeger Getting Started](https://www.jaegertracing.io/docs/)
- [Prometheus Scrape Configs](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Loki for Log Aggregation](https://grafana.com/docs/loki/latest/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)

---

**Próximo**: ADR-004 (RLS + JWT para Multi-Tenancy)
