# Clusterizando PostgreSQL com Docker Swarm

Para criar um cluster PostgreSQL com Docker Swarm de forma correta, é necessário considerar vários aspectos como alta disponibilidade, replicação, backup e recuperação. Vou te mostrar como configurar um cluster PostgreSQL robusto usando Docker Swarm.

## Arquitetura recomendada
A arquitetura recomendada para um cluster PostgreSQL em Docker Swarm consiste em:

- Um nó primário (master) para escrita
- Múltiplos nós de réplica (slave) para leitura
- Sistema de gerenciamento de volume para persistência de dados
- Sistema de monitoramento e failover automático

## Passo a passo para implementação
### 1. Inicialize seu cluster Docker Swarm

```
# No nó que será o manager
docker swarm init --advertise-addr <IP_DO_MANAGER>

# Nos nós workers (o comando exato será fornecido após inicializar o swarm no manager)
docker swarm join --token <TOKEN> <IP_DO_MANAGER>:2377
```

### 2. Configure um sistema de volumes compartilhados
Para um cluster PostgreSQL, recomendo usar volumes nomeados com um driver de armazenamento distribuído como NFS ou, preferencialmente, um plugin de volume específico para armazenamento em cluster.
Instale um plugin de volume como o REX-Ray:
```
docker plugin install rexray/s3fs \
  --grant-all-permissions \
  S3FS_ACCESSKEY=<access-key> \
  S3FS_SECRETKEY=<secret-key>
  ```

### 3. Crie seu arquivo docker-compose.yml para o cluster PostgreSQL

#### postgres-swarm-stack.yml
```
version: '3.8'

services:
  postgres-master:
    image: postgres:14
    command: postgres -c 'max_connections=200' -c 'wal_level=replica' -c 'archive_mode=on' -c 'max_wal_senders=10' -c 'wal_keep_size=1024'
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-StrongPasswordHere}
      POSTGRES_DB: postgres
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgres-master-data:/var/lib/postgresql/data
    configs:
      - source: pg_hba_conf
        target: /var/lib/postgresql/data/pgdata/pg_hba.conf
      - source: postgresql_conf
        target: /var/lib/postgresql/data/pgdata/postgresql.conf
    networks:
      - postgres-network
    ports:
      - "5432:5432"
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
          - node.labels.postgres-master == true
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 2G
      update_config:
        parallelism: 1
        delay: 10s
        order: stop-first
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  postgres-replica:
    image: postgres:14
    command: >
      bash -c "
        until pg_basebackup -h postgres-master -p 5432 -D /var/lib/postgresql/data/pgdata -U replicator -v -P -R -X stream -C; do
          echo 'Waiting for primary to be available...'
          sleep 1
        done
        echo 'Replica initialized, starting PostgreSQL'
        exec postgres
      "
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-StrongPasswordHere}
      POSTGRES_DB: postgres
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgres-replica-data:/var/lib/postgresql/data
    networks:
      - postgres-network
    depends_on:
      - postgres-master
    deploy:
      mode: replicated
      replicas: 2
      placement:
        constraints:
          - node.labels.postgres-replica == true
        preferences:
          - spread: node.id
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s
      resources:
        limits:
          cpus: '1'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 1G
      update_config:
        parallelism: 1
        delay: 10s
        order: stop-first
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  pgbouncer:
    image: bitnami/pgbouncer:latest
    environment:
      POSTGRESQL_HOST: postgres-master
      POSTGRESQL_PORT: 5432
      POSTGRESQL_USERNAME: postgres
      POSTGRESQL_PASSWORD: ${POSTGRES_PASSWORD:-StrongPasswordHere}
      PGBOUNCER_DATABASE: postgres
      PGBOUNCER_POOL_MODE: transaction
      PGBOUNCER_MAX_CLIENT_CONN: 1000
      PGBOUNCER_DEFAULT_POOL_SIZE: 50
    networks:
      - postgres-network
    ports:
      - "6432:6432"
    deploy:
      mode: replicated
      replicas: 2
      placement:
        preferences:
          - spread: node.id
      restart_policy:
        condition: on-failure
      update_config:
        parallelism: 1
        delay: 10s
        order: stop-first

  pgbackrest:
    image: woblerr/pgbackrest:latest
    volumes:
      - pgbackrest-config:/etc/pgbackrest
      - pgbackrest-backups:/var/lib/pgbackrest
      - postgres-master-data:/var/lib/postgresql/data:ro
    networks:
      - postgres-network
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure

  patroni:
    image: patroni:latest
    environment:
      PATRONI_SCOPE: postgres
      PATRONI_NAME: ${HOSTNAME}
      PATRONI_POSTGRESQL_CONNECT_ADDRESS: ${HOSTNAME}:5432
      PATRONI_POSTGRESQL_DATA_DIR: /var/lib/postgresql/data/pgdata
      PATRONI_RESTAPI_CONNECT_ADDRESS: ${HOSTNAME}:8008
      PATRONI_ETCD_HOST: etcd:2379
      PATRONI_POSTGRESQL_PGPASS: /tmp/pgpass
      PATRONI_POSTGRESQL_REPLICATION_USERNAME: replicator
      PATRONI_POSTGRESQL_REPLICATION_PASSWORD: ${REPLICATOR_PASSWORD:-ReplicatorPassword}
      PATRONI_SUPERUSER_USERNAME: postgres
      PATRONI_SUPERUSER_PASSWORD: ${POSTGRES_PASSWORD:-StrongPasswordHere}
    volumes:
      - patroni-data:/var/lib/postgresql/data
    networks:
      - postgres-network
    deploy:
      mode: global
      restart_policy:
        condition: on-failure

  etcd:
    image: bitnami/etcd:latest
    environment:
      ALLOW_NONE_AUTHENTICATION: "yes"
      ETCD_ADVERTISE_CLIENT_URLS: http://etcd:2379
      ETCD_LISTEN_CLIENT_URLS: http://0.0.0.0:2379
    volumes:
      - etcd-data:/bitnami/etcd
    networks:
      - postgres-network
    deploy:
      mode: replicated
      replicas: 3
      placement:
        constraints:
          - node.role == manager
        preferences:
          - spread: node.id
      restart_policy:
        condition: on-failure
      update_config:
        parallelism: 1
        delay: 10s
        order: stop-first

  pgadmin:
    image: dpage/pgadmin4:latest
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@example.com
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_PASSWORD:-AdminPassword}
      PGADMIN_CONFIG_SERVER_MODE: "False"
    volumes:
      - pgadmin-data:/var/lib/pgadmin
    networks:
      - postgres-network
    ports:
      - "8080:80"
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure

networks:
  postgres-network:
    driver: overlay
    attachable: true

volumes:
  postgres-master-data:
    driver: rexray/s3fs
    driver_opts:
      size: "20"
  postgres-replica-data:
    driver: rexray/s3fs
    driver_opts:
      size: "20"
  patroni-data:
    driver: rexray/s3fs
    driver_opts:
      size: "10"
  pgbackrest-config:
    driver: local
  pgbackrest-backups:
    driver: rexray/s3fs
    driver_opts:
      size: "100"
  etcd-data:
    driver: local
  pgadmin-data:
    driver: local

configs:
  pg_hba_conf:
    file: ./pg_hba.conf
  postgresql_conf:
    file: ./postgresql.conf
```

