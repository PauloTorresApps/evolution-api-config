#!/bin/sh

# Set up OpenTelemetry environment variables for Honeycomb
export OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-n8n}"
export OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://api.honeycomb.io"
export OTEL_EXPORTER_OTLP_HEADERS="x-honeycomb-team=${HONEYCOMB_API_KEY}"
export OTEL_EXPORTER_OTLP_TRACES_HEADERS="x-honeycomb-team=${HONEYCOMB_API_KEY}"
export OTEL_LOG_LEVEL="info"

# Start n8n with OpenTelemetry instrumentation
echo "Starting n8n with OpenTelemetry instrumentation and Honeycomb export..."
exec node --require /usr/local/lib/node_modules/n8n/tracing.js /usr/local/bin/n8n "$@"