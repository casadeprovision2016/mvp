# ADR-002: PostgreSQL como Database Principal

**Status**: Aprovado  
**Data**: Dezembro 2025  
**Decisores**: Architecture Team, Data Engineering

---

## Contexto

Cotai precisa de um datastore principal que suporte:
- Multi-tenancy com isolamento forte (RLS).
- ACID transactions (aprovações, pagamentos, contratos).
- Queries complexas (relatórios, agregações).
- Compliance: auditoria, retenção, criptografia em repouso.

### Opções Consideradas

1. **PostgreSQL** ✅
2. MongoDB (NoSQL polyglot)
3. CockroachDB (distributed ACID)
4. Cloud Spanner (Google)

---

## Decisão

**PostgreSQL 15+ como principal relational datastore** para todos os serviços do Cotai (MVP).

### Rationale

| Critério | PostgreSQL | MongoDB | CockroachDB | Cloud Spanner |
|----------|-----------|---------|------------|---------------|
| **ACID Compliance** | ✅ Nativo | ⚠️ Partial (v4+) | ✅ Nativo | ✅ Nativo |
| **RLS (Row-Level Security)** | ✅ Nativo | ❌ Aplicação | ❌ Aplicação | ⚠️ IAM roles |
| **Query Complexity** | ✅ SQL avançado | ⚠️ Agregações difíceis | ✅ SQL | ✅ SQL |
| **Relatórios/BI** | ✅ Excelente | ⚠️ Aggregation framework | ✅ Bom | ✅ Excelente |
| **Licença** | ✅ Open source | ✅ Open source | ✅ Open source | ❌ Comercial (Google) |
| **Custo (self-hosted)** | Baixo | Baixo | Médio | N/A (managed) |
| **Multi-tenancy RLS** | ✅ Built-in | ❌ Custom | ❌ Custom | ⚠️ Schemas |
| **Escalabilidade leitura** | ⚠️ Read replicas | ✅ Horizontal sharding | ✅ Nativo distribuído | ✅ Nativo distribuído |

**Vencedor**: PostgreSQL oferece **RLS nativo** (crítico para multi-tenancy segura), **ACID forte** e **excelente suporte a SQL complexo** (relatórios, análises).

---

## Implicações

### Positivas

1. ✅ **RLS nativo**: Políticas de isolamento tenant direto em SQL, sem aplicação layer.
2. ✅ **ACID forte**: Transações confiáveis para aprovações, pagamentos, contratos.
3. ✅ **Maduro e stável**: Usado em produção por décadas, comunidade vasta.
4. ✅ **JSON/JSONB**: Suporte a semi-structured data (documentos de licitação).
5. ✅ **Extensions**: pgvector (IA/embeddings), PostGIS (geo), pg_trgm (full-text search).
6. ✅ **Replicação**: Hot standby, streaming replication para HA.
7. ✅ **Tooling**: pgAdmin, dbeaver, Adminer (management).

### Negativas

1. ❌ **Escalabilidade vertical**: Sharding manual (vs CockroachDB automático).
2. ❌ **Writes distribuído**: Replicação é read-only; writes precisam de sharding explícito.
3. ❌ **Documentos massivos**: Não é ideal para documentos enormes (use S3 + metadata no PG).

### Mitigações

- **Escalabilidade**: Usar read replicas para BI/relatórios; sharding por tenant para futura crescimento.
- **Documentos**: Armazenar PDFs no S3, metadados + URI no PostgreSQL.
- **HA**: Postgres gerenciado (RDS, Cloud SQL) com automated failover.

---

## Topologia de Banco de Dados

### Padrão: Database-per-Service

Cada microserviço tem seu próprio banco de dados (schema isolado ou DB separado):

```
postgres-cluster
├── edital_db (edital-service)
├── extracao_db (extracao-service)
├── cotacao_db (cotacao-service)
├── fornecedor_db (fornecedor-service)
├── estoque_db (estoque-service)
├── notificacao_db (notificacao-service)
└── auth_db (auth-service)
```

**Ou** (se usar um cluster único com RLS):

```
postgres-cluster
└── cotai_db
    ├── public.tenant (todas as tabelas com tenant_id FK)
    ├── edital.edital_publicado
    ├── edital.item_edital
    ├── cotacao.cotacao
    ├── cotacao.resposta_cotacao
    ├── ...
    └── RLS policies aplicadas a cada schema
```

### Schema Example (Multi-Tenant RLS)

