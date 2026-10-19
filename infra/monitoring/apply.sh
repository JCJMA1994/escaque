#!/usr/bin/env bash
# Crea (o recrea) las alertas de un entorno. Uso:
#   infra/monitoring/apply.sh qa escaque-qa api-escaque-qa.system-failed-tech.com tu@correo.com
set -euo pipefail
ENV_NAME=$1 PROJECT=$2 API_HOST=$3 EMAIL=$4
DIR=$(cd "$(dirname "$0")" && pwd)
gcloud config set project "$PROJECT" >/dev/null

# Canal de correo (reutiliza el que tenga el mismo nombre)
NAME="Escaque $ENV_NAME"
CHANNEL=$(gcloud beta monitoring channels list --filter="displayName=\"$NAME\"" --format='value(name)' | head -1)
if [ -z "$CHANNEL" ]; then
  CHANNEL=$(gcloud beta monitoring channels create --display-name="$NAME" --type=email \
    --channel-labels=email_address="$EMAIL" --format='value(name)')
fi
echo "Canal: $CHANNEL"

# Comprobación de disponibilidad de /healthz cada minuto desde varias regiones
UPTIME=$(gcloud monitoring uptime list-configs --filter="displayName=\"Escaque API $ENV_NAME\"" --format='value(name)' | head -1)
if [ -z "$UPTIME" ]; then
  UPTIME=$(gcloud monitoring uptime create "Escaque API $ENV_NAME" \
    --resource-type=uptime-url --resource-labels=host="$API_HOST",project_id="$PROJECT" \
    --protocol=https --path=/healthz --period=1 --timeout=10 \
    --matcher-content=ok --matcher-type=contains-string --format='value(name)')
fi
UPTIME_ID=${UPTIME##*/}
echo "Comprobación: $UPTIME_ID"

# Políticas: se borran las anteriores del mismo nombre y se crean de nuevo
for f in "$DIR"/policy-*.yaml; do
  tmp=$(mktemp)
  sed -e "s|__ENV__|$ENV_NAME|g" -e "s|__CHANNEL__|$CHANNEL|g" -e "s|__UPTIME_ID__|$UPTIME_ID|g" "$f" > "$tmp"
  display=$(grep -m1 '^displayName:' "$tmp" | sed 's/^displayName: *//; s/^"//; s/"$//')
  for old in $(gcloud alpha monitoring policies list --filter="displayName=\"$display\"" --format='value(name)'); do
    gcloud alpha monitoring policies delete "$old" --quiet
  done
  gcloud alpha monitoring policies create --policy-from-file="$tmp" --format='value(name)'
  rm "$tmp"
done
echo "Listo. Activa además en las consolas: Error Reporting (notificaciones) y Crashlytics (alertas)."
