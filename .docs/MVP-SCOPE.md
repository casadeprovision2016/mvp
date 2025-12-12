# MVP Scope: Cotai Multi-Tenant Procurement Platform

**Project**: Cotai  
**Status**: In Development (Phase 0/1)  
**Version**: 1.0  
**Last Updated**: December 2025

---

## Executive Summary

Cotai MVP is a **SaaS platform for multi-tenant procurement and bidding management**. The initial release focuses on core procurement workflows: tender creation, quotation collection, vendor evaluation, and decision support.

**Success Criteria**: Launch with 2-3 pilot customers, achieve 99.5% uptime, sub-500ms API latency (P95), process 100+ tenders/month per tenant.

---

## Core Features (MVP)

### 1. **Tender Management** (`edital-service`)

Users can create, publish, and manage tenders (RFQ/RFP).

#### Features

- ✅ Create tender with rich text description
- ✅ Define tender items (products/services with specifications)
- ✅ Set bidding periods (opening, closing dates, phases)
- ✅ Assign evaluators and permissions
- ✅ Publish tender (notify vendors via email)
- ✅ View tender timeline and activity log
- ✅ Support for multiple tender types (price-only, scored, negotiation)
- ✅ Document attachments (PDF specs, terms & conditions)

#### Acceptance Criteria

```gherkin
Scenario: User creates and publishes tender
  Given user is authenticated and in "procurer" role
  When user creates tender with title, description, and 5 items
  And user sets bidding period (14 days from now)
  And user publishes tender
  Then tender status becomes "Publicado"
  And invited vendors receive email notification
  And audit log records creation + publication
```

#### Out of Scope (MVP)

- ❌ Tender templates
- ❌ Multi-phase bidding (Q&A, clarifications)
- ❌ Electronic signatures on tenders
- ❌ Procurement plans or forecasting

---

### 2. **Quotation Management** (`cotacao-service`)

Vendors submit quotation responses; procurers collect and manage them.

#### Features

- ✅ Vendors view assigned tenders
- ✅ Vendors submit quotations (price, terms, attached files)
- ✅ Procurers view all vendor responses in dashboard
- ✅ Compare quotations side-by-side
- ✅ Download quotations as PDF/Excel
- ✅ Scoring/ranking by price (and optionally other criteria)
- ✅ Notes and annotations on individual quotations
- ✅ Approval workflow (procurer → manager → director)
- ✅ Status tracking (submitted, under review, rejected, approved)

#### Acceptance Criteria

```gherkin
Scenario: Vendor submits quotation
  Given tender is in bidding period
  And vendor is invited
  When vendor submits quotation with prices for each item
  And attaches supporting documents
  Then quotation status becomes "Enviado"
  And procurer is notified via dashboard
  And quotation appears in tender's response list

Scenario: Procurer scores quotations
  Given multiple vendors have submitted quotations
  When procurer views "Comparar Ofertas"
  Then all quotations displayed side-by-side
  And ranking shown by lowest price
  And procurer can manually adjust scores
```

#### Out of Scope (MVP)

- ❌ Real-time auction/dynamic pricing
- ❌ Vendor questions/clarification requests
- ❌ Automated scoring rules (except simple price ranking)
- ❌ Contract generation from quotation

---

### 3. **Vendor Management** (`fornecedor-service`)

Maintain vendor profiles, registrations, and evaluation history.

#### Features

- ✅ Vendor self-registration (name, CNPJ, contact, category)
- ✅ Vendor profile: company info, certifications, contact persons
- ✅ Vendor categorization (product categories they supply)
- ✅ Vendor invitation to tenders (import from list or CSV)
- ✅ View past quotations and tender history
- ✅ Simple vendor rating/feedback (star rating after completion)
- ✅ Vendor contact management (multiple contacts per vendor)

#### Acceptance Criteria

```gherkin
Scenario: Vendor registers
  Given user visits vendor registration page
  When user fills CNPJ, company name, email
  And user sets up login credentials
  Then account created and activation email sent
  And vendor can log in and view accessible tenders

Scenario: Procurer invites vendors to tender
  Given procurer has created a tender
  When procurer selects "Convidar Fornecedores"
  And procurer uploads CSV with vendor CNPJs or searches by name
  Then selected vendors receive email invitation
  And tender appears in their dashboard
```

#### Out of Scope (MVP)

- ❌ Vendor risk scoring / compliance checks
- ❌ Vendor performance analytics / dashboards
- ❌ EDI / automated data feeds from vendor systems
- ❌ Vendor portal (vendors access via main app)

---

### 4. **Authentication & Authorization** (`auth-service`)

Multi-tenant identity and access control.

#### Features

- ✅ User registration (email/password + email verification)
- ✅ Login with OAuth2/OIDC (optional: Google, Azure AD)
- ✅ JWT token generation with tenant_id + roles
- ✅ Role-based access control (RBAC):
  - `Administrador` — Full tenant access + user management
  - `Gestor Procurement` — Tender/quotation management
  - `Avaliador` — View and score quotations
  - `Fornecedor` — Submit quotations to assigned tenders
