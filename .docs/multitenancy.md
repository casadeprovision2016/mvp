# Modelo Multi-Tenant do Cotai

**Versão**: 1.0  
**Data**: Dezembro 2025

---

## 1. Visão Geral

Cotai é uma **plataforma SaaS multi-tenant** onde múltiplos clientes (empresas/órgãos) compartilham a mesma infraestrutura com **isolamento completo de dados**.

### Princípios

1. **Isolamento de dados**: Tenant A nunca vê dados de Tenant B.
2. **Compliance**: Auditoria imutável, conformidade com LGPD/GDPR.
3. **Escalabilidade**: Dimensionar recursos independente de número de tenants.
4. **Configurabilidade**: Cada tenant pode customizar workflows, templates, permissões.

---

## 2. Estratégias de Isolamento

### 2.1 Comparativo

| Estratégia | Isolamento | Custo Infra | Complexidade | Auditoria | Backup | Recomendação |
|-----------|-----------|-----------|-------------|-----------|--------|-------------|
| **RLS (Row-Level Security)** | Forte | Baixo | Médio | Fácil | Simples | ✅ MVP |
| **Schema-per-Tenant** | Muito Forte | Médio | Alto | Fácil | Granular | Q2 2026 |
| **DB-per-Tenant** | Isolamento completo | Alto | Muito Alto | Fácil | Complexo | Enterprise |

### 2.2 RLS (Row-Level Security) — MVP

**Padrão**: Um único PostgreSQL, múltiplos schemas com RLS policies.

#### Arquitetura de Dados

```sql
-- Tabela central de tenants (compartilhada)
CREATE TABLE public.tenant (
  id UUID PRIMARY KEY,
  name VARCHAR(255),
  plan VARCHAR(50),        -- starter, professional, enterprise
  storage_limit BIGINT,    -- bytes
  features JSONB,          -- features habilitadas por plano
  status VARCHAR(20),      -- active, suspended, deleted
  created_at TIMESTAMP,
  UNIQUE(name)
);

-- Todas as tabelas do domínio incluem tenant_id
CREATE TABLE edital.edital (
  id UUID PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES public.tenant(id),
  ...campos de domínio...,
  CONSTRAINT unique_numero_per_tenant UNIQUE(tenant_id, numero_edital)
);

-- RLS Policy: usuário só vê dados de seu tenant
ALTER TABLE edital.edital ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_edital_tenant ON edital.edital
  FOR ALL
  USING (tenant_id = current_setting('app.tenant_id')::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
```

#### Fluxo de Requisição

```
1. API Gateway recebe request com JWT
   Authorization: Bearer <JWT>
   {sub: user_id, tenant_id: "abc123"}

2. API Gateway extrai tenant_id → header X-Tenant-ID

3. Serviço (ex: cotacao-service):
   a) Lê header X-Tenant-ID
   b) Inicia transação: SET app.tenant_id = 'abc123'
   c) Query automaticamente filtra por tenant_id via RLS
   
4. Resposta retorna apenas dados de tenant abc123
```

#### Implementação: Middleware de Tenant

**Java (Spring)**:

