#!/usr/bin/env bash
# Copias de Firestore de un entorno. Uso:
#   infra/backups/setup.sh prod escaque-prod
# prod: diaria con 14 días + recuperación a un minuto concreto (PITR, 7 días).
# qa:   semanal con 4 semanas.
set -euo pipefail
ENV_NAME=$1 PROJECT=$2
if [ "$ENV_NAME" = "prod" ]; then
  gcloud firestore backups schedules create --project="$PROJECT" --database='(default)' \
    --recurrence=daily --retention=14d
  gcloud firestore databases update --project="$PROJECT" --database='(default)' --enable-pitr
else
  gcloud firestore backups schedules create --project="$PROJECT" --database='(default)' \
    --recurrence=weekly --day-of-week=SUN --retention=4w
fi
gcloud firestore backups schedules list --project="$PROJECT" --database='(default)'
