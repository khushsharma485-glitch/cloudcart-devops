# Container images

Each service owns its Dockerfile next to its code (`services/<name>/Dockerfile`),
so the build context is just that service. The storefront has its own in
`frontend/`. This page explains the shared design.

## Multi-stage build

```
maven:3.9-eclipse-temurin-17   ->  mvn package (dependencies cached in a BuildKit cache mount)
eclipse-temurin:17-jre-alpine  ->  java -Djarmode=tools extract --layers
eclipse-temurin:17-jre-alpine  ->  runtime: JRE only, layers copied in order
```

| Stage | Why |
|---|---|
| build | JDK + Maven exist only here. Tests are not run in the image build; CI runs them first. |
| extract | Splits the Spring Boot jar into dependencies / loader / snapshot / application layers. Dependencies change rarely, so a code change rebuilds and pushes only the small application layer. |
| runtime | No compiler, no Maven, no shell tools beyond busybox. `apk upgrade` pulls Alpine fixes published after the base image. |

## Runtime hardening

- Runs as UID/GID `10001` (`USER 10001:10001`). Kubernetes enforces it with `runAsNonRoot` and the namespace's `restricted` Pod Security level.
- Works with a read-only root filesystem. The only writable path is `/tmp` (an `emptyDir` in Kubernetes and a `tmpfs` in Compose).
- `JAVA_TOOL_OPTIONS`:
  - `-XX:MaxRAMPercentage=65` sizes the heap from the container memory limit. The remaining 35% covers metaspace, thread stacks, code cache and buffers. At 75% the JVM was OOMKilled by the kernel before it could raise `OutOfMemoryError`; see [incident 03](../docs/incidents/03-high-memory.md).
  - `-XX:+ExitOnOutOfMemoryError` makes the process exit (code 3, with a log line) instead of limping on, so Kubernetes restarts it.
- Structured logs: `LOGGING_STRUCTURED_FORMAT_CONSOLE=ecs` writes JSON that Loki indexes.
- `HEALTHCHECK` (for Docker / Compose) uses the liveness endpoint. Kubernetes uses its own probes instead.

## Security scanning

- **hadolint** lints every Dockerfile in CI (`.hadolint.yaml`).
- **Trivy** scans every image in CI and fails on CRITICAL vulnerabilities. Locally, `make scan` fails on HIGH or CRITICAL.
- Trivy findings are fixed at the source. The first scan (Spring Boot 3.5.16) found a CRITICAL Tomcat CVE and HIGH CVEs in Jackson and pgjdbc. Later, CI blocked CVE-2026-47884 (CRITICAL, Spring Framework 6.2) which has no 6.2 fix because Boot 3.5 is out of open-source support, so the services moved to Spring Boot 4.1.1. The poms still pin Tomcat 11.0.26 and Jackson 3.1.7 above the Boot 4.1.1 defaults; Dependabot raises the PR that lets those pins go.

## Tags

CI tags every image with the full Git commit SHA, plus `X.Y.Z` on release tags `vX.Y.Z`. ECR repositories are `IMMUTABLE`, so a tag can never be re-pointed at different content. `latest` is never used.
