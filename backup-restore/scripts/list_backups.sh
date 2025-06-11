#!/bin/bash
# list_backups.sh - Lista backups disponíveis

BACKUP_DIR="${BACKUP_DIR:-/backups}"

# Listar arquivos .sql e .sql.gz com detalhes
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name "*.sql" -o -name "*.sql.gz" \) \
  -printf "%f %s %Tb %Td %TH:%TM\n" | sort -r