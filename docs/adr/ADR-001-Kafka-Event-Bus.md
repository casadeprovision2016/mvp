# ADR-001: Apache Kafka como Event Bus

**Status**: Aprovado  
**Data**: Dezembro 2025  
**Decisores**: Architecture Team, Platform Engineers

---

## Contexto

O Cotai precisa de um backbone de mensageria para:
- Desacoplamento entre serviços (edital-service → extracao-service → cotacao-service).
- Propagação de eventos com auditoria (quem fez o quê, quando).
- Escalabilidade: processar milhares de eventos/segundo.
- Garantias de entrega e ordering (por tenant).

### Opções Consideradas

1. **Apache Kafka** ✅
2. RabbitMQ
3. Google Cloud Pub/Sub
4. AWS EventBridge / SQS+SNS

---

## Decisão

**Usar Apache Kafka como principal event bus** para Cotai.

### Rationale

| Critério | Kafka | RabbitMQ | GCP Pub/Sub | AWS EventBridge |
|----------|-------|----------|-------------|-----------------|
| **Throughput** | Ultra-alto (1M+ msg/s) | Alto (1M msg/s) | Alto | Alto |
| **Ordering** | ✅ Por partição | ❌ Não garantido | ❌ Não garantido | ❌ Não garantido |
| **Replayability** | ✅ Evento persistido | ❌ Deletado após consumo | ⚠️ Limited window | ⚠️ Limited window |
| **Custo (self-hosted)** | Baixo (cluster simples) | Baixo | N/A (managed) | N/A (managed) |
| **Ecosystem** | Conectores, Schema Registry, Streams API | Plugins limitados | Boas integrações GCP | Boas integrações AWS |
| **Multi-tenancy** | ✅ Particionamento por tenant | ⚠️ Manualmente | ⚠️ Manualmente | ⚠️ Manualmente |
| **Comunidade** | Muito grande, produção em massa | Grande | Grande (GCP) | Grande (AWS) |

**Vencedor**: Kafka é ideal para **ordering por tenant** (via partitionKey), **replay de eventos** (auditoria/compliance) e **escalabilidade massiva**.

---

## Implicações

### Positivas

1. ✅ **Auditoria imutável**: Todos os eventos persistidos; fácil replay se houver falha.
2. ✅ **Ordem garantida**: Partição por `tenant_id` = eventos de um tenant sempre na mesma sequência.
3. ✅ **Escalabilidade**: HPA de consumers independente de producers.
4. ✅ **Flex de tecnologia**: Kafka Streams para processamento real-time (agregações, CQRS).
5. ✅ **Integração ERP**: Connectors prontos (JDBC, Debezium CDC).

### Negativas

1. ❌ **Overhead operacional**: Cluster Kafka requer monitoramento, rebalancing, disk space planning.
2. ❌ **Latência (vs RabbitMQ)**: Kafka tem latência P99 um pouco maior (ms vs µs), mas aceitável.
3. ❌ **Complexidade**: Precisa tuning de retenção, compaction, replication factor.

### Mitigações

- **Operações**: Usar Kafka gerenciado (Confluent Cloud, AWS MSK) para reduzir overhead.
- **Latência**: Configurar compressão, batch size, para P99 < 500ms (aceitável para Cotai).
- **Retenção**: Definir políticas por tópico (ex: auditoria = 1 ano, transitórios = 7 dias).

---

## Topologia Recomendada

### Tópicos Principais

```
# Descoberta & Ingestão
edital.publicado
edital.normalizado
edital-extracao.iniciada
edital-extracao.concluida

# Cotações
cotacao.criada
cotacao.respondida
cotacao.analizada
cotacao.aprovada

# Fornecedores
fornecedor.criado
fornecedor.qualificado
fornecedor.avaliado

# Estoque
estoque.reservado
estoque.consumido
estoque.reabastecimento-necessario

# Notificações & Auditoria
notificacao.enviada
auditoria.acao
usuario.autenticado
```