```java
@Component
public class TenantContextFilter implements Filter {
  
  @Override
  public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
      throws IOException, ServletException {
    String tenantId = extractTenantId((HttpServletRequest) request);
    
    if (tenantId == null) {
      ((HttpServletResponse) response).sendError(HttpServletResponse.SC_UNAUTHORIZED, 
        "X-Tenant-ID header required");
      return;
    }
    
    TenantContext.setTenant(tenantId);
    
    try {
      chain.doFilter(request, response);
    } finally {
      TenantContext.clear();
    }
  }
  
  private String extractTenantId(HttpServletRequest request) {
    // Opção 1: Header (recomendado)
    String tenantId = request.getHeader("X-Tenant-ID");
    
    if (tenantId == null) {
      // Opção 2: JWT claim (fallback)
      String authHeader = request.getHeader("Authorization");
      if (authHeader != null && authHeader.startsWith("Bearer ")) {
        String jwt = authHeader.substring(7);
        tenantId = extractTenantIdFromJwt(jwt);
      }
    }
    
    return tenantId;
  }
  
  private String extractTenantIdFromJwt(String jwt) {
    JwtConsumer jwtConsumer = new JwtConsumerBuilder()
      .setSkipSignatureVerification() // Validado antes
      .build();
    
    JwtClaims claims = jwtConsumer.processToClaims(jwt);
    return (String) claims.getClaimValue("tenant_id");
  }
}

public class TenantContext {
  private static final ThreadLocal<String> TENANT = new ThreadLocal<>();
  
  public static void setTenant(String tenantId) {
    TENANT.set(tenantId);
  }
  
  public static String getTenant() {
    return TENANT.get();
  }
  
  public static void clear() {
    TENANT.remove();
  }
}

@Component
public class DatabaseConfiguration {
  
  @Bean
  public DataSource dataSource() throws Exception {
    return new DataSourceProxy(primaryDataSource()) {
      @Override
      public Connection getConnection() throws SQLException {
        Connection conn = super.getConnection();
        String tenantId = TenantContext.getTenant();
        
        if (tenantId != null) {
          try (Statement stmt = conn.createStatement()) {
            stmt.execute("SET app.tenant_id = '" + tenantId + "'");
          }
        }
        
        return conn;
      }
    };
  }
}
```

**Go**:

```go
package middleware

import (
  "context"
  "net/http"
  "strings"
)

const TenantIDContextKey = "tenant_id"

func TenantMiddleware(next http.Handler) http.Handler {
  return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
    tenantID := extractTenantID(r)
    
    if tenantID == "" {
      http.Error(w, "X-Tenant-ID header required", http.StatusUnauthorized)
      return
    }
    
    ctx := context.WithValue(r.Context(), TenantIDContextKey, tenantID)
    next.ServeHTTP(w, r.WithContext(ctx))
  })
}

func extractTenantID(r *http.Request) string {
  // Opção 1: Header
  tenantID := r.Header.Get("X-Tenant-ID")
  if tenantID != "" {
    return tenantID
  }
  
  // Opção 2: JWT claim
  authHeader := r.Header.Get("Authorization")
  if authHeader != "" {
    token := strings.TrimPrefix(authHeader, "Bearer ")
    if tenantID := extractFromJWT(token); tenantID != "" {
      return tenantID
    }
  }
  
  return ""
}

// Usar em repository
func (r *CotacaoRepository) FindByTenant(ctx context.Context) ([]Cotacao, error) {
  tenantID := ctx.Value(TenantIDContextKey).(string)
  
  // Set RLS policy
  _, err := r.db.ExecContext(ctx, "SET app.tenant_id = $1", tenantID)
  if err != nil {
    return nil, err
  }
  
  // Query aplicará RLS automaticamente
  rows, err := r.db.QueryContext(ctx, `
    SELECT id, tenant_id, descricao, status, created_at
    FROM cotacao.cotacao
    ORDER BY created_at DESC
  `)
  // ... scanear resultados
}
```

---

### 2.3 Schema-per-Tenant — Escalabilidade Futura

Quando um tenant crescer muito (> 500GB de dados), migrar para schema dedicado:

```sql
-- Tenant premium em schema próprio
CREATE SCHEMA cotai_tenant_xyz;

CREATE TABLE cotai_tenant_xyz.edital (
  id UUID PRIMARY KEY,
  -- Sem tenant_id, é implícito no schema
  numero_edital VARCHAR(50),
  ...
);

-- Ou até DB separado
CREATE DATABASE cotai_tenant_xyz;
```

**Vantagens**:
- Isolamento físico (sem RLS overhead).
- Backup granular por tenant.
- Escalabilidade independente.

**Desvantagens**:
- Muitos objetos de schema.
- Gerenciamento operacional complexo.

---

### 2.4 DB-per-Tenant — Enterprise

Para clientes com compliance muito rígido (ex: governo federal):

