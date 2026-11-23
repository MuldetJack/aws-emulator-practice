#!/usr/bin/env bash
#
# Módulo 01 — IAM
#
# El servicio que más veces te va a bloquear en la vida. Este lab construye el
# modelo mental completo en una corrida:
#
#   trust policy      ->  QUIÉN puede asumir el rol
#   permission policy ->  QUÉ puede hacer una vez adentro
#
# El emulador evalúa permisos de verdad: vas a ver AccessDenied reales.
#
#   ./labs/01-iam.sh up      # crea el rol y corre las demostraciones
#   ./labs/01-iam.sh check   # muestra el estado del rol
#   ./labs/01-iam.sh down    # borra todo

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PREFIJO="lab-iam"
ROL="$PREFIJO-lector"
ROL_AJENO="$PREFIJO-solo-lambda"
BUCKET="$PREFIJO-datos"
POLICY="permisos"
CUENTA="000000000000"

# Confía en la propia cuenta: cualquier principal de la cuenta puede asumirlo.
TRUST_CUENTA='{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Principal":{"AWS":"arn:aws:iam::'"$CUENTA"':root"},"Action":"sts:AssumeRole"}]}'

# Confía SOLO en el servicio Lambda. Un usuario no puede asumirlo.
TRUST_LAMBDA='{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

# Permisos de arranque: mirar, nada más.
PERM_LECTURA='{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Action":["s3:ListBucket","s3:ListAllMyBuckets"],"Resource":"*"}]}'

# Permisos ampliados: además, escribir dentro de ESE bucket y de ninguno más.
perm_escritura() {
  printf '%s' '{"Version":"2012-10-17","Statement":[
    {"Effect":"Allow","Action":["s3:ListBucket","s3:ListAllMyBuckets"],"Resource":"*"},
    {"Effect":"Allow","Action":"s3:PutObject","Resource":"arn:aws:s3:::'"$BUCKET"'/*"}]}'
}

# ---------------------------------------------------------------- helpers