```sql
-- Schemas por domínio
CREATE SCHEMA IF NOT EXISTS edital;
CREATE SCHEMA IF NOT EXISTS cotacao;
CREATE SCHEMA IF NOT EXISTS fornecedor;

-- Tabela central de tenants
CREATE TABLE public.tenant (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  status VARCHAR(20) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT NOW()
);

-- Tabela de usuários com tenant_id
CREATE TABLE public.user_account (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenant(id),
  email VARCHAR(255) NOT NULL,
  name VARCHAR(255),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(tenant_id, email)
);

-- Tabela de edital com RLS
CREATE TABLE edital.edital (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenant(id),
  numero_edital VARCHAR(50) NOT NULL,
  titulo VARCHAR(500),
  descricao TEXT,
  data_publicacao TIMESTAMP,
  data_encerramento TIMESTAMP,
  valor_estimado DECIMAL(15, 2),
  modalidade VARCHAR(50),
  orgao VARCHAR(255),
  status VARCHAR(20) DEFAULT 'rascunho',
  created_by UUID REFERENCES public.user_account(id),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  CONSTRAINT unique_edital_per_tenant UNIQUE(tenant_id, numero_edital)
);

-- Habilitar RLS
ALTER TABLE edital.edital ENABLE ROW LEVEL SECURITY;

-- RLS Policy: usuários só veem dados de seu tenant
CREATE POLICY rls_edital_tenant ON edital.edital
  FOR ALL
  USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- RLS Policy para SELECT
CREATE POLICY rls_edital_select ON edital.edital
  FOR SELECT
  USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- RLS Policy para INSERT (validar tenant_id)
CREATE POLICY rls_edital_insert ON edital.edital
  FOR INSERT
  WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);

-- Audit log (imutável)
CREATE TABLE public.audit_log (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES public.tenant(id),
  user_id UUID NOT NULL REFERENCES public.user_account(id),
  action VARCHAR(50),           -- INSERT, UPDATE, DELETE, APPROVE
  entity_type VARCHAR(100),     -- edital, cotacao, fornecedor
  entity_id UUID,
  changes JSONB,                 -- {before: {...}, after: {...}}
  created_at TIMESTAMP DEFAULT NOW()
);

-- Index para queries de auditoria
CREATE INDEX idx_audit_tenant_time ON public.audit_log(tenant_id, created_at DESC);
```

---

## Configuração Helm (PostgreSQL Gerenciado)

```yaml
# charts/postgres/values.yaml
postgresql:
  enabled: true
  image:
    tag: "15.5"  # Latest stable
  
  primary:
    persistence:
      size: 100Gi
      storageClassName: "fast-ssd"
  
  # Replicação
  readReplicas:
    enabled: true
    replicaCount: 2
    persistence:
      size: 100Gi
  
  # Configurações de segurança
  securityContext:
    enabled: true
    fsGroup: 1001
  
  # Backups
  backup:
    enabled: true
    # pgBackRest ou WAL-G
    schedule: "0 2 * * *"  # daily at 2am
    retention: "30d"
  
  # Monitoramento
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      interval: 30s
```

---

## Implementação RLS em Código

### Java (Hibernate + Spring Data)

```java
@Entity
@Table(name = "edital", schema = "edital")
public class EditalEntity {
  @Id
  private UUID id;
  
  @Column(name = "tenant_id", nullable = false)
  private UUID tenantId;
  
  @Column(name = "numero_edital", nullable = false, length = 50)
  private String numeroEdital;
  
  @Column(name = "titulo", length = 500)
  private String titulo;
  
  // ... outros campos
  
  @CreationTimestamp
  @Column(name = "created_at")
  private LocalDateTime createdAt;
}

@Repository
public interface EditalRepository extends JpaRepository<EditalEntity, UUID> {
  List<EditalEntity> findByTenantIdOrderByCreatedAtDesc(UUID tenantId);
  
  @Query(value = "SELECT * FROM edital.edital WHERE tenant_id = :tenantId", 
         nativeQuery = true)
  List<EditalEntity> findAllForTenant(@Param("tenantId") UUID tenantId);
}

@Service
public class EditalService {
  @Autowired
  private EditalRepository repository;
  
  @Autowired
  private JdbcTemplate jdbc;
  
  public List<EditalEntity> listarPorTenant(UUID tenantId) {
    // Set RLS policy
    jdbc.execute("SET app.tenant_id = '" + tenantId + "'");
    
    // Query usa RLS automaticamente
    return repository.findAll();
  }
  
  public void criarEdital(EditalCreateRequest req, UUID tenantId) {
    jdbc.execute("SET app.tenant_id = '" + tenantId + "'");
    
    EditalEntity edital = EditalEntity.builder()
      .id(UUID.randomUUID())
      .tenantId(tenantId)
      .numeroEdital(req.numeroEdital)
      .titulo(req.titulo)
      .build();
    
    repository.save(edital);
    
    // Log auditoria
    logAuditoria(tenantId, "EDITAL_CRIADO", edital.id, edital);
  }
  
  private void logAuditoria(UUID tenantId, String action, UUID entityId, Object entity) {
    jdbc.update(
      "INSERT INTO public.audit_log (tenant_id, user_id, action, entity_type, entity_id, changes) " +
      "VALUES (?, ?, ?, ?, ?, ?)",
      tenantId, getCurrentUserId(), action, "EDITAL", entityId, 
      convertToJson(entity)
    );
  }
}
```

