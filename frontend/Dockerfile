# Static storefront on an unprivileged nginx (runs as UID 101, port 8080).
FROM nginxinc/nginx-unprivileged:1.30-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD ["wget", "-q", "--spider", "http://127.0.0.1:8080/healthz"]