# Pide credenciales temporales del rol y las deja en AWS_* del entorno actual.
asumir() {
  local arn="$1" sesion="$2" out
  out=$(aws sts assume-role --role-arn "$arn" --role-session-name "$sesion" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text) || return 1
  IFS=$'\t' read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<<"$out"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

# Corre un comando con el rol asumido, en una subshell para no contaminar la shell.
con_rol() (
  asumir "arn:aws:iam::$CUENTA:role/$ROL" "lab" >/dev/null || exit 1
  "$@"
)

# Muestra si un comando fue permitido o denegado, y por qué.
probar() {
  local etiqueta="$1"; shift
  local out status=0
  out=$(con_rol "$@" 2>&1) || status=$?
  if [ $status -eq 0 ]; then
    lab::ok "PERMITIDO  $etiqueta"
  else
    lab::warn "DENEGADO   $etiqueta"
    printf '%s\n' "$out" | grep -o 'is not authorized to perform:.*' | head -1 | sed 's/^/        /'
  fi
}

# ---------------------------------------------------------------- lab

lab_up() {
  lab::title "1. Un rol tiene DOS políticas, y hacen cosas distintas"

  lab::step "Rol $ROL — trust policy: confía en la cuenta $CUENTA"
  lab::idem "rol $ROL" \
    aws iam create-role --role-name "$ROL" --assume-role-policy-document "$TRUST_CUENTA"

  lab::step "Permission policy inicial: solo puede MIRAR"
  aws iam put-role-policy --role-name "$ROL" --policy-name "$POLICY" \
    --policy-document "$PERM_LECTURA"
  lab::ok "policy $POLICY aplicada (s3:ListBucket, s3:ListAllMyBuckets)"

  lab::step "Bucket de prueba, creado por vos (el admin), no por el rol"
  lab::idem "bucket $BUCKET" aws s3api create-bucket --bucket "$BUCKET"

  lab::title "2. Asumir el rol: dejás de ser vos"

  lab::step "aws sts assume-role"
  local yo quien
  yo=$(aws sts get-caller-identity --query Arn --output text)
  quien=$(con_rol aws sts get-caller-identity --query Arn --output text)
  printf '\n'
  printf '   %-8s %s\n' "antes" "$yo"
  printf '   %-8s %s\n' "ahora" "$quien"
  printf '\n'
  lab::note "El ARN pasa de iam::user a sts::assumed-role/<rol>/<sesión>: ya no sos"
  lab::note "un usuario, sos una sesión temporal del rol."
  lab::note "Las credenciales son temporales y caducan solas. Así funciona TODO en"
  lab::note "AWS real: una Lambda, un pod de EKS o una EC2 no tienen access keys"
  lab::note "guardadas — asumen un rol exactamente así, por detrás."

  lab::title "3. Qué puede y qué no puede hacer el rol"

  probar "s3:ListAllMyBuckets  (listar buckets)"      aws s3 ls
  probar "s3:PutObject         (subir un archivo)"    aws s3 cp "$0" "s3://$BUCKET/prueba.txt"
  probar "dynamodb:ListTables  (otro servicio)"       aws dynamodb list-tables
  printf '\n'
  lab::note "Leé el mensaje de DENEGADO: dice el principal, la acción, el recurso"
  lab::note "y el motivo. En AWS real ese texto es tu herramienta de debug nº1."
  lab::note "«no identity-based policy allows» = falta el permiso, no está denegado"
  lab::note "explícitamente. Un Deny explícito gana siempre sobre cualquier Allow."

  lab::title "4. Ampliar el permiso: menor privilegio en acción"

  lab::step "Agregando s3:PutObject SOLO sobre arn:aws:s3:::$BUCKET/*"
  aws iam put-role-policy --role-name "$ROL" --policy-name "$POLICY" \
    --policy-document "$(perm_escritura)"
  lab::ok "policy actualizada"
  printf '\n'

  probar "s3:PutObject         en $BUCKET"        aws s3 cp "$0" "s3://$BUCKET/prueba.txt"
  probar "s3:PutObject         en OTRO bucket"    aws s3 cp "$0" "s3://lab-test/prueba.txt"
  printf '\n'
  lab::note "Mismo permiso, distinto Resource. Eso es menor privilegio: no alcanza"
  lab::note "con decir 'puede escribir en S3', hay que decir DÓNDE."
  lab::note "No hizo falta volver a asumir el rol: IAM evalúa las políticas en cada"
  lab::note "request, no al momento de emitir las credenciales."

  lab::title "5. La trust policy decide quién entra"

  lab::step "Rol $ROL_AJENO — trust policy: solo el servicio Lambda"
  lab::idem "rol $ROL_AJENO" \
    aws iam create-role --role-name "$ROL_AJENO" --assume-role-policy-document "$TRUST_LAMBDA"

  lab::step "Intentando asumirlo como usuario"
  local out
  if out=$(aws sts assume-role --role-arn "arn:aws:iam::$CUENTA:role/$ROL_AJENO" \
           --role-session-name intruso 2>&1); then
    lab::warn "lo asumió igual — el emulador no evaluó la trust policy acá"
  else
    lab::ok "RECHAZADO, como tiene que ser:"
    printf '%s\n' "$out" | grep -o 'An error occurred.*' | head -1 | sed 's/^/        /'
  fi
  printf '\n'
  lab::note "Son dos puertas distintas y las dos tienen que abrirse:"
  lab::note "  trust policy       -> ¿quién sos? ¿tenés derecho a entrar?"
  lab::note "  permission policy  -> ya adentro, ¿qué podés tocar?"
  lab::note "El 90% de los '¿por qué no puedo?' en AWS es una de estas dos."

  lab::title "Para escribir"

  cat <<'TXT'
   1. ¿Por qué una Lambda necesita un rol y no un usuario con access keys?
   2. Tenés un Allow de s3:* y un Deny de s3:DeleteObject. ¿Qué pasa?
   3. ¿Por qué el paso 4 funcionó sin volver a asumir el rol?
   4. Escribí la policy mínima para una Lambda que SOLO lee de una tabla
      DynamoDB llamada Posts y escribe en el bucket app-media.

   Después: ./labs/01-iam.sh down
TXT
  printf '\n'
}

lab_check() {
  lab::title "Estado de $PREFIJO"

  local r
  for r in "$ROL" "$ROL_AJENO"; do
    if aws iam get-role --role-name "$r" >/dev/null 2>&1; then
      lab::ok "rol      $r"
      aws iam list-role-policies --role-name "$r" --query 'PolicyNames' --output text 2>/dev/null \
        | tr '\t' '\n' | sed '/^$/d;s/^/        policy: /'
    else
      lab::warn "rol      $r no existe — corré: $(basename "$0") up"
    fi
  done

  if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
    lab::ok "bucket   s3://$BUCKET"
  else
    lab::warn "bucket   $BUCKET no existe"
  fi
}

lab_down() {
  lab::title "Borrando $PREFIJO"

  # Un rol con políticas inline pegadas no se puede borrar: primero se despegan.
  if aws iam get-role --role-name "$ROL" >/dev/null 2>&1; then
    aws iam delete-role-policy --role-name "$ROL" --policy-name "$POLICY" >/dev/null 2>&1 || true
  fi
  lab::rm "rol $ROL"       aws iam delete-role --role-name "$ROL"
  lab::rm "rol $ROL_AJENO" aws iam delete-role --role-name "$ROL_AJENO"

  if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
    aws s3 rm "s3://$BUCKET" --recursive >/dev/null 2>&1 || true
    lab::rm "bucket $BUCKET" aws s3api delete-bucket --bucket "$BUCKET"
  else
    lab::skip "bucket $BUCKET no estaba"
  fi
}

lab::main "$@"