### Go (sqlc + pgx)

```go
package db

import (
  "context"
  "github.com/jackc/pgx/v5"
)

type EditalRow struct {
  ID               string
  TenantID         string
  NumeroEdital     string
  Titulo           string
  DataPublicacao   time.Time
  DataEncerramento time.Time
  ValorEstimado    float64
  Status           string
  CreatedAt        time.Time
}

func (q *Queries) ListEditaisPorTenant(ctx context.Context, tenantID string) ([]EditalRow, error) {
  // Set RLS policy
  if _, err := q.db.Exec(ctx, "SET app.tenant_id = $1", tenantID); err != nil {
    return nil, err
  }
  
  // Query applies RLS automatically
  rows, err := q.db.Query(ctx, `
    SELECT id, tenant_id, numero_edital, titulo, data_publicacao, 
           data_encerramento, valor_estimado, status, created_at
    FROM edital.edital
    ORDER BY created_at DESC
  `)
  if err != nil {
    return nil, err
  }
  defer rows.Close()
  
  var editais []EditalRow
  for rows.Next() {
    var row EditalRow
    err := rows.Scan(
      &row.ID, &row.TenantID, &row.NumeroEdital, &row.Titulo,
      &row.DataPublicacao, &row.DataEncerramento, &row.ValorEstimado,
      &row.Status, &row.CreatedAt,
    )
    if err != nil {
      return nil, err
    }
    editais = append(editais, row)
  }
  
  return editais, rows.Err()
}

func (q *Queries) CreateEdital(ctx context.Context, arg CreateEditalParams) (string, error) {
  // Set RLS policy
  if _, err := q.db.Exec(ctx, "SET app.tenant_id = $1", arg.TenantID); err != nil {
    return "", err
  }
  
  var id string
  err := q.db.QueryRow(ctx, `
    INSERT INTO edital.edital (
      id, tenant_id, numero_edital, titulo, data_publicacao,
      data_encerramento, valor_estimado, modalidade, orgao, status, created_by, created_at
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW())
    RETURNING id
  `,
    arg.ID, arg.TenantID, arg.NumeroEdital, arg.Titulo, arg.DataPublicacao,
    arg.DataEncerramento, arg.ValorEstimado, arg.Modalidade, arg.Orgao,
    arg.Status, arg.CreatedBy,
  ).Scan(&id)
  
  if err != nil {
    return "", err
  }
  
  // Log auditoria
  logAuditoria(ctx, q.db, arg.TenantID, "EDITAL_CRIADO", id, arg)
  
  return id, nil
}
```

---

## Estratégia de Backup e Disaster Recovery

```yaml
# Backup policy
backups:
  type: "pgBackRest"  # ou WAL-G
  frequency: "daily"
  retention: "30 days"
  location: "s3://cotai-backups"
  
point_in_time_recovery: "7 days"
```

### Teste de Restore (mensal)

1. Criar clone da production.
2. Restaurar backup de 30 dias atrás.
3. Validar integridade de dados.
4. Destruir clone.

---

## Monitoramento e Alertas

```yaml
# Prometheus rules
- alert: PostgreSQLHighConnections
  expr: pg_stat_activity_count > 80
  for: 5m
  
- alert: PostgreSQLDiskSpace
  expr: node_filesystem_avail_bytes{mountpoint="/var/lib/postgresql"} / node_filesystem_size_bytes < 0.15
  for: 5m
  
- alert: PostgreSQLReplicationLag
  expr: pg_replication_lag > 10000  # 10 segundos
  for: 2m
```

---

## Referências

- [PostgreSQL 15 Documentation](https://www.postgresql.org/docs/15/)
- [Row-Level Security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- [pgBackRest](https://pgbackrest.org/)
- [PostgreSQL HA Best Practices](https://www.postgresql.org/docs/current/warm-standby.html)

---

**Próximo**: ADR-003 (OpenTelemetry para Observabilidade)
