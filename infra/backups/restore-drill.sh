#!/usr/bin/env bash
# Simulacro de restauración (cada trimestre). Restaura la última copia en una
# base de datos nueva, NUNCA sobre la de producción. Uso:
#   infra/backups/restore-drill.sh escaque-prod southamerica-east1
set -euo pipefail
PROJECT=$1 REGION=$2
DEST="restore-$(date +%Y%m%d)"
LAST=$(gcloud firestore backups list --project="$PROJECT" --location="$REGION" \
  --format='value(name)' --sort-by=~snapshotTime | head -1)
[ -n "$LAST" ] || { echo "No hay copias en $REGION"; exit 1; }
echo "Restaurando $LAST en la base $DEST…"
start=$(date +%s)
gcloud firestore databases restore --project="$PROJECT" --source-backup="$LAST" --destination-database="$DEST"
echo "Pedido en $(( $(date +%s) - start )) s. Comprueba en la consola (Firestore → $DEST) que hay"
echo "documentos en games y users, anota el tiempo total en la guía y borra la base:"
echo "  gcloud firestore databases delete --project=$PROJECT --database=$DEST"