```
postgres-prod-tenant-xyz
  └── cotai_db (schemas: edital, cotacao, fornecedor, ...)

postgres-prod-tenant-abc
  └── cotai_db (schemas: edital, cotacao, fornecedor, ...)
```

**Vantagens**:
- Isolamento total (compliance forte).
- Backup/restore independente por tenant.

**Desvantagens**:
- Custo de infra alto.
- Gerenciamento operacional massivo.

---

## 3. Propagação de Tenant (JWT + X-Tenant-ID)

### 3.1 Fluxo de Token

1. **Login (OAuth2/OIDC)**:
   ```
   POST /auth/login
   {email: user@company.com, password: ...}
   
   ↓
   
   auth-service valida credenciais e tenant
   
   ↓
   
   JWT gerado:
   {
     "sub": "user-123",
     "tenant_id": "tenant-abc",
     "tenant_name": "ACME Corp",
     "roles": ["gestor-liciacoes"],
     "iat": 1702478400,
     "exp": 1702564800
   }
   ```

2. **Cada Requisição Autenticada**:
   ```
   GET /api/cotacao
   Authorization: Bearer <JWT>
   X-Tenant-ID: tenant-abc  (opcional, extraído do JWT se não presente)
   
   ↓
   
   API Gateway:
   - Valida JWT (signature)
   - Extrai tenant_id do claim
   - Injeta header X-Tenant-ID
   
   ↓
   
   Serviço processa com contexto de tenant
   ```

3. **Comunicação S2S (gRPC)**:
   ```
   cotacao-service → fornecedor-service
   
   Metadata:
   x-tenant-id: tenant-abc
   x-trace-id: <trace_id>
   authorization: <service-to-service JWT>
   
   ↓
   
   fornecedor-service injeta tenant context
   ```

### 3.2 Validação de Tenant

```java
@Component
public class TenantValidator {
  
  @Autowired
  private TenantRepository tenantRepository;
  
  public void validateTenant(String tenantId) throws TenantInvalidException {
    Tenant tenant = tenantRepository.findById(UUID.fromString(tenantId))
      .orElseThrow(() -> new TenantInvalidException("Tenant não encontrado: " + tenantId));
    
    if (tenant.getStatus() != TenantStatus.ACTIVE) {
      throw new TenantInvalidException("Tenant inativo ou deletado");
    }
  }
}

@Component
public class TenantAuthenticationFilter implements Filter {
  
  @Override
  public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
      throws IOException, ServletException {
    HttpServletRequest request = (HttpServletRequest) req;
    String tenantId = request.getHeader("X-Tenant-ID");
    
    try {
      tenantValidator.validateTenant(tenantId);
      chain.doFilter(req, res);
    } catch (TenantInvalidException e) {
      ((HttpServletResponse) res).sendError(
        HttpServletResponse.SC_FORBIDDEN, 
        e.getMessage()
      );
    }
  }
}
```

---

## 4. Isolamento de Dados em Detalhes

### 4.1 Regras RLS Completas

```sql
-- Tabela edital
CREATE TABLE edital.edital (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenant(id),
  numero_edital VARCHAR(50) NOT NULL,
  data_publicacao TIMESTAMP,
  -- ... outras colunas
  CONSTRAINT unique_edital_per_tenant UNIQUE(tenant_id, numero_edital)
);

-- Habilitar RLS
ALTER TABLE edital.edital ENABLE ROW LEVEL SECURITY;

-- Policy 1: SELECT (leitura)
CREATE POLICY edital_select_policy ON edital.edital
  FOR SELECT
  USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Policy 2: INSERT (criação)
CREATE POLICY edital_insert_policy ON edital.edital
  FOR INSERT
  WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);

-- Policy 3: UPDATE (atualização)
CREATE POLICY edital_update_policy ON edital.edital
  FOR UPDATE
  USING (tenant_id = current_setting('app.tenant_id')::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);

-- Policy 4: DELETE
CREATE POLICY edital_delete_policy ON edital.edital
  FOR DELETE
  USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Aplicar a mesma estrutura a todas as tabelas do domínio
ALTER TABLE edital.item_edital ENABLE ROW LEVEL SECURITY;
CREATE POLICY item_edital_rls ON edital.item_edital
  FOR ALL
  USING (EXISTS (
    SELECT 1 FROM edital.edital
    WHERE edital.id = item_edital.edital_id
      AND edital.tenant_id = current_setting('app.tenant_id')::uuid
  ));
```

