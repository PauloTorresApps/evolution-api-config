#!/bin/sh
# restore_backup.sh - Versão totalmente compatível com POSIX shell

# Configurações
BACKUP_DIR="../backups"
PG_USER="postgres"
RESTORE_GLOBALS=true

# Funções auxiliares
error_exit() {
    echo "[ERRO] $1"
    exit 1
}

restore_globals() {
    file="$1"
    echo "Restaurando configurações globais de: $file"
    
    case "$file" in
        *.gz)
            gunzip -c "$file" | psql -U "$PG_USER" -d postgres || error_exit "Falha ao restaurar globals"
            ;;
        *)
            psql -U "$PG_USER" -d postgres -f "$file" || error_exit "Falha ao restaurar globals"
            ;;
    esac
}

restore_database() {
    file="$1"
    filename=$(basename "$file")
    # Extrai o nome do banco antes do primeiro underscore
    dbname=$(echo "$filename" | cut -d'_' -f1)
    
    echo "Criando banco $dbname..."
    createdb -U "$PG_USER" "$dbname" || echo "Banco já existe ou erro na criação. Continuando..."
    
    echo "Restaurando banco $dbname de: $file"
    
    case "$file" in
        *.gz)
            gunzip -c "$file" | psql -U "$PG_USER" -d "$dbname" || error_exit "Falha ao restaurar banco $dbname"
            ;;
        *)
            psql -U "$PG_USER" -d "$dbname" -f "$file" || error_exit "Falha ao restaurar banco $dbname"
            ;;
    esac
}

# Verificar se o diretório existe
[ -d "$BACKUP_DIR" ] || error_exit "Diretório de backups não encontrado: $BACKUP_DIR"

# Listar backups disponíveis
echo "Backups disponíveis:"
echo "---------------------"
ls -1t "$BACKUP_DIR" | grep -E '\.sql$|\.sql.gz$' | cat -n
echo

# Selecionar backup
echo "Digite o número do backup a restaurar: "
read backup_num
selected_file=$(ls -1t "$BACKUP_DIR" | grep -E '\.sql$|\.sql.gz$' | sed -n "${backup_num}p")

[ -z "$selected_file" ] && error_exit "Seleção inválida"

full_path="$BACKUP_DIR/$selected_file"
echo "Backup selecionado: $selected_file"
echo

# Detectar tipo de backup
case "$selected_file" in
    todos_bancos_*)
        echo "Restaurando backup completo..."
        case "$selected_file" in
            *.gz)
                gunzip -c "$full_path" | psql -U "$PG_USER" -d postgres || error_exit "Restauração falhou"
                ;;
            *)
                psql -U "$PG_USER" -d postgres -f "$full_path" || error_exit "Restauração falhou"
                ;;
        esac
        ;;
    *)
        # Backup parcial
        if [ "$RESTORE_GLOBALS" = "true" ]; then
            timestamp_part=$(echo "$selected_file" | cut -d'_' -f2-)
            global_file=$(ls -1t "$BACKUP_DIR" | grep "globals_$timestamp_part" | head -1)
            if [ -n "$global_file" ]; then
                restore_globals "$BACKUP_DIR/$global_file"
            else
                echo "AVISO: Arquivo de globals não encontrado para este timestamp"
            fi
        fi

        # Restaurar bancos individuais
        timestamp_part=$(echo "$selected_file" | cut -d'_' -f2-)
        for file in "$BACKUP_DIR"/*"$timestamp_part"; do
            if echo "$file" | grep -vq "globals"; then
                restore_database "$file"
            fi
        done
        ;;
esac

echo "----------------------------------------"
echo "Restauração concluída com sucesso!"
echo "Verifique os logs acima para eventuais avisos"