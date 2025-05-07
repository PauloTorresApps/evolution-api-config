# IMPLEMENTANDO PROMETHEUS COM GRAFANA

## Craindo os arquivos de configuração

Primeiro, vamos criar um docker-compose.yml que inclui todos os serviços mencionados e adiciona o Prometheus e Grafana:

```
docker-compose.yml


version: '3.8'

services:
  evolution-api:
    image: evolution/api:latest
    container_name: evolution-api
    restart: always
    ports:
      - "8080:8080"
    volumes:
      - ./evolution-api-data:/app/data
    networks:
      - app-network
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=8080"
      - "prometheus.path=/metrics"

  nginx:
    image: nginx:latest
    container_name: nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/logs:/var/log/nginx
      - ./nginx/html:/usr/share/nginx/html
    networks:
      - app-network
    depends_on:
      - evolution-api
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=80"
      - "prometheus.path=/metrics"

  postgres:
    image: postgres:14
    container_name: postgres
    restart: always
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: evolution
    volumes:
      - postgres-data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    networks:
      - app-network
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=5432"
      - "prometheus.path=/metrics"

  redis:
    image: redis:latest
    container_name: redis
    restart: always
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    command: redis-server --appendonly yes
    networks:
      - app-network
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=6379"
      - "prometheus.path=/metrics"

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: always
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
    networks:
      - app-network

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: always
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    networks:
      - app-network
    depends_on:
      - prometheus

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: always
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - "9100:9100"
    networks:
      - app-network
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=9100"
      - "prometheus.path=/metrics"

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: always
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8081:8080"
    networks:
      - app-network
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=8080"
      - "prometheus.path=/metrics"

networks:
  app-network:
    driver: bridge

volumes:
  postgres-data:
  redis-data:
  prometheus-data:
  grafana-data:
```

Agora, vamos criar a configuração do Prometheus para coletar métricas dos serviços:

```
prometheus.yml


global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'evolution-api'
    static_configs:
      - targets: ['evolution-api:8080']

  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx:80']

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'docker'
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        filters:
          - name: label
            values: ['prometheus.scrape=true']
    relabel_configs:
      - source_labels: [__meta_docker_container_label_prometheus_path]
        regex: (.+)
        target_label: __metrics_path__
        replacement: $1
      - source_labels: [__meta_docker_container_label_prometheus_port]
        regex: (.+)
        target_label: __address__
        replacement: $${1}:$${2}
      - source_labels: [__meta_docker_container_name]
        regex: '/(.*)'
        target_label: container_name
        replacement: $1
      - source_labels: [__meta_docker_container_label_com_docker_compose_service]
        target_label: service_name
```

Agora vamos configurar o NGINX para expor métricas para o Prometheus:

```
nginx.conf

server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
    }

    location /metrics {
        stub_status on;
        access_log off;
        allow 172.16.0.0/12;  # Permitir acesso da rede Docker
        deny all;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
```

Agora, vamos configurar a dashboard básica do Grafana para visualizar as métricas:

```
datasource.yaml


apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    orgId: 1
    url: http://prometheus:9090
    basicAuth: false
    isDefault: true
    editable: true
```

## Passo a passo para implementação

### 1.Crie a estrutura de diretórios

```
mkdir -p prometheus grafana/provisioning/datasources nginx/conf.d nginx/html nginx/logs evolution-api-data
```

### 2.Crie os arquivos de configuração

- Salve o arquivo docker-compose.yml na pasta raiz
- Salve o arquivo prometheus.yml em ./prometheus/
- Salve o arquivo datasource.yml em ./grafana/provisioning/datasources/
- Crie o arquivo de configuração NGINX em ./nginx/conf.d/default.conf

### 3.Adaptações necessárias para Evolution API:

- Verifique se a Evolution API disponibiliza um endpoint /metrics. Caso contrário, você pode precisar adicionar um exportador específico para esse serviço.

### 4.Inicialize os serviços:

```
docker-compose up -d
```

### 5.Acessando os serviços

```
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (usuário: admin, senha: admin)
```

## Configuração de Exportadores de Métricas

Para os serviços que não expõem métricas nativamente no formato Prometheus, adicionamos dois exportadores importantes:

1.<b>Node Exporter:</b> Coleta métricas do sistema operacional host
2.<b>cAdvisor:</b> Coleta métricas de containers Docker

Para PostgreSQL e Redis, é possível adicionar exportadores específicos:

```
Adição de Exportadores para PostgresSQL e Redis:


postgres-exporter:
    image: prometheuscommunity/postgres-exporter:latest
    container_name: postgres-exporter
    environment:
      DATA_SOURCE_NAME: "postgresql://postgres:postgres@postgres:5432/evolution?sslmode=disable"
    ports:
      - "9187:9187"
    networks:
      - app-network
    depends_on:
      - postgres
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=9187"
      - "prometheus.path=/metrics"

  redis-exporter:
    image: oliver006/redis_exporter:latest
    container_name: redis-exporter
    command: --redis.addr=redis://redis:6379
    ports:
      - "9121:9121"
    networks:
      - app-network
    depends_on:
      - redis
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=9121"
      - "prometheus.path=/metrics"
```

## Configurando dashboards no Grafana

Após acessar o Grafana (http://localhost:3000), você pode:

1. Verificar se a fonte de dados Prometheus está configurada (Configurações > Fontes 2.de dados)

2. Importar dashboards pré-configurados usando seus IDs:
   
   - Node Exporter: ID 1860
   - cAdvisor: ID 14282
   - PostgreSQL: ID 9628
   - Redis: ID 763
   - NGINX: ID 11199