### Particionamento

```yaml
topics:
  edital.publicado:
    partitions: 20              # Escalabilidade
    replication_factor: 3       # Alta disponibilidade
    retention_ms: 31536000000   # 1 ano (compliance)
    key: tenant_id              # Ordering por tenant
    
  auditoria.acao:
    partitions: 20
    replication_factor: 3
    retention_ms: 63072000000   # 2 anos (compliance LGPD)
    key: tenant_id
    
  notificacao.enviada:
    partitions: 10
    replication_factor: 3
    retention_ms: 604800000     # 7 dias
    key: tenant_id
```

---

## Configuração Exemplo (Helm)

```yaml
# charts/kafka/values.yaml
kafka:
  brokers: 3
  storageClass: "fast-ssd"
  storage: "100Gi"  # per broker
  
  topics:
    - name: edital.publicado
      partitions: 20
      replicationFactor: 3
      retentionMs: 31536000000
      
  config:
    log.retention.check.interval.ms: 300000
    log.segment.bytes: 1073741824
    compression.type: snappy

monitoring:
  prometheus:
    enabled: true
    interval: 30s
```

---

## Implementação em Código

### Java (Spring Cloud Stream + Kafka Binder)

```java
@Configuration
public class KafkaConfig {
  
  @Bean
  public KafkaTemplate<String, EditalPublicado> kafkaTemplate(
      ProducerFactory<String, EditalPublicado> pf) {
    return new KafkaTemplate<>(pf);
  }
  
  @Bean
  public ConsumerFactory<String, EditalPublicado> consumerFactory() {
    return new DefaultKafkaConsumerFactory<>(
      Map.of(
        ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, "kafka:9092",
        ConsumerConfig.GROUP_ID_CONFIG, "extracao-group",
        ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest"
      )
    );
  }
}

@Component
public class EditalEventPublisher {
  private final KafkaTemplate<String, EditalPublicado> kafkaTemplate;
  
  public void publish(EditalPublicado evento, String tenantId) {
    ProducerRecord<String, EditalPublicado> record =
      new ProducerRecord<>("edital.publicado", tenantId, evento);
    record.headers().add("tenant_id", tenantId.getBytes());
    record.headers().add("timestamp", String.valueOf(System.currentTimeMillis()).getBytes());
    
    kafkaTemplate.send(record)
      .addCallback(
        result -> log.info("Event sent: {}", evento.id),
        ex -> log.error("Event send failed", ex)
      );
  }
}

@Service
public class ExtracacaoService {
  @KafkaListener(topics = "edital.publicado", groupId = "extracao-group")
  public void processarEdital(ConsumerRecord<String, EditalPublicado> record) {
    String tenantId = record.key();
    EditalPublicado evento = record.value();
    
    // Iniciar OCR/NLP
    iniciarExtracao(tenantId, evento);
  }
}
```

### Go (Kafka reader)

```go
package main

import (
  "context"
  "github.com/segmentio/kafka-go"
  "log"
)

func consumeEdital(ctx context.Context) {
  reader := kafka.NewReader(kafka.ReaderConfig{
    Brokers:   []string{"kafka:9092"},
    Topic:     "edital.publicado",
    GroupID:   "extracao-group",
    Partition: 0,
  })
  
  for {
    msg, err := reader.ReadMessage(ctx)
    if err != nil {
      log.Fatal(err)
    }
    
    tenantID := string(msg.Key)
    // Parse evento e processar
    processarEdital(ctx, tenantID, msg.Value)
  }
}
```

---

## Referências

- [Kafka Official Documentation](https://kafka.apache.org/documentation/)
- [Confluent Best Practices](https://docs.confluent.io/platform/current/installation/best-practices.html)
- [Spring Cloud Stream + Kafka](https://spring.io/projects/spring-cloud-stream)
- [Kafka Streams for Event Processing](https://kafka.apache.org/documentation/#streams)

---

**Próximo**: ADR-002 (PostgreSQL como DB principal)