### 4.2 Testes de Isolamento

```java
@SpringBootTest
public class TenantIsolationTest {
  
  @Autowired
  private EditalRepository editalRepository;
  
  @Autowired
  private JdbcTemplate jdbc;
  
  @Test
  public void testTenant A_CannotSeeTenant B_Data() {
    UUID tenantA = UUID.randomUUID();
    UUID tenantB = UUID.randomUUID();
    
    // Criar edital para tenant A
    jdbc.execute("SET app.tenant_id = '" + tenantA + "'");
    Edital editalA = new Edital(tenantA, "EDI-001-A");
    editalRepository.save(editalA);
    
    // Tenant A vê seu edital
    List<Edital> editaisByA = editalRepository.findAll();
    assertThat(editaisByA).hasSize(1);
    assertThat(editaisByA.get(0).getTenantId()).isEqualTo(tenantA);
    
    // Trocar para tenant B
    jdbc.execute("SET app.tenant_id = '" + tenantB + "'");
    
    // Tenant B NÃO vê edital de tenant A (RLS bloqueia)
    List<Edital> editaisByB = editalRepository.findAll();
    assertThat(editaisByB).isEmpty();
  }
}
```

---

## 5. Configurações por Tenant

### 5.1 Tabela de Configurações

```sql
CREATE TABLE public.tenant_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL UNIQUE REFERENCES public.tenant(id),
  
  -- Workflow de aprovação
  approval_workflow JSONB,  -- {cotacao: {10000: "supervisor", 50000: "director"}}
  
  -- Templates de documento
  templates JSONB,  -- {proposta: "template-id", nda: "template-id"}
  
  -- Configuração de notificações
  notification_settings JSONB,  -- {email_enabled: true, slack_enabled: false}
  
  -- Parâmetros legais/fiscais
  fiscal_config JSONB,  -- {tax_regime: "lucro_presumido", icms_rate: 0.18}
  
  -- Idioma e branding
  language VARCHAR(10) DEFAULT 'pt-BR',
  timezone VARCHAR(50) DEFAULT 'America/Sao_Paulo',
  logo_url TEXT,
  color_primary VARCHAR(7) DEFAULT '#007bff',
  
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- RLS
ALTER TABLE public.tenant_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_config_rls ON public.tenant_config
  FOR ALL
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

### 5.2 Acesso a Configurações

```java
@Service
public class TenantConfigService {
  
  @Autowired
  private TenantConfigRepository repository;
  
  @Cacheable(value = "tenant_config", key = "#tenantId")
  public TenantConfig getConfig(String tenantId) {
    return repository.findByTenantId(UUID.fromString(tenantId))
      .orElse(getTenantConfigDefault());
  }
  
  public ApprovalWorkflow getApprovalWorkflow(String tenantId) {
    TenantConfig config = getConfig(tenantId);
    return parseApprovalWorkflow(config.getApprovalWorkflow());
  }
  
  public List<String> getEnabledFeatures(String tenantId) {
    // Verificar plan do tenant + features habilitadas
    Tenant tenant = tenantRepository.findById(UUID.fromString(tenantId)).get();
    List<String> featuresByPlan = getFeaturesByPlan(tenant.getPlan());
    
    // Adicionar custom features do tenant
    TenantConfig config = getConfig(tenantId);
    List<String> allFeatures = new ArrayList<>(featuresByPlan);
    allFeatures.addAll(config.getEnabledFeatures());
    
    return allFeatures;
  }
}
```

---

## 6. Audit Trail Imutável

### 6.1 Tabela de Auditoria

```sql
CREATE TABLE public.audit_log (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES public.tenant(id),
  user_id UUID NOT NULL REFERENCES public.user_account(id),
  
  action VARCHAR(50),               -- INSERT, UPDATE, DELETE, APPROVE, REJECT
  entity_type VARCHAR(100),         -- EDITAL, COTACAO, FORNECEDOR
  entity_id UUID,
  
  -- Snapshot antes e depois (para UPDATE)
  old_values JSONB,
  new_values JSONB,
  
  -- Contexto da ação
  ip_address INET,
  user_agent TEXT,
  endpoint VARCHAR(255),
  request_id UUID,
  
  created_at TIMESTAMP DEFAULT NOW()
);

