#!/usr/bin/env bash
# Helpers compartidos por los labs.
#
# No se ejecuta solo: lo sourcean los scripts labs/NN-*.sh
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------- salida

if [ -t 1 ]; then
  _C_DIM=$'\033[2m'; _C_B=$'\033[1m'; _C_OK=$'\033[32m'
  _C_WARN=$'\033[33m'; _C_ERR=$'\033[31m'; _C_OFF=$'\033[0m'
else
  _C_DIM=""; _C_B=""; _C_OK=""; _C_WARN=""; _C_ERR=""; _C_OFF=""
fi

lab::title() { printf '\n%s== %s ==%s\n\n' "$_C_B" "$*" "$_C_OFF"; }
lab::step()  { printf '%s->%s %s\n' "$_C_B" "$_C_OFF" "$*"; }
lab::ok()    { printf '   %sok%s   %s\n' "$_C_OK" "$_C_OFF" "$*"; }
lab::skip()  { printf '   %s--%s   %s\n' "$_C_DIM" "$_C_OFF" "$*"; }
lab::warn()  { printf '   %swarn%s %s\n' "$_C_WARN" "$_C_OFF" "$*"; }
lab::die()   { printf '\n%serror:%s %s\n\n' "$_C_ERR" "$_C_OFF" "$*" >&2; exit 1; }
lab::note()  { printf '   %s%s%s\n' "$_C_DIM" "$*" "$_C_OFF"; }

# ---------------------------------------------------------------- entorno

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Deja la shell apuntando al emulador. Idempotente: si ya está apuntado, no hace nada.
lab::env() {
  [ -n "${AWS_ENDPOINT_URL:-}" ] && return 0

  # env.sh está pensado para una shell interactiva y lee variables que pueden
  # no existir, así que se sourcea con `set -u` apagado y luego se restaura.
  local had_u=0
  case "$-" in *u*) had_u=1; set +u ;; esac

  local rc=0
  # shellcheck disable=SC1091
  source "$LAB_ROOT/env.sh" "" >/dev/null || rc=$?

  [ "$had_u" -eq 1 ] && set -u
  [ "$rc" -eq 0 ] || lab::die "no pude cargar env.sh — ¿está arriba el emulador? (docker compose up -d)"
}

# Falla con un mensaje útil si el emulador no responde.
lab::require_emulator() {
  lab::env
  command -v aws >/dev/null || lab::die "no encuentro la AWS CLI en el PATH"
  aws sts get-caller-identity >/dev/null 2>&1 \
    || lab::die "el emulador no responde en ${AWS_ENDPOINT_URL:-?} — probá: docker compose up -d"
}

# ---------------------------------------------------------------- idempotencia

# Corre un comando de creación y tolera que el recurso ya exista.
#
#   lab::idem "bucket lab-media" aws s3api create-bucket --bucket lab-media
#
# Esto es lo que hace idempotente a un script: volver a correrlo no debe fallar.
#
# Ojo, lección de AWS: no todas las APIs de creación se comportan igual.
#   - S3 create-bucket y SQS create-queue devuelven 200 si ya existe (son
#     idempotentes por diseño) — por eso vas a ver "listo" y no "ya existía".
#   - IAM create-role, DynamoDB create-table y Lambda create-function tiran
#     EntityAlreadyExists / ResourceInUseException / ResourceConflictException.
# Esta función normaliza las dos familias para que tu script no se caiga.
lab::idem() {
  local what="$1"; shift
  # Con `set -e` en el script que llama, una asignación que falla aborta todo.
  # El `|| status=$?` es lo que permite inspeccionar el error en vez de morir.
  local out status=0
  out="$("$@" 2>&1)" || status=$?

  if [ $status -eq 0 ]; then
    lab::ok "$what listo"
    return 0
  fi

  case "$out" in
    *AlreadyExists*|*EntityAlreadyExists*|*BucketAlreadyOwnedByYou*|\
    *ResourceInUseException*|*ResourceConflictException*|*QueueAlreadyExists*)
      lab::skip "$what ya existía"
      return 0
      ;;
  esac

  printf '%s\n' "$out" >&2
  lab::die "falló al crear $what"
}

# Igual, pero para borrar: tolera que el recurso ya no esté.
lab::rm() {
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then
    lab::ok "$what borrado"
  else
    lab::skip "$what no estaba"
  fi
}

# ---------------------------------------------------------------- subcomandos

# Despacha up/down/check. Cada lab define lab_up, lab_down y (opcional) lab_check.
lab::main() {
  local cmd="${1:-up}"
  case "$cmd" in
    up)    lab::require_emulator; lab_up ;;
    down)  lab::require_emulator; lab_down ;;
    check) lab::require_emulator; if declare -F lab_check >/dev/null; then lab_check; else lab_up; fi ;;
    *)     echo "uso: $(basename "$0") [up|down|check]" >&2; exit 2 ;;
  esac
}