### 4. Crie os arquivos de configuração necessários
#### postgresql.conf
```# Configurações para o PostgreSQL Master
listen_addresses = '*'
max_connections = 200
shared_buffers = 1GB
effective_cache_size = 3GB
work_mem = 16MB
maintenance_work_mem = 256MB
random_page_cost = 1.1
effective_io_concurrency = 200
parallel_tuple_cost = 0.1
parallel_setup_cost = 0.1
max_parallel_workers_per_gather = 4
max_parallel_workers = 8

# Configurações de replicação
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 1GB
hot_standby = on
hot_standby_feedback = on

# Configurações de performance
synchronous_commit = off
checkpoint_timeout = 15min
max_wal_size = 2GB
min_wal_size = 1GB
checkpoint_completion_target = 0.9
default_statistics_target = 100
```
#### pg_hba.conf
```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             postgres                                trust
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5

# Permitir acesso de réplicas 
host    replication     replicator      samenet                 md5

# Permitir acesso da rede interna do swarm
host    all             all             10.0.0.0/8              md5
host    all             all             172.16.0.0/12           md5
host    all             all             192.168.0.0/16          md5

```
### 5.Preparando os nós para o cluster
Antes de implantar o stack, você precisa rotular os nós que serão utilizados:

```
# Etiquete o nó que será o master do PostgreSQL
docker node update --label-add postgres-master=true <NODE-ID-OU-HOSTNAME>

# Etiquete os nós que serão réplicas
docker node update --label-add postgres-replica=true <NODE-ID-OU-HOSTNAME>
docker node update --label-add postgres-replica=true <NODE-ID-OU-HOSTNAME-2>
```
### 6. Deploy do stack PostgreSQL

```bash
docker stack deploy -c postgres-swarm-stack.yml postgres
```

### 7. Monitorando o cluster
Para monitorar o cluster, recomendo configurar o Prometheus e Grafana:
```bash
# Crie um diretório para os arquivos de configuração
mkdir -p monitoring/prometheus monitoring/grafana
```

#### Usuário dedicado para monitoramento do postgres

