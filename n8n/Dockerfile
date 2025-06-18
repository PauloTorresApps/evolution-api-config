FROM n8nio/n8n:latest

USER root

# Install required packages
RUN echo "Installing required packages..." && \
    apk add --no-cache \
    curl \
    gettext \
    coreutils \
    openssl \
    ca-certificates \
    musl-dev && \
    echo "Curl installed successfully: $(curl --version | head -n 1)" && \
    echo "Envsubst installed successfully: $(envsubst --version | head -n 1)"

# Switch to n8n's installation directory
WORKDIR /usr/local/lib/node_modules/n8n

# Install Node.js OpenTelemetry dependencies locally to n8n
RUN npm install --legacy-peer-deps \
    @opentelemetry/api \
    @opentelemetry/sdk-node \
    @opentelemetry/auto-instrumentations-node \
    @opentelemetry/exporter-trace-otlp-http \
    @opentelemetry/exporter-logs-otlp-http \
    @opentelemetry/resources \
    @opentelemetry/semantic-conventions \
    @opentelemetry/instrumentation \
    @opentelemetry/instrumentation-winston \
    @opentelemetry/winston-transport \
    winston \
    flat

# Copy instrumentation files to n8n directory
COPY tracing.js n8n-otel-instrumentation.js ./ 
RUN chown node:node ./*.js

# Copy entrypoint script
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN echo "Setting entrypoint permissions..." && \
    chmod +x /docker-entrypoint.sh && \
    chown node:node /docker-entrypoint.sh && \
    echo "Entrypoint script contents:" && \
    cat /docker-entrypoint.sh

USER node

ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]