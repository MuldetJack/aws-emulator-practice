#!/usr/bin/env bash
#
# Módulo 03 — DynamoDB: modelar para una app móvil
#
# El módulo que más te cambia la cabeza. En SQL modelás los datos y después
# escribís las consultas. En DynamoDB es al revés: primero escribís los
# patrones de acceso, y la tabla sale de ahí.
#
# Acá se construye UNA tabla que sirve a los cuatro patrones de una app de
# posts, sin un solo Scan.
#
#   ./labs/03-dynamodb.sh up | check | down

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PREFIJO="lab-ddb"
TABLA="$PREFIJO-app"

# --- helpers -----------------------------------------------------------------

# poner <pk> <sk> <json-de-atributos-extra>
poner() {
  local pk="$1" sk="$2" extra="${3:-}"
  local item="{\"pk\":{\"S\":\"$pk\"},\"sk\":{\"S\":\"$sk\"}"
  [ -n "$extra" ] && item="$item,$extra"
  item="$item}"
  aws dynamodb put-item --table-name "$TABLA" --item "$item"
}

# Muestra los items de una respuesta de query, en una línea cada uno.
mostrar() {
  python3 -c '
import json, sys
r = json.load(sys.stdin)
for it in r.get("Items", []):
    pk = it["pk"]["S"]
    sk = it["sk"]["S"]
    otros = {k: list(v.values())[0] for k, v in it.items() if k not in ("pk", "sk")}
    extra = "  ".join(f"{k}={v}" for k, v in sorted(otros.items()))
    print(f"        {pk:<12} {sk:<30} {extra}")
c = r.get("Count", 0)
s = r.get("ScannedCount", 0)
print(f"        -- Count={c}  ScannedCount={s}")
'
}

