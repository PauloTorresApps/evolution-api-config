#!/bin/bash
# restore_backup.sh - Restaura backups gerados pelo script de backup (versão compatível)

# Configurações (devem bater com o script de backup)
BACKUP_DIR="../backups"
PG_USER="postgres"  # Altere se necessário
RESTORE_GLOBALS=true

# Funções auxiliares
error_exit() {
    echo "[ERRO] $1"
    exit 1
}

restore_globals() {
    local file="$1"
    echo "Restaurando configurações globais de: $file"
    
    if [[ "$file" == *.gz ]]; then
        gunzip -c "$file" | psql -U "$PG_USER" -d postgres || error_exit "Falha ao restaurar globals"
    else
        psql -U "$PG_USER" -d postgres -f "$file" || error_exit "Falha ao restaurar globals"
    fi
}

restore_database() {
    local file="$1"
    local filename=$(basename "$file")
    local dbname=$(echo "$filename" | cut -d'_' -f1)
    
    echo "Criando banco $dbname..."
    createdb -U "$PG_USER" "$dbname" || echo "Banco já existe ou erro na criação. Continuando..."
    
    echo "Restaurando banco $dbname de: $file"
    
    if [[ "$file" == *.gz ]]; then
        gunzip -c "$file" | psql -U "$PG_USER" -d "$dbname" || error_exit "Falha ao restaurar banco $dbname"
    else
        psql -U "$PG_USER" -d "$dbname" -f "$file" || error_exit "Falha ao restaurar banco $dbname"
    fi
}

# Verificar se o diretório existe
[ -d "$BACKUP_DIR" ] || error_exit "Diretório de backups não encontrado: $BACKUP_DIR"

# Listar backups disponíveis
echo "Backups disponíveis:"
echo "---------------------"
ls -1t "$BACKUP_DIR" | grep -E '\.sql$|\.sql.gz$' | cat -n
echo

# Selecionar backup
read -p "Digite o número do backup a restaurar: " backup_num
selected_file=$(ls -1t "$BACKUP_DIR" | grep -E '\.sql$|\.sql.gz$' | sed -n "${backup_num}p")

[ -z "$selected_file" ] && error_exit "Seleção inválida"

full_path="$BACKUP_DIR/$selected_file"
echo "Backup selecionado: $selected_file"
echo

# Detectar tipo de backup
if [[ "$selected_file" == todos_bancos_* ]]; then
    # Backup completo (pg_dumpall)
    echo "Restaurando backup completo..."
    if [[ "$selected_file" == *.gz ]]; then
        gunzip -c "$full_path" | psql -U "$PG_USER" -d postgres || error_exit "Restauração falhou"
    else
        psql -U "$PG_USER" -d postgres -f "$full_path" || error_exit "Restauração falhou"
    fi
else
    # Backup parcial (globals + databases individuais)
    if [ "$RESTORE_GLOBALS" = true ]; then
        global_file=$(ls -1t "$BACKUP_DIR" | grep "globals_${selected_file#*_}" | head -1)
        [ -n "$global_file" ] && restore_globals "$BACKUP_DIR/$global_file"
    fi

    # Restaurar bancos individuais
    timestamp_part="${selected_file#*_}"
    for file in "$BACKUP_DIR"/*"$timestamp_part"; do
        if [[ "$file" != *globals* ]]; then
            restore_database "$file"
        fi
    done
fi

echo "----------------------------------------"
echo "Restauração concluída com sucesso!"
echo "Verifique os logs acima para eventuais avisos"