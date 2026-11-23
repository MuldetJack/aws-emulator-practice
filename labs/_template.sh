#!/usr/bin/env bash
#
# Plantilla para los labs 01 en adelante.
#
#   cp labs/_template.sh labs/01-iam.sh
#
# Este archivo CORRE tal cual: crea un bucket y una cola de ejemplo, para que
# veas el patrón funcionando antes de escribir el tuyo.
#
#   ./labs/_template.sh up      # crea (dos veces seguidas: no explota)
#   ./labs/_template.sh check   # verifica que esté todo
#   ./labs/_template.sh down    # borra
#
# Las tres reglas del patrón:
#   1. Idempotente — correrlo dos veces da el mismo resultado.
#   2. Imprime lo que creó.
#   3. Sabe borrarse, porque el emulador pierde todo al reiniciar.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Prefijo propio por lab: así cada módulo borra lo suyo y nada más.
PREFIJO="lab-template"
BUCKET="$PREFIJO-media"
COLA="$PREFIJO-trabajos"

lab_up() {
  lab::title "Creando recursos de $PREFIJO"

  lab::step "Bucket S3"
  lab::idem "bucket $BUCKET" \
    aws s3api create-bucket --bucket "$BUCKET"

  lab::step "Cola SQS"
  lab::idem "cola $COLA" \
    aws sqs create-queue --queue-name "$COLA"

  lab_check
}

lab_check() {
  lab::title "Estado"

  local url
  if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
    lab::ok "bucket   s3://$BUCKET"
  else
    lab::warn "bucket   $BUCKET no existe — corré: $(basename "$0") up"
  fi

  if url=$(aws sqs get-queue-url --queue-name "$COLA" --query QueueUrl --output text 2>/dev/null); then
    lab::ok "cola     $url"
  else
    lab::warn "cola     $COLA no existe — corré: $(basename "$0") up"
  fi
}

lab_down() {
  lab::title "Borrando recursos de $PREFIJO"

  local url
  if url=$(aws sqs get-queue-url --queue-name "$COLA" --query QueueUrl --output text 2>/dev/null); then
    lab::rm "cola $COLA" aws sqs delete-queue --queue-url "$url"
  else
    lab::skip "cola $COLA no estaba"
  fi

  # Un bucket con objetos no se puede borrar: primero se vacía.
  if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
    aws s3 rm "s3://$BUCKET" --recursive >/dev/null 2>&1 || true
    lab::rm "bucket $BUCKET" aws s3api delete-bucket --bucket "$BUCKET"
  else
    lab::skip "bucket $BUCKET no estaba"
  fi
}

lab::main "$@"