- ✅ Multi-tenant isolation via X-Tenant-ID header + JWT claim
- ✅ Password reset flow
- ✅ User invitation (admin invites users to tenant)
- ✅ Audit log of login attempts and role changes

#### Acceptance Criteria

```gherkin
Scenario: User logs in and accesses tenant data
  Given user account in "tenant_a"
  When user logs in with email + password
  Then JWT issued with tenant_id = "tenant_a"
  And user can only see "tenant_a" data
  And audit log records login timestamp + IP

Scenario: Admin invites new user
  Given user is admin of tenant
  When admin sends invitation to new.user@company.com with role "Avaliador"
  Then invitation email sent
  And new user can register and join tenant
```

#### Out of Scope (MVP)

- ❌ Multi-factor authentication (MFA)
- ❌ SSO federation (SAML, OAuth for multiple IdPs)
- ❌ Passwordless login (biometric, FIDO2)
- ❌ Custom permission models (future: ABAC)

---

### 5. **Notifications** (`notificacao-service`)

Transactional notifications (email, SMS).

#### Features

- ✅ Email notifications:
  - Tender published → vendors
  - Quotation deadline reminder → vendors (24h before)
  - Quotation received → procurers
  - Tender decision → vendors (won/lost)
  - User invitation → email with registration link
  - Password reset → email with reset link
- ✅ SMS notifications (optional first release):
  - Tender published → mobile-enabled vendors
  - Quotation deadline reminder (optional)
- ✅ In-app notifications (toast/banner)
- ✅ Notification history & audit trail

#### Acceptance Criteria

```gherkin
Scenario: Tender published email notification
  Given tender published at 2025-01-10 10:00 AM
  And 50 vendors invited
  When notification job triggers
  Then each vendor receives email within 5 minutes
  And email includes tender title, deadline, link to respond
  And notification logged in audit trail
```

#### Out of Scope (MVP)

- ❌ SMS (can add later)
- ❌ Slack / Teams integration
- ❌ Notification templates (hard-coded initially)
- ❌ Notification preferences / unsubscribe

---

### 6. **Dashboard & Analytics** (Frontend)

Web interface for procurers and vendors.

#### Features (Procurers)

- ✅ Dashboard home: active tenders, pending quotations, upcoming deadlines
- ✅ Tender list: search, filter (status, date, category)
- ✅ Tender detail: items, timeline, quotation status, actions
- ✅ Quotation comparison: side-by-side view, scoring, ranking
- ✅ Vendor list: search, invite, contact management
- ✅ Reports: tenders created, quotations received, decision timeline

#### Features (Vendors)

- ✅ Dashboard home: assigned tenders, submission status, upcoming deadlines
- ✅ Tender list: search, filter (open, closed, won, lost)
- ✅ Tender detail: requirements, items, bidding timeline
- ✅ Submit quotation: add prices, upload documents, submit
- ✅ View past quotations and feedback
- ✅ Company profile: edit contact info, certifications

#### Acceptance Criteria

```gherkin
Scenario: Procurer views quotation comparison
  Given 3 vendors submitted quotations to tender
  When procurer opens "Comparar Ofertas"
  Then table shows all items and each vendor's price
  And total price calculated per vendor
  And ranking sorted by price
  And procurer can download as Excel
```

#### Out of Scope (MVP)

- ❌ Advanced analytics / dashboards
- ❌ Data export (beyond PDF/Excel)
- ❌ Custom branding / white-labeling

---

## Non-Functional Requirements

### Performance

| Metric | Target |
|--------|--------|
| API P95 Latency | < 500ms |
| API P99 Latency | < 1000ms |
| Page Load Time | < 2s |
| Error Rate | < 0.1% |
| Availability | 99.5% monthly |

### Scalability

- Support **100+ tenders/month** per tenant
- Support **1000+ vendors** per tenant
- Support **100k+ concurrent users** (across all tenants)
- Scale from 2 pilots to 50+ customers in 12 months

### Security

- ✅ OAuth2/OIDC authentication
- ✅ Row-Level Security (RLS) for multi-tenant isolation
- ✅ Encryption in transit (TLS 1.3)
- ✅ RBAC enforcement at API layer
- ✅ Audit logging of all sensitive operations
- ✅ No hardcoded credentials; Vault integration for production
- ✅ Password reset security (time-limited tokens)
- ✅ CORS / CSRF protection

### Compliance

- ✅ LGPD (Lei Geral de Proteção de Dados) compliance:
  - User consent tracking
  - Data retention policies
  - Right to erasure support
- ✅ Audit trail (immutable logs of all user actions)
- ✅ Data residency (Brazil-based)

### Observability