```sql
-- Crie um usuário dedicado para o exporter
CREATE USER postgres_exporter WITH PASSWORD 'exporter_password';

-- Conceda permissão para conectar ao banco de dados que você quer monitorar (ex: 'meu_banco')
-- Se o exporter for monitorar todos os bancos, você pode precisar ajustar ou rodar em cada um.
-- Geralmente, ele se conecta a um banco específico (pode ser 'postgres' ou o seu principal).
GRANT CONNECT ON DATABASE seu_banco_de_dados TO postgres_exporter; -- Substitua 'seu_banco_de_dados'

-- Conceda permissões para visualizar estatísticas
GRANT SELECT ON pg_stat_database TO postgres_exporter;
GRANT SELECT ON pg_stat_activity TO postgres_exporter;
GRANT SELECT ON pg_stat_user_tables TO postgres_exporter;
GRANT SELECT ON pg_stat_user_indexes TO postgres_exporter;
GRANT SELECT ON pg_stat_bgwriter TO postgres_exporter;
GRANT SELECT ON pg_stat_database_conflicts TO postgres_exporter;
-- Para algumas métricas mais detalhadas ou queries customizadas, pode ser necessário mais.
-- Para versões mais recentes do exporter e para métricas como tamanho de WAL,
-- pode ser necessário acesso a funções específicas.
-- Exemplo, se o exporter usar:
-- GRANT EXECUTE ON FUNCTION pg_ls_waldir() TO postgres_exporter; (ou pg_ls_waldir_nativelib() em versões mais novas)
-- GRANT EXECUTE ON FUNCTION pg_stat_file(text) TO postgres_exporter;
-- GRANT pg_monitor TO postgres_exporter; -- PostgreSQL 10+ oferece este role que simplifica muitas permissões.

-- Se você estiver usando PostgreSQL 10 ou superior, o role pg_monitor é recomendado:
-- GRANT pg_monitor TO postgres_exporter;
-- Isso já concede a maioria das permissões necessárias.
-- Verifique a documentação do postgres_exporter para as permissões exatas recomendadas para sua versão.
```

Crie um arquivo `monitoring-stack.yml` para implantar Prometheus e Grafana:
#### monitoring-stack.yml
```yml

version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    ports:
      - "9090:9090"
    networks:
      - monitoring-network
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure

  postgres-exporter:
    image: prometheuscommunity/postgres-exporter:latest
    environment:
      DATA_SOURCE_NAME: "postgresql://postgres:${POSTGRES_PASSWORD:-StrongPasswordHere}@postgres-master:5432/postgres?sslmode=disable"
    networks:
      - monitoring-network
      - postgres_postgres-network
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: on-failure

  node-exporter:
    image: prom/node-exporter:latest
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
      - monitoring-network
    deploy:
      mode: global
      restart_policy:
        condition: on-failure

  grafana:
    image: grafana/grafana:latest
    volumes:
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-GrafanaPassword}
      - GF_USERS_ALLOW_SIGN_UP=false
    ports:
      - "3000:3000"
    networks:
      - monitoring-network
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure

networks:
  monitoring-network:
    driver: overlay
  postgres_postgres-network:
    external: true

volumes:
  prometheus-data:
  grafana-data:

```
Crie o arquivo de configuração do Prometheus:
#### prometheus.yml

```yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    scrape_interval: 5s
    dns_sd_configs:
      - names:
          - 'tasks.node-exporter'
        type: 'A'
        port: 9100

  - job_name: 'postgres-exporter'
    scrape_interval: 5s
    static_configs:
      - targets: ['postgres-exporter:9187']
```

Deploy o stack de monitoramento:
```bash
docker stack deploy -c monitoring-stack.yml monitoring
```

## Recomendações importantes para produção

1. Segurança:

- Não use senhas padrão em produção
- Configure o uso de TLS/SSL para conexões PostgreSQL
- Restrinja o acesso à rede usando regras de firewall


2. Backups:

- Configure backups regulares usando pgBackRest
- Armazene backups em locais externos ao cluster
- Teste regularmente o processo de restauração


3. Alta disponibilidade:

- Use ferramentas como Patroni ou Stolon para gerenciar failover automático
- Configure um sistema de DNS dinâmico para apontar sempre para o nó primário ativo


4. Monitoramento:

- Crie alertas para métricas críticas como espaço em disco, carga de CPU, número de conexões, etc.
- Monitore o tempo de replicação entre o primário e as réplicas


5. Escalabilidade:

- Para melhor desempenho em leituras, adicione mais réplicas
- Use PgBouncer para gerenciar o pool de conexões.


### Considerações adicionais

- Sharding: Para bancos de dados muito grandes, considere implementar sharding com PostgreSQL e uma ferramenta como Citus
- Atualizações: Planeje atualizações com tempo de inatividade mínimo usando a estratégia de blue-green deployment

Essa configuração fornece um cluster PostgreSQL robusto com alta disponibilidade, replicação, balanceamento de carga e monitoramento, tudo orquestrado pelo Docker Swarm.