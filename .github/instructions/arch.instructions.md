---
applyTo: '**'
---
# Copilot / AI Agent Instructions — MVP Repository

Purpose: Quickly equip an AI coding agent to be productive in this repository by summarizing the "big picture", developer workflows, project-specific conventions, and important commands discovered in `arquiteture.md`.

1) Big-picture architecture (from `arquiteture.md`)
- **Microservices**: repo follows a microservices mindset (domain-based boundaries, database-per-service, service autonomy).
- **Communication**: gRPC/protobufs for S2S; Kafka/RabbitMQ for async events; API Gateway (Kong) and service mesh expected for mTLS.
- **Persistence**: polyglot (Postgres, Mongo, Cassandra, Redis) and patterns like CQRS, Event Sourcing and Sagas are used.
- **Deploy/Run**: Docker images + Kubernetes; Helm charts + GitOps (ArgoCD/Flux) for deployments.

2) Prefered technologies & conventions (explicit)
- **Language/build**: Java (Spring Boot / Quarkus) with Gradle as default build system. Look for `build.gradle` / `gradlew` in service roots.
- **API-first**: Proto-first gRPC development using `buf` for linting and breaking-change checks. Expect `buf.yaml` and `proto/` folders.
- **CI gates**: proto lint/compat (buf), static analysis (Checkstyle/SpotBugs/PMD), dependency scanning (Snyk/OWASP), container scan (Trivy), SAST/DAST, Helm/chart linting.
- **K8s packaging**: Helm charts validated with `helm lint` and `kubeval` and chart-testing tooling (`ct`).

3) Quick commands — run these in a service root (adjust to the repo layout)
- Build & test Java: `./gradlew clean build` (or `./gradlew test`)
- Proto checks (from repo root or proto dir): `buf lint` and `buf breaking --against .` (ensure `buf.yaml` present)
- Helm chart checks: `helm lint charts/<chart>` and `kubeval charts/<chart>/templates` (or `ct lint` if configured)
- Container scan: `trivy image <image:tag>` for CI-style checks

4) What to look for when changing code
- If changing APIs, update `.proto` files and run `buf lint` + `buf breaking` before modifying generated code or API contracts.
- If changing data model, verify database migration patterns and any event schemas (update consumers and producers). Look for CQRS/Event Sourcing indicators in service folders.
- For infra changes (Helm/Manifests), run Helm linting and ensure GitOps-friendly diffs (no secrets). Use `kubeval` and chart-testing as CI gates.

5) Observability & runtime expectations
- All services should export Prometheus metrics, OpenTelemetry traces and structured JSON logs with correlation IDs. When adding instrumentation, follow existing metric names and tracing propagation.

6) Security constraints (enforced in CI/runtime)
- Secrets must not be in the repo — expect Vault / cloud secrets manager integration. Do not commit credentials.
- mTLS and service identity expected via service-mesh or cert automation. Changes that affect networking/security require infra/ops review.

7) PR checklist for AI-generated changes
- Update/load tests: `./gradlew test` (or equivalent). Ensure green.
- If API changes: run `buf lint` and `buf breaking` and add consumers' updates or migration notes.
- Run static analysis and container scans locally if available (`./gradlew check`, `trivy`).
- Update Helm/chart linting: `helm lint` and `kubeval` for changed charts.
- Add or update SLO/metric names if behavioral changes affect observability.

8) Files and locations to inspect first
- `arquiteture.md` — architecture and conventions (source of truth for this repo).
- Search for service roots with `build.gradle`/`gradlew`, `proto/`, `charts/` or `helm/`, `Dockerfile`, `.github/workflows/`.

9) Agent behavior rules (repository-specific)
- Avoid making breaking API changes without adding `proto` compatibility checks and bump instructions.
- Do not add secrets, keys, or credentials to the repo. If required, add placeholders and document secret provisioning steps.
- When adding dependencies, prefer minimal, well-maintained libraries; call out SCA (software composition analysis) concerns in the PR.

10) When you are unsure
- Ask for a maintainer/author review and reference `arquiteture.md` for design rationale. For infra or security-impacting changes, request an infra/security reviewer explicitly.

