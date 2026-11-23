#!/usr/bin/env bash
#
# Módulo 02 — S3 y la URL prefirmada
#
# La pieza de S3 que define la arquitectura de una app móvil: el teléfono sube
# la foto DIRECTO a S3 con una URL temporal, sin que el archivo pase nunca por
# tu backend. Menos costo, menos latencia, menos código.
#
#   ./labs/02-s3.sh up | check | down

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PREFIJO="lab-s3"
BUCKET="$PREFIJO-media"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Llama al firmador sin credenciales en el entorno, para dejar claro que la
# URL prefirmada se usa SIN ellas: la firma ya viaja adentro.
sin_credenciales() {
  env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN "$@"
}

lab_up() {
  lab::title "1. Un bucket no tiene carpetas"

  lab::idem "bucket $BUCKET" aws s3api create-bucket --bucket "$BUCKET"

  printf 'perfil de ana\n'  > "$TMP/ana.txt"
  printf 'perfil de beto\n' > "$TMP/beto.txt"
  printf 'post numero 1\n'  > "$TMP/post1.txt"

  lab::step "Subiendo tres objetos con 'rutas'"
  aws s3 cp "$TMP/ana.txt"   "s3://$BUCKET/usuarios/ana/perfil.txt"  >/dev/null
  aws s3 cp "$TMP/beto.txt"  "s3://$BUCKET/usuarios/beto/perfil.txt" >/dev/null
  aws s3 cp "$TMP/post1.txt" "s3://$BUCKET/posts/1.txt"              >/dev/null
  lab::ok "3 objetos subidos"

  lab::step "Listado plano: esas 'carpetas' son parte del nombre"
  printf '\n'
  aws s3api list-objects-v2 --bucket "$BUCKET" --query 'Contents[].Key' --output text \
    | tr '\t' '\n' | sed 's/^/        /'
  printf '\n'
  lab::note "No existe el directorio usuarios/. El objeto se llama literalmente"
  lab::note "'usuarios/ana/perfil.txt'. La barra es un carácter más del nombre."

  lab::step "Delimiter: así se simula una carpeta"
  printf '\n'
  aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "usuarios/" --delimiter "/" \
    --query 'CommonPrefixes[].Prefix' --output text | tr '\t' '\n' | sed 's/^/        /'
  printf '\n'
  lab::note "La consola de AWS te dibuja carpetas haciendo exactamente esto."
  lab::note "Consecuencia práctica: elegí bien el prefijo, porque es tu único"
  lab::note "índice. 'usuarios/<id>/...' se lista barato; 'foto-<id>.jpg' no."

  lab::title "2. URL prefirmada de BAJADA (GET)"

  local url_get
  url_get=$(aws s3 presign "s3://$BUCKET/posts/1.txt" --expires-in 300)
  lab::ok "generada, válida 300 s"
  printf '\n        %s\n\n' "$(printf '%s' "$url_get" | cut -c1-96)…"

  lab::step "Usándola SIN credenciales"
  local cuerpo
  cuerpo=$(sin_credenciales curl -sk "$url_get")
  lab::ok "contenido recibido: $cuerpo"
  lab::note "La firma va en la query string (X-Amz-Signature). Cualquiera con"
  lab::note "esa URL puede leer ese objeto hasta que expire: trátala como un"
  lab::note "secreto de corta vida, no la guardes en logs ni en la DB."

  lab::title "3. URL prefirmada de SUBIDA (PUT) — el flujo móvil"

  lab::note "'aws s3 presign' SOLO firma GET. Para subir hace falta firmar un PUT,"
  lab::note "que en producción hace el SDK. labs/tools/presign-put.mjs lo hace a"
  lab::note "mano con node:crypto para que veas la anatomía de la firma."
  printf '\n'

  local url_put
  url_put=$(node "$LAB_ROOT/labs/tools/presign-put.mjs" "$BUCKET" "usuarios/ana/foto.jpg" 300)
  lab::ok "PUT prefirmado generado"

  printf 'bytes de una foto\n' > "$TMP/foto.jpg"
  lab::step "El 'teléfono' sube, sin credenciales de AWS"
  local codigo
  codigo=$(sin_credenciales curl -sk -o /dev/null -w '%{http_code}' \
           -X PUT --upload-file "$TMP/foto.jpg" "$url_put")
  if [ "$codigo" = "200" ]; then
    lab::ok "HTTP $codigo — el objeto entró directo a S3"
  else
    lab::warn "HTTP $codigo — la subida falló"
  fi

  lab::step "Verificando desde el lado del backend"
  aws s3api head-object --bucket "$BUCKET" --key "usuarios/ana/foto.jpg" \
    --query '{bytes:ContentLength,modificado:LastModified}' --output text \
    | sed 's/^/        /'

  lab::title "4. La firma es de UNA operación sobre UN objeto"

  lab::step "Reusando la URL de ana para escribir en la clave de beto"
  local salida
  salida=$(sin_credenciales curl -sk -X PUT --upload-file "$TMP/foto.jpg" \
           "${url_put/ana/beto}" 2>&1 || true)
  if printf '%s' "$salida" | grep -q 'SignatureDoesNotMatch\|AccessDenied'; then
    lab::ok "RECHAZADO: la ruta es parte de lo que se firmó"
  else
    lab::warn "la aceptó — revisá el resultado"
  fi
  printf '\n'
  lab::note "Por eso una presigned URL es segura de entregar: no es una llave del"
  lab::note "bucket, es un permiso para hacer UNA cosa en UN lugar hasta una hora."

  lab::title "5. Y caduca"

  lab::step "Generando una válida 1 segundo y esperando 2"
  local url_corta
  url_corta=$(aws s3 presign "s3://$BUCKET/posts/1.txt" --expires-in 1)
  sleep 2
  if sin_credenciales curl -sk "$url_corta" | grep -q 'AccessDenied\|Expired'; then
    lab::ok "EXPIRADA — AccessDenied, como corresponde"
  else
    lab::warn "siguió funcionando; el emulador puede ser laxo con el reloj"
  fi
  printf '\n'
  lab::note "X-Amz-Expires viaja firmado: nadie puede estirarlo editando la URL."

  lab::title "Para escribir"

  cat <<'TXT'
   1. ¿Por qué conviene que el teléfono suba a S3 directo y no a tu API?
      Pensá en costo, latencia, memoria del backend y tamaño de archivo.
   2. Si la URL prefirmada se filtra, ¿qué puede hacer quien la tenga?
      ¿Y qué NO puede hacer?
   3. Tu app sube fotos de perfil. ¿Qué expiración le ponés y por qué?
   4. Diseñá el esquema de claves (keys) para fotos de perfil y adjuntos
      de posts. ¿Qué prefijo te deja listar lo de un usuario barato?
   5. Abrí labs/tools/presign-put.mjs y seguí la derivación de la clave:
      AWS4<secreto> -> fecha -> región -> s3 -> aws4_request.
      ¿Por qué AWS la deriva así en vez de firmar con el secreto directo?

   Pista para la 5: pensá qué puede hacer alguien que roba una clave derivada.

   Después: ./labs/02-s3.sh down
TXT
  printf '\n'
}

lab_check() {
  lab::title "Estado de $PREFIJO"
  if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
    lab::ok "bucket s3://$BUCKET"
    aws s3api list-objects-v2 --bucket "$BUCKET" --query 'Contents[].Key' --output text 2>/dev/null \
      | tr '\t' '\n' | sed '/^$/d;s/^/        /'
  else
    lab::warn "bucket $BUCKET no existe — corré: $(basename "$0") up"
  fi
}

lab_down() {
  lab::title "Borrando $PREFIJO"
  if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
    aws s3 rm "s3://$BUCKET" --recursive >/dev/null 2>&1 || true
    lab::rm "bucket $BUCKET" aws s3api delete-bucket --bucket "$BUCKET"
  else
    lab::skip "bucket $BUCKET no estaba"
  fi
}

lab::main "$@"