- ✅ Distributed tracing (Jaeger)
- ✅ Prometheus metrics (request latency, error rate, business metrics)
- ✅ Structured JSON logs (Loki aggregation)
- ✅ Dashboards in Grafana
- ✅ Alerting on SLO violations

---

## MVP Phases (Delivery Timeline)

### Phase 0: Foundation (Now → End of January 2025)

- ✅ Architecture & design decisions documented
- ✅ Local development environment setup
- ✅ Core services scaffolded (proto definitions, Helm charts)
- ✅ CI/CD pipeline operational (GitHub Actions, Trivy, Helm lint)
- ✅ Observability stack deployed (Jaeger, Prometheus, Loki, Grafana)

**Deliverables**: Documentation, tooling, empty service structure

### Phase 1: Core Services (February 2025)

- ✅ `auth-service`: User registration, login, JWT, RBAC
- ✅ `edital-service`: Tender creation, publication
- ✅ `cotacao-service`: Quotation submission, basic comparison
- ✅ `fornecedor-service`: Vendor registration, invitation
- ✅ `notificacao-service`: Email notifications (tender published, quotation received)
- ✅ Basic web frontend (procurer & vendor dashboards)

**Deliverables**: Working services, database schemas, API contracts

### Phase 2: Integration & Hardening (March 2025)

- ✅ Service-to-service communication (gRPC, Kafka)
- ✅ Integration tests across services
- ✅ Performance testing & optimization
- ✅ Security hardening (mTLS, secret rotation, RBAC enforcement)
- ✅ Documentation (runbooks, troubleshooting, SLOs)

**Deliverables**: Integrated system, hardened security, monitoring

### Phase 3: Pilot Deployment (April 2025)

- ✅ Deployment to GCP (staging → production)
- ✅ Pilot customers onboarded (2-3 organizations)
- ✅ Monitoring & alerting active
- ✅ On-call rotation established
- ✅ Runbooks & SLA definitions active

**Deliverables**: Production system, pilot customers, ops procedures

---

## Success Metrics (MVP)

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Uptime** | 99.5% | Prometheus uptime metric |
| **API Latency** | P95 < 500ms | Jaeger traces, Prometheus histograms |
| **Error Rate** | < 0.1% | Error logs, metrics |
| **Pilot Adoption** | 2-3 customers | Customer signups & active tenders |
| **Tender Volume** | 100+ tenders/month (all pilots combined) | Database metrics |
| **Vendor Participation** | 500+ registered vendors | User database |
| **LGPD Compliance** | 100% coverage | Audit trail completeness |
| **Test Coverage** | >= 75% | Code coverage reports |
| **Documentation** | 100% of APIs documented | Swagger/OpenAPI completeness |

---

## Out of Scope (Future Releases)

- ❌ Advanced analytics & BI dashboards
- ❌ AI-powered vendor recommendations
- ❌ Procurement forecasting / demand planning
- ❌ Contract lifecycle management (CLM)
- ❌ Supplier performance dashboards
- ❌ EDI / B2B integration
- ❌ Multi-language support (beyond Portuguese)
- ❌ Advanced workflow automation (beyond approval chains)
- ❌ Reverse auction / dynamic pricing
- ❌ Integration with ERP systems
- ❌ Mobile app (web-responsive initially)

---

## Dependencies & Assumptions

### External Dependencies

- **GCP Services**: Cloud SQL (PostgreSQL), Cloud Storage, Artifact Registry, Cloud Build
- **Email Service**: SendGrid or similar (for transactional emails)
- **OAuth2 Provider**: Google Cloud Identity (or built-in OAuth2 if custom IdP preferred)

### Assumptions

1. **Pilot customers** have existing vendor lists (manual upload via CSV)
2. **Single geographic region** (Brazil) for MVP
3. **Portuguese language** only (internationalization post-MVP)
4. **User base** < 100k concurrent (scaling designs in place, not all implemented)
5. **Tender complexity** limited (no multi-phase bidding, sub-contracting)

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| **Scope creep** | Delay | Strict feature gate; change control board |
| **Performance under load** | Failure | Load testing early; caching strategy |
| **Vendor adoption** | Low usage | Strong UX; onboarding support; early feedback |
| **Data isolation bugs** | Security | Code review focused on RLS; integration tests |
| **Pilot customer churn** | Loss of validation | Weekly check-ins; feedback loop; quick fixes |

---

## Approval & Sign-Off

| Role | Name | Signature | Date |
|------|------|-----------|------|
| **Product Owner** | [Name] | — | TBD |
| **Engineering Lead** | [Name] | — | TBD |
| **Architecture Review** | [Name] | — | TBD |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | Dec 2025 | Platform Team | Initial MVP scope |

---

**Document Type**: Product Requirements  
**Owner**: Product Management  
**Reviewers**: Engineering, Architecture, Security, Compliance  
**Last Updated**: December 2025
