#!/bin/bash
# restore_backup.sh - Restaura backup PostgreSQL

set -e

# Configurações
PG_HOST="${PG_HOST:-postgres}"
PG_USER="${PG_USER:-postgres}"
PG_PORT="${PG_PORT:-5432}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"

# Funções auxiliares
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

restore_database() {
    local file="$1"
    local dbname=$(basename "$file" | cut -d'_' -f1)
    
    log "Restaurando banco: $dbname"
    
    # Criar banco se não existir
    if ! psql -h "$PG_HOST" -U "$PG_USER" -lqt | cut -d \| -f 1 | grep -qw "$dbname"; then
        createdb -h "$PG_HOST" -U "$PG_USER" "$dbname"
    fi
    
    # Restaurar backup
    case "$file" in
        *.gz)
            gunzip -c "$file" | psql -h "$PG_HOST" -U "$PG_USER" -d "$dbname"
            ;;
        *)
            psql -h "$PG_HOST" -U "$PG_USER" -d "$dbname" -f "$file"
            ;;
    esac
    
    log "Banco $dbname restaurado com sucesso!"
}

restore_full_backup() {
    local file="$1"
    log "Restaurando backup completo"
    
    case "$file" in
        *.gz)
            gunzip -c "$file" | psql -h "$PG_HOST" -U "$PG_USER" -d postgres
            ;;
        *)
            psql -h "$PG_HOST" -U "$PG_USER" -d postgres -f "$file"
            ;;
    esac
    
    log "Backup completo restaurado com sucesso!"
}

# Principal
main() {
    local backup_file="$1"
    local full_path="${BACKUP_DIR}/${backup_file}"
    
    [ -f "$full_path" ] || {
        log "Arquivo não encontrado: $full_path"
        exit 1
    }
    
    log "Iniciando restauração: $backup_file"
    
    # Detectar tipo de backup
    if [[ "$backup_file" == todos_bancos_* ]]; then
        restore_full_backup "$full_path"
    else
        restore_database "$full_path"
    fi
    
    log "Restauração concluída com sucesso!"
}

main "$@"