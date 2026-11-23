#!/usr/bin/env bash
#
# Módulo 00 — Cómo le hablás a AWS
#
# No crea recursos: te muestra el modelo de credenciales y endpoints que usan
# la CLI y todos los SDK. Es el módulo que te sirve para siempre, en cualquier
# lenguaje y contra AWS real.
#
#   ./labs/00-entorno.sh          # recorrido completo
#   ./labs/00-entorno.sh check    # idem (no hay nada que borrar)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

lab_up() {
  lab::title "1. A dónde apunta tu CLI"

  lab::step "Las cinco variables que redirigen la CLI al emulador"
  printf '\n'
  printf '   %-32s %s\n' "AWS_ENDPOINT_URL"          "${AWS_ENDPOINT_URL:-<sin definir>}"
  printf '   %-32s %s\n' "AWS_SHARED_CREDENTIALS_FILE" "${AWS_SHARED_CREDENTIALS_FILE:-<sin definir>}"
  printf '   %-32s %s\n' "AWS_CONFIG_FILE"           "${AWS_CONFIG_FILE:-<sin definir>}"
  printf '   %-32s %s\n' "AWS_CA_BUNDLE"             "${AWS_CA_BUNDLE:-<sin definir>}"
  printf '   %-32s %s\n' "AWS_REGION"                "${AWS_REGION:-<sin definir>}"
  printf '\n'
  lab::note "AWS_ENDPOINT_URL existe también en AWS real: es el override oficial"
  lab::note "del endpoint regional. Por eso el emulador no necesita un SDK especial."
  lab::note "AWS_CA_BUNDLE hace falta porque el emulador sirve HTTPS con cert autofirmado."

  lab::title "2. Quién sos para AWS"

  lab::step "aws sts get-caller-identity"
  local who
  who=$(aws sts get-caller-identity --output json)
  printf '\n%s\n\n' "$who"
  lab::note "Cuenta 000000000000 = la cuenta ficticia del emulador."
  lab::note "El ARN describe el principal: quién hace la llamada. IAM decide"
  lab::note "qué puede hacer ese principal — eso es el módulo 01."

  lab::title "3. De dónde salen las credenciales"

  local creds="${AWS_SHARED_CREDENTIALS_FILE:-}"
  if [ -r "$creds" ]; then
    lab::step "Archivo: $creds"
    printf '\n'
    sed 's/^\(aws_secret_access_key *= *\).*/\1<oculto>/' "$creds" | sed 's/^/   /'
    printf '\n'
    lab::note "El emulador genera un access key NUEVO en cada arranque."
    lab::note "Sirven solo para esta corrida: si reiniciás el contenedor, cambian."
  else
    lab::warn "no encuentro el archivo de credenciales en $creds"
  fi

  lab::title "4. El orden de precedencia (la trampa clásica)"

  lab::step "Probando qué pasa si una variable de entorno pisa el archivo"
  printf '\n'
  local out
  if out=$(AWS_ACCESS_KEY_ID=AKIAFALSO123456789AB \
           AWS_SECRET_ACCESS_KEY=secreto-inventado \
           aws sts get-caller-identity 2>&1); then
    lab::warn "la llamada funcionó igual — el emulador no validó la firma"
    printf '%s\n' "$out" | sed 's/^/   /'
  else
    lab::ok "la llamada FALLÓ, como tiene que ser:"
    printf '\n'
    printf '%s\n' "$out" | head -4 | sed 's/^/   /'
    printf '\n'
  fi
  lab::note "Las variables de entorno GANAN sobre el archivo de credenciales."
  lab::note "Por eso env.sh hace unset de AWS_PROFILE y AWS_ACCESS_KEY_ID/SECRET:"
  lab::note "si te quedaron de una sesión con AWS real, romperían todas las llamadas"
  lab::note "— y el error no dice 'tenés mal la variable', dice 'firma inválida'."
  printf '\n'
  lab::note "Precedencia, de mayor a menor:"
  lab::note "  1. variables de entorno        AWS_ACCESS_KEY_ID, ..."
  lab::note "  2. AWS_PROFILE                 perfil del archivo de config"
  lab::note "  3. archivo de credenciales     ~/.aws/credentials  [default]"
  lab::note "  4. rol del entorno             EC2/ECS/Lambda metadata"

  lab::title "5. Qué firma cada request"

  lab::step "Mirando la firma SigV4 con --debug"
  local sig
  sig=$(aws sts get-caller-identity --debug 2>&1 \
        | grep -m1 -o 'AWS4-HMAC-SHA256 Credential=[^,]*' || true)
  if [ -n "$sig" ]; then
    printf '\n   %s\n\n' "$sig"
    lab::note "Cada llamada a AWS va firmada con SigV4: método, host, path, headers,"
    lab::note "hash del body y timestamp. Por eso el reloj desincronizado rompe AWS,"
    lab::note "y por eso una URL prefirmada de S3 puede funcionar sin credenciales."
  else
    lab::warn "no pude capturar la línea de firma (no es grave)"
  fi

  lab::title "Para escribir"

  cat <<'TXT'
   Respondé en tus propias palabras, por escrito:

   1. ¿Por qué env.sh hace unset de AWS_PROFILE antes de exportar nada?
   2. ¿Qué pasa exactamente si quedó un AWS_PROFILE de una sesión con AWS real?
   3. ¿Para qué está AWS_CA_BUNDLE y qué error verías sin esa variable?
   4. ¿Por qué AWS_ENDPOINT_URL existe en el SDK real, si AWS ya tiene
      endpoints regionales fijos?

   Cuando puedas responder las cuatro sin mirar, pasá al módulo 01 (IAM).
TXT
  printf '\n'
}

lab_down() {
  lab::skip "el módulo 00 no crea recursos: no hay nada que borrar"
}

lab::main "$@"
