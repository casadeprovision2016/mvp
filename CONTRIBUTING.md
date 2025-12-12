# Contributing to Cotai

Thank you for your interest in contributing to Cotai! This guide provides standards and workflows for developing, testing, and submitting changes.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Commit Conventions](#commit-conventions)
- [Code Style & Quality](#code-style--quality)
- [Testing Requirements](#testing-requirements)
- [Pull Request Process](#pull-request-process)
- [API-First Development](#api-first-development)
- [Observability & Instrumentation](#observability--instrumentation)
- [Documentation](#documentation)

---

## Getting Started

### 1. Validate Your Workstation

Ensure all required tools are installed and validated:

```bash
bash scripts/setup-workstation.sh
```

This script verifies:
- `git` (2.20+), `docker` (24.0+), `minikube` (1.31+), `kubectl` (1.27+), `helm` (3.12+)
- `go` (1.21+), `python` (3.11+), `java` (17+)
- `golangci-lint`, `trivy`, `buf`, `kubectl-score`

### 2. Clone the Repository

```bash
git clone https://github.com/your-org/cotai.git
cd cotai
```

### 3. Set Up Local Development Environment

```bash
# Start local Minikube cluster with dependencies
minikube start --driver=docker --addons=ingress,metrics-server

# Use Minikube's Docker daemon for builds
eval $(minikube docker-env)

# Install dependencies (PostgreSQL, Kafka, observability stack)
make local-setup
```

### 4. Install Pre-commit Hooks (Optional but Recommended)

```bash
# Install git hooks for linting and secret scanning
pip install pre-commit
pre-commit install
```

---

## Development Workflow

### Git Workflow: GitFlow

We use **GitFlow** branching strategy to support parallel development, staged releases, and hotfixes.

#### Branch Types

| Branch Type | Purpose | Naming Convention | Merge Into |
|-------------|---------|-------------------|------------|
| `main` | Production releases | — | (PR only) |
| `develop` | Integration branch for next release | — | `main` (via release) |
| `feature/*` | New feature or improvement | `feature/auth-mfa`, `feature/vendor-scoring` | `develop` |
| `bugfix/*` | Bug fix | `bugfix/jwt-expiry-issue` | `develop` |
| `release/*` | Release preparation | `release/v1.2.3` | `main` + back-merge to `develop` |
| `hotfix/*` | Production bug fix | `hotfix/critical-data-loss` | `main` + back-merge to `develop` |

#### Workflow Example: Feature Development

```bash
# 1. Start from latest develop
git checkout develop
git pull origin develop

# 2. Create feature branch
git checkout -b feature/auth-mfa

# 3. Make changes, test, commit
git add .
git commit -m "feat(auth-service): implement multi-factor authentication"

# 4. Run linters and tests
make lint
make test

# 5. Push and create PR
git push origin feature/auth-mfa
# Navigate to GitHub → Create Pull Request
```

#### Workflow Example: Release

```bash
# 1. Create release branch from develop
git checkout -b release/v1.2.3 develop

# 2. Update version numbers, changelog, etc.
# Update Chart.yaml appVersion, package.json, pom.xml, go.mod, etc.
git commit -m "chore: bump version to v1.2.3"

# 3. Merge to main
git checkout main
git pull origin main
git merge --no-ff release/v1.2.3 -m "Merge release v1.2.3"
git tag -s -m "Release v1.2.3" v1.2.3

# 4. Back-merge to develop
git checkout develop
git merge --no-ff release/v1.2.3
git push origin main develop --tags

# 5. Delete release branch
git push origin --delete release/v1.2.3
```

---

## Commit Conventions

We follow **[Conventional Commits](https://www.conventionalcommits.org/)** for clear, semantic commit messages.

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

| Type | Purpose | Changelog |
|------|---------|-----------|
| `feat` | New feature | ✅ Yes (minor) |
| `fix` | Bug fix | ✅ Yes (patch) |
| `docs` | Documentation | ❌ No |
| `style` | Code style, formatting (no logic change) | ❌ No |
| `refactor` | Code refactoring (no feature/bug fix) | ❌ No |
| `perf` | Performance improvement | ✅ Yes (patch) |
| `test` | Add or update tests | ❌ No |
| `chore` | Build, dependencies, configuration | ❌ No |
| `ci` | CI/CD workflow changes | ❌ No |

### Scope

Scope identifies the affected area (service, module, or domain):

```
feat(auth-service): implement OAuth2 PKCE flow
feat(edital-service): add tender versioning
fix(cotacao-service): resolve race condition in scoring
docs(observability): update SLO definitions
ci(github-actions): add Trivy container scanning
```

### Subject

- Use imperative mood: "add" not "added", "implement" not "implemented"
- Do not capitalize first letter
- Do not end with period
- Limit to 50 characters

### Body (Optional)

- Explain **why**, not what (the diff shows what)
- Wrap at 72 characters
- Separate from subject with a blank line

### Footer (Optional)

```
Closes #123
Refs #456, #789
Breaking-Change: JWT structure now includes tenant_id claim
```

### Examples

```
feat(auth-service): add multi-factor authentication

Implement TOTP-based MFA for user accounts with fallback SMS option.
Users can enable MFA in account settings; login flow validates MFA
token before issuing JWT.

Closes #345
```

```
fix(cotacao-service): prevent concurrent response submissions

Add distributed lock (Redis) to prevent race condition where multiple
threads could submit duplicate responses to same quotation.

Test: Added integration test `TestConcurrentResponseSubmissions`
Refs #234
```

```
docs: update README quick-start section
```

---

## Code Style & Quality

### Linting & Formatting

All code must pass linting before being pushed.

#### Go

```bash
# Run linter (configured in .golangci.yml)
golangci-lint run ./...

# Auto-format
go fmt ./...
goimports -w .
```

#### Java

```bash
# Run Checkstyle, SpotBugs, PMD
./gradlew checkstyleMain spotbugsMain pmdMain

# Auto-format (Google Java Format)
google-java-format -i src/**/*.java
```

#### Python

```bash
# Run ruff and flake8
ruff check .
flake8 .

# Auto-format with black
black .
```

#### Protocol Buffers

```bash
# Validate proto files
buf lint ./proto

# Check for breaking changes (against last release)
buf breaking --against '.git#ref=main'

# Auto-format
buf format -w ./proto
```

### Make Targets

```bash
# Run all linters
make lint

# Auto-format code
make format

# Run linters and fix issues automatically (where possible)
make lint-fix
```

---

## Testing Requirements

### Test Coverage Minimum: **75%**

All code must include tests. Use the pyramid model:

```
         /\          E2E Tests (slow, high confidence)
        /  \         Integration Tests (medium speed)
       /    \        Unit Tests (fast, isolated)
      /______\
```

### Unit Tests

**Fast, isolated, no external dependencies**

```go
// Go example (table-driven)
func TestValidateEmail(t *testing.T) {
  tests := []struct {
    name    string
    email   string
    want    bool
  }{
    {"valid email", "user@example.com", true},
    {"invalid email", "not-an-email", false},
  }
  for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
      if got := ValidateEmail(tt.email); got != tt.want {
        t.Errorf("ValidateEmail(%q) = %v, want %v", tt.email, got, tt.want)
      }
    })
  }
}
```

```java
// Java example
@Test
void shouldValidateEmail() {
  assertTrue(EmailValidator.isValid("user@example.com"));
  assertFalse(EmailValidator.isValid("not-an-email"));
}
```

### Integration Tests

**Against local services (database, Kafka, Redis)**

```bash
# Run integration tests
make test-integration
```

### Contract Tests

**Verify gRPC API compatibility between services**

```bash
# Run contract tests
make test-contracts
```

### Running Tests Locally

```bash
# All tests
make test

# Specific service
make test service=auth-service

# With coverage report
make test-coverage
```

### Running Tests in CI

Tests are executed automatically on each commit. To simulate CI locally:

```bash
# Run full CI pipeline locally
make ci-checks
```

---

## Pull Request Process

### 1. Create PR on GitHub

- **Title**: Use conventional commit format (e.g., `feat: add MFA support`)
- **Description**: Link to related issue, describe changes, note any breaking changes
- **Labels**: Apply service label (e.g., `auth-service`), type label (e.g., `feature`)

### 2. PR Template (Auto-populated)

```markdown
## Description
Brief description of changes and motivation.

## Related Issue
Closes #123

## Type of Change
- [x] Feature
- [ ] Bug fix
- [ ] Breaking change
- [ ] Documentation

## Testing
- [x] Unit tests added
- [x] Integration tests passing
- [x] Manual testing completed

## Checklist
- [x] Code follows style guidelines
- [x] Linting passes (`make lint`)
- [x] Tests pass (`make test`)
- [x] Test coverage >= 75%
- [x] Documentation updated
- [x] Proto files validated (`buf lint`, `buf breaking`)
- [x] Helm charts validated (`helm lint`, `kubeval`)
- [x] No secrets or credentials committed

## Screenshots (if applicable)
...

## Breaking Changes
Describe any breaking changes and migration path.
```

### 3. Code Review

- **CODEOWNERS** are automatically requested (see [CODEOWNERS](CODEOWNERS))
- **Minimum 1 approval** required before merge (2 for critical paths)
- **All CI checks must pass** (linting, tests, security scans)
- **All conversations must be resolved** before merge

### 4. PR Checklist (Author)

Before requesting review:

```bash
# 1. Code style
make lint

# 2. Tests
make test

# 3. Test coverage
make test-coverage  # Ensure >= 75%

# 4. Proto validation (if applicable)
buf lint ./services/my-service/proto
buf breaking --against '.git#ref=main' ./services/my-service/proto

# 5. Helm validation (if applicable)
helm lint ./services/my-service/charts/

# 6. Documentation
# - Ensure README updated
# - Proto files documented
# - API changes documented in ADR or ARCHITECTURE.md

# 7. No secrets committed
git diff HEAD~1 | grep -i "password\|token\|key\|secret" && echo "SECRETS FOUND!" || echo "OK"

# 8. Commit messages follow Conventional Commits
# Review your commits: git log develop..HEAD --oneline
```

### 5. Merge Requirements

- ✅ All CI checks pass
- ✅ At least 1 approval from CODEOWNERS
- ✅ No unresolved conversations
- ✅ Branch is up-to-date with target branch

---

## API-First Development

All APIs must be designed and documented **before** implementation.

### gRPC (Service-to-Service)

1. **Define proto contract** in `proto/` directory:
   ```protobuf
   syntax = "proto3";
   package cotai.v1;
   
   service CotacaoService {
     rpc CreateCotacao(CreateCotacaoRequest) returns (CotacaoResponse);
   }
   ```

2. **Validate proto**:
   ```bash
   buf lint
   buf breaking --against '.git#ref=main'
   ```

3. **Generate code**:
   ```bash
   buf generate
   ```

4. **Implement service** with the generated interfaces

### REST (External APIs)

1. **Define OpenAPI spec** in `openapi/` directory
2. **Review and document endpoints** before implementation
3. **Validate OpenAPI**:
   ```bash
   spectacle openapi/cotacao-api.yaml  # Generate docs
   ```

---

## Observability & Instrumentation

All changes must maintain or improve observability.

### Required Instrumentation

#### Traces

- Entry points (HTTP, gRPC, message handlers)
- Database queries
- External API calls
- Business-critical operations

```go
// Go example
span := tracer.Start(ctx, "cotacao.criar",
  trace.WithAttributes(
    attribute.String("tenant_id", tenantId),
    attribute.String("http.method", "POST"),
  ),
)
defer span.End()
```

#### Metrics

- Request latency (histogram)
- Request count (counter)
- Error rate (counter)
- Business metrics (e.g., "cotacoes_criadas", "fornecedores_avaliados")

```go
// Go example
requestDuration.Record(ctx, elapsed,
  metric.WithAttributes(
    attribute.String("service", "cotacao-service"),
    attribute.String("method", "CreateCotacao"),
  ),
)
```

#### Logs

- Structured JSON logs
- Correlation IDs (trace_id, request_id)
- Contextual data (tenant_id, user_id, resource_id)

```go
// Go example
logger.Info("cotacao criada",
  "trace_id", traceID,
  "tenant_id", tenantID,
  "cotacao_id", cotacaoID,
)
```

See [Observability Guide](docs/observability.md) for detailed instrumentation patterns.

---

## Documentation

### README Updates

- Explain new features, APIs, or configuration
- Add examples if applicable
- Update table of contents

### Code Comments

- Public functions/types must have GoDoc-style comments
- Complex logic should have explanatory comments
- Don't comment obvious code

```go
// ValidateEmail checks if email format is valid per RFC 5322.
func ValidateEmail(email string) bool { ... }

// Circuit breaker pattern with exponential backoff.
// Max 3 retries, starting with 100ms delay.
func callExternalAPI(ctx context.Context) error { ... }
```

### Architecture Decision Records (ADRs)

For significant architectural decisions, create an ADR:

1. Copy template: `cp docs/adr/ADR-000-TEMPLATE.md docs/adr/ADR-NNN-Your-Decision.md`
2. Fill in sections: Context, Decision, Consequences, Alternatives
3. Submit PR with your changes referencing the ADR

Example: [ADR-001-Kafka-Event-Bus.md](docs/adr/ADR-001-Kafka-Event-Bus.md)

---

## Questions or Need Help?

- **GitHub Issues**: For bugs and feature requests
- **GitHub Discussions**: For architecture questions and RFCs
- **Slack**: Internal channel `#cotai-dev`
- **Team**: Reach out to service CODEOWNERS

---

**Last Updated**: December 2025  
**Maintained By**: Platform Engineering Team