-- Index para queries rápidas
CREATE INDEX idx_audit_tenant_time ON public.audit_log(tenant_id, created_at DESC);
CREATE INDEX idx_audit_entity ON public.audit_log(entity_type, entity_id);
CREATE INDEX idx_audit_user ON public.audit_log(user_id, created_at DESC);

-- Política de retenção: 2 anos
-- (background job delete records older than 2 years weekly)
```

### 6.2 Log Automático (Trigger ou AOP)

**Opção 1: Trigger PostgreSQL**:

```sql
CREATE FUNCTION audit_trigger_func() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.audit_log (
    tenant_id, user_id, action, entity_type, entity_id,
    old_values, new_values, endpoint, request_id, ip_address
  ) VALUES (
    current_setting('app.tenant_id')::uuid,
    current_setting('app.user_id')::uuid,
    TG_OP,
    TG_TABLE_NAME,
    NEW.id,
    row_to_json(OLD),
    row_to_json(NEW),
    current_setting('app.endpoint', true),
    current_setting('app.request_id', true)::uuid,
    inet_client_addr()
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER edital_audit_trigger AFTER INSERT OR UPDATE OR DELETE ON edital.edital
FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();
```

**Opção 2: AOP Spring**:

```java
@Aspect
@Component
public class AuditLogAspect {
  
  @Autowired
  private AuditLogRepository auditRepository;
  
  @AfterReturning("@annotation(Auditable)")
  public void logAuditableOperation(JoinPoint jp) {
    String methodName = jp.getSignature().getName();
    Object[] args = jp.getArgs();
    
    String tenantId = TenantContext.getTenant();
    String userId = SecurityContextHolder.getContext().getAuthentication().getName();
    
    AuditLog log = AuditLog.builder()
      .tenantId(UUID.fromString(tenantId))
      .userId(UUID.fromString(userId))
      .action(methodName)
      .entityType(jp.getTarget().getClass().getSimpleName())
      .newValues(JsonUtils.toJson(args))
      .ipAddress(RequestUtils.getClientIp())
      .endpoint(RequestUtils.getRequestUri())
      .build();
    
    auditRepository.save(log);
  }
}

@Auditable
@PostMapping("/cotacao")
public ResponseEntity<CotacaoDTO> criarCotacao(@RequestBody CotacaoRequest request) {
  // ...
}
```

---

## 7. Checklist de Implementação MVP

- [ ] Implementar RLS policies em todas as tabelas do domínio.
- [ ] Criar middleware TenantContext (Spring Filter, Go middleware).
- [ ] Validar tenant_id em cada request (header X-Tenant-ID ou JWT claim).
- [ ] Configurar OTEL com atributo tenant_id em spans/métricas/logs.
- [ ] Criar testes de isolamento (tenant A ≠ tenant B).
- [ ] Implementar audit_log table + triggers/AOP.
- [ ] Documentar workflow de tenant onboarding (criar tenant_config defaults).
- [ ] Treinar time em troubleshooting de tenant issues.

---

## 8. Roadmap Future (Q2+ 2026)

- Schema-per-Tenant para enterprise.
- Multi-region com replicação de tenant-specific data.
- Data residency por país (LGPD, GDPR).
- Backup/restore granular por tenant.
- Self-service tenant provisioning (signup + auto-setup).

---

**Próxima**: ADR-004 (gRPC + Protobuf para S2S)
