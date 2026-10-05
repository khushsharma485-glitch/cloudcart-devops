# syntax=docker/dockerfile:1.7
#
# Multi-stage build:
#   1. build   - full JDK + Maven, compiles and packages the jar
#   2. extract - splits the jar into Spring Boot layers (deps change rarely,
#                app code changes often, so Docker layer caching works well)
#   3. runtime - JRE only, no Maven, no compiler, runs as a non-root user
#
# Tests are not run here: CI runs them before building the image.

FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /workspace
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn -B -q dependency:go-offline
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 mvn -B -q package -DskipTests

FROM eclipse-temurin:17-jre-alpine AS extract
WORKDIR /extract
COPY --from=build /workspace/target/app.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination layers

FROM eclipse-temurin:17-jre-alpine AS runtime
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="cloudcart" \
      org.opencontainers.image.source="https://github.com/cloudcart/cloudcart-devops" \
      org.opencontainers.image.version="${APP_VERSION}"

# Pick up security fixes released after the base image was built, then
# create an unprivileged user with a fixed UID so Kubernetes
# runAsNonRoot/runAsUser checks can verify it.
RUN apk upgrade --no-cache \
 && addgroup -S -g 10001 app \
 && adduser -S -D -H -u 10001 -G app -s /sbin/nologin app

WORKDIR /app
COPY --from=extract --chown=app:app /extract/layers/dependencies/ ./
COPY --from=extract --chown=app:app /extract/layers/spring-boot-loader/ ./
COPY --from=extract --chown=app:app /extract/layers/snapshot-dependencies/ ./
COPY --from=extract --chown=app:app /extract/layers/application/ ./

USER 10001:10001

# Heap = 65% of the container memory limit; the rest is for metaspace,
# thread stacks, code cache and direct buffers. At 75% the JVM outgrew a
# 512Mi limit and was OOMKilled by the kernel (exit 137, no log line) before
# it could raise OutOfMemoryError (docs/incidents/03-high-memory.md).
ENV SERVER_PORT=8080 \
    APP_VERSION=${APP_VERSION} \
    LOGGING_STRUCTURED_FORMAT_CONSOLE=ecs \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=65 -XX:+ExitOnOutOfMemoryError -Djava.io.tmpdir=/tmp"

EXPOSE 8080

# Used by Docker / docker compose. Kubernetes uses its own probes instead.
HEALTHCHECK --interval=15s --timeout=3s --start-period=60s --retries=3 \
  CMD ["wget", "-q", "--spider", "http://127.0.0.1:8080/actuator/health/liveness"]

ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