lab_up() {
  lab::title "1. Una sola tabla, dos claves genéricas"

  lab::idem "tabla $TABLA" \
    aws dynamodb create-table --table-name "$TABLA" \
      --attribute-definitions AttributeName=pk,AttributeType=S AttributeName=sk,AttributeType=S \
      --key-schema AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE \
      --billing-mode PAY_PER_REQUEST

  aws dynamodb wait table-exists --table-name "$TABLA"
  lab::ok "tabla activa"
  printf '\n'
  lab::note "Las claves se llaman 'pk' y 'sk', no 'user_id' ni 'post_id'. En"
  lab::note "single-table design una misma columna guarda cosas distintas según"
  lab::note "el tipo de item. Se siente mal al principio. Es correcto."

  lab::title "2. Cargando la app: usuarios, posts, comentarios y likes"

  lab::step "Perfiles         pk=USER#<id>   sk=PROFILE"
  poner "USER#ana"  "PROFILE" '"nombre":{"S":"Ana"},"seguidores":{"N":"120"}'  >/dev/null
  poner "USER#beto" "PROFILE" '"nombre":{"S":"Beto"},"seguidores":{"N":"47"}'  >/dev/null
  lab::ok "2 perfiles"

  lab::step "Posts            pk=USER#<id>   sk=POST#<fecha>#<id>"
  poner "USER#ana" "POST#2026-11-18T09:00#p1" '"texto":{"S":"primer post"}'  >/dev/null
  poner "USER#ana" "POST#2026-11-19T14:30#p2" '"texto":{"S":"segundo post"}' >/dev/null
  poner "USER#ana" "POST#2026-11-20T20:15#p3" '"texto":{"S":"tercer post"}'  >/dev/null
  poner "USER#beto" "POST#2026-11-19T11:00#p4" '"texto":{"S":"hola"}'        >/dev/null
  lab::ok "4 posts"

  lab::step "Comentarios      pk=POST#<id>   sk=COMMENT#<fecha>#<id>"
  poner "POST#p1" "COMMENT#2026-11-18T10:00#c1" '"autor":{"S":"beto"},"texto":{"S":"buenisimo"}' >/dev/null
  poner "POST#p1" "COMMENT#2026-11-18T11:30#c2" '"autor":{"S":"ana"},"texto":{"S":"gracias"}'    >/dev/null
  lab::ok "2 comentarios"

  lab::step "Likes            pk=POST#<id>   sk=LIKE#<usuario>"
  poner "POST#p1" "LIKE#beto" >/dev/null
  poner "POST#p3" "LIKE#beto" >/dev/null
  lab::ok "2 likes"
  printf '\n'
  lab::note "Fijate el truco: los posts cuelgan del usuario (pk=USER#) y los"
  lab::note "comentarios y likes cuelgan del post (pk=POST#). Cada patrón de"
  lab::note "acceso define de quién cuelga cada cosa."

  lab::title "3. Los cuatro patrones de acceso, sin un solo Scan"

  lab::step "A · Perfil de un usuario  ->  GetItem"
  printf '\n'
  aws dynamodb get-item --table-name "$TABLA" \
    --key '{"pk":{"S":"USER#ana"},"sk":{"S":"PROFILE"}}' \
    --query 'Item.[nombre.S,seguidores.N]' --output text \
    | awk '{printf "        nombre=%s  seguidores=%s\n", $1, $2}'
  printf '\n'
  lab::note "GetItem por clave completa: la operación más barata que existe."

  lab::step "B · Últimos 2 posts de ana, más nuevos primero  ->  Query"
  printf '\n'
  aws dynamodb query --table-name "$TABLA" \
    --key-condition-expression 'pk = :u AND begins_with(sk, :p)' \
    --expression-attribute-values '{":u":{"S":"USER#ana"},":p":{"S":"POST#"}}' \
    --no-scan-index-forward --limit 2 --output json | mostrar
  printf '\n'
  lab::note "Por qué funciona: la sk empieza con la fecha ISO, que ordena"
  lab::note "alfabéticamente igual que cronológicamente. --no-scan-index-forward"
  lab::note "lee el índice al revés. No hay 'ORDER BY': el orden ES el índice."

  lab::step "C · Comentarios de un post  ->  Query"
  printf '\n'
  aws dynamodb query --table-name "$TABLA" \
    --key-condition-expression 'pk = :p AND begins_with(sk, :c)' \
    --expression-attribute-values '{":p":{"S":"POST#p1"},":c":{"S":"COMMENT#"}}' \
    --output json | mostrar
  printf '\n'

  lab::step "D · ¿Beto likeó el post p1?  ->  GetItem"
  printf '\n'
  local like
  like=$(aws dynamodb get-item --table-name "$TABLA" \
         --key '{"pk":{"S":"POST#p1"},"sk":{"S":"LIKE#beto"}}' --query 'Item' --output json)
  if [ "$like" != "null" ]; then
    lab::ok "sí — y lo supimos con UNA lectura por clave, sin contar nada"
  else
    lab::warn "no"
  fi
  lab::note "En SQL esto sería un SELECT con WHERE sobre una tabla de likes."
  lab::note "Acá el like ES su propia clave: existe o no existe."

  lab::title "4. Query vs Scan: la diferencia que te va a costar plata"

  lab::step "Scan buscando los posts de ana (el modo equivocado)"
  printf '\n'
  aws dynamodb scan --table-name "$TABLA" \
    --filter-expression 'begins_with(sk, :p)' \
    --expression-attribute-values '{":p":{"S":"POST#"}}' --output json | mostrar
  printf '\n'
  lab::note "Mirá Count contra ScannedCount. Scan LEE TODA LA TABLA y después"
  lab::note "descarta: el filtro se aplica después de leer, y pagás lo leído."
  lab::note "Con 10 items no se nota. Con 10 millones, es la diferencia entre"
  lab::note "15 ms y un timeout — y entre centavos y una factura seria."
  lab::note "Regla: si tu pantalla necesita un Scan, el modelo está mal."

  lab::title "Para escribir"

  cat <<'TXT'
   1. Agregá este patrón: "traer los seguidores de un usuario". ¿Qué pk y
      qué sk usás? ¿Hace falta una tabla nueva? (No.)
   2. "Traer el feed global, los 20 posts más nuevos de TODOS los usuarios."
      Con esta tabla no se puede sin Scan. ¿Por qué? ¿Qué GSI lo resuelve?
   3. ¿Qué pasa si un post se hace viral y recibe 10 millones de likes,
      todos con pk=POST#p1? Buscá "hot partition".
   4. Volvé a tu respuesta del módulo 01, punto 4: escribí la policy IAM
      mínima para una Lambda que solo hace los accesos A, B, C y D.
      Pista: dynamodb:Query y dynamodb:GetItem, sobre el ARN de esta tabla.

   Después: ./labs/03-dynamodb.sh down
TXT
  printf '\n'
}

lab_check() {
  lab::title "Estado de $PREFIJO"
  local estado
  if estado=$(aws dynamodb describe-table --table-name "$TABLA" \
              --query 'Table.TableStatus' --output text 2>/dev/null); then
    lab::ok "tabla $TABLA  ($estado)"
    lab::note "No muestro ItemCount a propósito: DynamoDB lo actualiza cada ~6 h,"
    lab::note "así que casi siempre miente. Para contar de verdad hay que leer."
  else
    lab::warn "tabla $TABLA no existe — corré: $(basename "$0") up"
  fi
}

lab_down() {
  lab::title "Borrando $PREFIJO"
  lab::rm "tabla $TABLA" aws dynamodb delete-table --table-name "$TABLA"
}

lab::main "$@"
