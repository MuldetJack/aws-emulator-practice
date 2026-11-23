# Plan de aprendizaje — AWS para backend móvil

Objetivo: entender y poder construir el lado servidor de una app móvil en AWS.
Ritmo: 10+ h/semana, ~5 semanas. Laboratorio: el emulador de este repo, sin cuenta real.

Todo lo que aparece acá fue **probado contra el emulador** (v1.0.471, aarch64) antes
de escribirse. Lo que no funciona está marcado como tal.

---

## Cómo trabajar

**Regla única e innegociable: cada ejercicio se escribe como script, no como comandos sueltos.**

El estado del emulador vive en RAM. Un `docker compose down`, un `restart` o un OOM
(exit 137) borra todo. Eso no es una molestia: es el mejor hábito de cloud metido a la
fuerza. Si tu entorno no se reconstruye con un comando, no existe.

Los scripts viven en [`labs/`](labs/). El módulo 00 ya está escrito y corriendo
(`./labs/00-entorno.sh`), y `labs/_template.sh` es la plantilla para los demás —
también corre tal cual, para que veas el patrón antes de escribir el tuyo.

Cada módulo deja un script en `labs/NN-nombre.sh` que:

1. Es **idempotente** — lo corrés dos veces y no explota.
2. Imprime lo que creó.
3. Tiene un `destroy` al final o un script hermano.

Esto reemplaza a CloudFormation/CDK, que acá **no sirven** (24% de fidelidad).

### Arranque de cada sesión

```bash
docker compose up -d
source ./env.sh
aws sts get-caller-identity     # debe devolver la cuenta 000000000000
```

Si `env.sh` se queja, el emulador no está arriba o todavía no escribió las credenciales.

### Reparto del tiempo por sesión

| 20% | Leer el concepto (docs de AWS real, no del emulador) |
| 60% | CLI: romperlo, leer el error, arreglarlo |
| 20% | Escribir en tu propio README qué entendiste |

El 20% final es el que convierte práctica en conocimiento. No lo saltees.

---

## Semana 1 — Identidad, permisos y datos

### Módulo 0 · El modelo de comunicación con AWS (2 h)

Antes de tocar un servicio, entendé **cómo** le hablás a AWS. Es lo que te va a
servir para siempre, en cualquier SDK y cualquier lenguaje.

Conceptos: endpoint regional · región · credenciales (access key + secret + session
token) · firma SigV4 · el orden de precedencia de credenciales.

Ejercicio: leé `env.sh` línea por línea y respondé por escrito:

- ¿Por qué hace `unset AWS_PROFILE AWS_ACCESS_KEY_ID ...`?
- ¿Qué pasa si quedó un `AWS_PROFILE` de una sesión con AWS real?
- ¿Para qué está `AWS_CA_BUNDLE`?
- ¿Qué es `AWS_ENDPOINT_URL` y por qué existe esa variable en el SDK real?

Ese archivo es un mapa del modelo de credenciales de AWS. Entenderlo vale más que
diez tutoriales.

### Módulo 1 · IAM — el concepto central (6 h)

IAM es el servicio que más veces te va a bloquear en tu vida. **El emulador lo
valida de verdad**, así que se puede aprender acá.

Conceptos: usuario vs rol · *trust policy* (quién puede asumir el rol) vs *permission
policy* (qué puede hacer) · policies administradas vs inline · `sts:AssumeRole` ·
rol de ejecución vs resource policy · menor privilegio.

Ejercicio verificado — la lección de IAM en tres comandos:

```bash
# 1. Rol con trust policy para Lambda, SIN permisos
aws iam create-role --role-name lab-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

# 2. Intentar conectar SQS -> Lambda  =>  FALLA
#    "The function execution role does not have permissions to call ReceiveMessage on SQS"

# 3. Dar el permiso  =>  funciona
aws iam attach-role-policy --role-name lab-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole
```

Si entendés por qué el paso 2 falla, entendiste IAM. Escribí la explicación.

### Módulo 2 · S3 — archivos y la URL prefirmada (5 h)

Conceptos: bucket · key · prefijo (no hay carpetas) · clases de almacenamiento ·
versionado · eventos de bucket · **presigned URL**.

La presigned URL es *la* pieza de S3 para móvil: el teléfono sube la foto directo a
S3 con una URL temporal, sin que el archivo pase por tu backend. Verificado:

```bash
aws s3 mb s3://lab-media
aws s3 presign s3://lab-media/foto.jpg --expires-in 300
# => https://127.0.0.1:9297/lab-media/foto.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256&...
```

Ejercicio: una Lambda que recibe `{"filename":"x.jpg"}` y devuelve una URL de subida
prefirmada. Ese es el endpoint real de "subir foto de perfil" de cualquier app.

### Módulo 3 · DynamoDB — modelar para una app móvil (7 h)

El módulo más difícil del plan y el que más cambia tu forma de pensar.

Conceptos: partition key y sort key · por qué **no** se modela como SQL · patrones de
acceso primero, tabla después · `Query` vs `Scan` (y por qué `Scan` es casi siempre un
error) · GSI · single-table design · capacidad on-demand vs provisionada.

Ejercicio: modelá una app de posts con estos patrones de acceso, en **una sola tabla**:

- traer el perfil de un usuario
- traer los últimos 20 posts de un usuario, más nuevos primero
- traer los comentarios de un post
- saber si el usuario X likeó el post Y

Escribí primero el diseño de PK/SK en papel. Después creá la tabla y cargá datos.
Si necesitás un `Scan` para alguno, el modelo está mal.

---

## Semana 2 — Cómputo y la API

### Módulo 4 · Lambda (8 h)

**Verificado: el emulador ejecuta código Node de verdad.** No es un stub.

Conceptos: handler · objeto `event` y `context` · runtimes · memoria y timeout · cold
start · concurrencia · variables de entorno · versiones y alias · los dos permisos
distintos (rol de ejecución vs quién puede invocarla).

Gotcha verificado: después de `create-function` la función queda en `Pending` y el
invoke falla con `ResourceConflictException`. Igual que en AWS real. Siempre:

```bash
aws lambda wait function-active --function-name lab-fn
```

Ejercicio: Lambda en Node 20 que lee y escribe en la tabla DynamoDB del módulo 3,
con el rol correcto y nada más que eso (menor privilegio).

Nota: los logs llegan a CloudWatch Logs (`/aws/lambda/<fn>`), pero la observabilidad
del emulador es floja. No inviertas tiempo en métricas y alarmas acá.

### Módulo 5 · API Gateway — exponer la API al teléfono (8 h)

Conceptos: HTTP API vs REST API (para móvil, casi siempre HTTP API) · integración
proxy y la **forma exacta** del evento y la respuesta · rutas · stages · CORS ·
authorizers.

Verificado. El endpoint del emulador tiene forma propia:

```bash
API=$(aws apigatewayv2 create-api --name lab-api --protocol-type HTTP \
  --target arn:aws:lambda:us-east-1:000000000000:function:lab-fn \
  --query ApiId --output text)

# SIN esto, toda llamada devuelve 500 "Internal Server Error":
aws lambda add-permission --function-name lab-fn --statement-id apigw \
  --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:us-east-1:000000000000:$API/*/*/*"

curl -sk "https://127.0.0.1:9297/_aws/execute-api/$API/"
```

Ese 500 es el error más común de API Gateway en AWS real y acá lo reproducís exacto.
La lección: `create-api --target` crea la integración pero **no** el permiso de invocación.

Ejercicio: API con rutas `GET /posts`, `POST /posts`, `GET /posts/{id}`, cada una
contra una Lambda, leyendo y escribiendo en DynamoDB.

---

## Semana 3 — Autenticación

### Módulo 6 · Cognito (10 h)

El servicio que define la experiencia de login de tu app. **Verificado: el emulador
emite JWT RS256 reales y publica JWKS**, así que se puede aprender el flujo completo,
incluida la verificación de firma.

Conceptos: user pool (quién sos) vs identity pool (a qué recursos AWS accedés) ·
app client · flujos de auth (`USER_PASSWORD_AUTH`, SRP, refresh) · **ID token vs
access token vs refresh token** y cuál manda tu app en cada caso · claims · JWKS y
rotación de claves · grupos · atributos custom · triggers de Lambda.

Verificado de punta a punta:

```bash
POOL=$(aws cognito-idp create-user-pool --pool-name lab-pool --query UserPool.Id --output text)
CLIENT=$(aws cognito-idp create-user-pool-client --user-pool-id $POOL --client-name app \
  --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
  --query UserPoolClient.ClientId --output text)

aws cognito-idp sign-up --client-id $CLIENT --username yo@example.com --password 'Passw0rd!2026'
aws cognito-idp admin-confirm-sign-up --user-pool-id $POOL --username yo@example.com
aws cognito-idp initiate-auth --client-id $CLIENT --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=yo@example.com,PASSWORD='Passw0rd!2026'

# Las claves públicas para verificar la firma del token:
curl -sk "https://127.0.0.1:9297/$POOL/.well-known/jwks.json"
```

Ejercicio clave: pegá el ID token en jwt.io y leé cada claim (`iss`, `aud`, `sub`,
`token_use`, `exp`). Después escribí una Lambda que **verifique la firma** contra el
JWKS y rechace un token manipulado. Eso es exactamente lo que hace un backend real.

---

## Semana 4 — Asincronía y orquestación

### Módulo 7 · SQS, SNS y EventBridge (8 h)

La pregunta que resuelve este módulo: *¿cuándo cola, cuándo pub/sub, cuándo bus de eventos?*

- **SQS** — una cola, un trabajo, un consumidor que lo toma. Desacopla y absorbe picos.
- **SNS** — un mensaje, N suscriptores. Es el servicio detrás de las push notifications.
- **EventBridge** — bus con reglas de ruteo por contenido del evento.

Conceptos: visibility timeout · dead-letter queue · **idempotencia** (SQS garantiza
*at-least-once*: tu consumidor va a ver mensajes repetidos y tiene que tolerarlo) ·
FIFO vs estándar · event source mapping y batching.

Verificado: el trigger SQS → Lambda funciona (ver módulo 1 para el permiso que necesita).

Ejercicio: `POST /posts` responde al teléfono al instante y encola el trabajo pesado
(generar thumbnail, notificar seguidores). Una Lambda worker consume la cola. Forzá un
error en el worker y mirá cómo el mensaje vuelve a la cola y termina en la DLQ.

### Módulo 8 · Step Functions y secretos (5 h)

Conceptos: máquina de estados · reintentos con backoff · manejo de errores y
compensación · cuándo una orquestación explícita le gana a Lambdas encadenadas.
Secrets Manager y KMS: dónde van las credenciales de verdad (nunca en variables de
entorno en texto plano).

Ojo: **SSM Parameter Store está al 47%**. Aprendé el concepto, no pelees con el emulador.

---

## Semana 5 — Proyecto integrador (12 h)

Un backend móvil completo, levantado por un solo script, desde cero, en el emulador.

```
  App móvil
     │
     ├─ Cognito ──────────────► login, ID token (JWT RS256)
     │
     ├─ API Gateway (HTTP API) ─► authorizer JWT
     │        │
     │        └─ Lambda ──┬──► DynamoDB   (posts, perfiles)
     │                    ├──► S3         (presigned URL para fotos)
     │                    └──► SQS ──► Lambda worker ──► SNS
     │
     └─ IAM: un rol por Lambda, con lo mínimo necesario
```

Requisitos de entrega:

1. `labs/proyecto/up.sh` levanta **todo** desde cero en un emulador recién arrancado.
2. `labs/proyecto/down.sh` lo borra.
3. `labs/proyecto/smoke.sh` hace el recorrido completo: signup → login → crear post
   con foto → verificar que el worker procesó → borrar.
4. Cada Lambda tiene su propio rol con permisos mínimos. Cero `*` en las policies.
5. Un `README.md` donde explicás **por qué** cada servicio está ahí.

Si el punto 1 corre limpio dos veces seguidas, aprendiste AWS mejor que mucha gente
que trabaja en AWS todos los días.

---

## Lo que este plan NO te enseña

Honestidad por delante: el emulador cubre las APIs, no la nube. Queda pendiente para
cuando tengas una cuenta real:

| Tema | Por qué no está acá |
|---|---|
| **VPC, subredes, security groups** | No hay red emulada. Es la mitad de la arquitectura AWS real. |
| **IAM en profundidad** | El emulador valida permisos, pero no vas a ver el ecosistema real de SCPs, boundaries y federación. |
| **Costos y facturación** | No hay facturación. Y el costo manda el diseño en AWS. |
| **CloudFormation / CDK / SAM** | 24% de fidelidad. **No lo intentes acá**: vas a debuggear el emulador, no tu código. |
| **La consola web** | No existe. Toda la práctica es CLI — lo cual, para aprender, es mejor. |
| **Despliegue real y CI/CD** | Sin cuenta no hay despliegue. |
| **Push notifications reales** | SNS emulado no habla con APNs ni FCM. |
| **CloudFront, RDS, ECS, EC2** | Fuera de alcance para este plan. |
| **Monitoreo, alarmas, X-Ray** | Observabilidad floja en el emulador. |
| **Cuotas, límites, multi-AZ** | No se simulan. |

Cuando termines las 5 semanas, el paso siguiente es una cuenta free tier y rehacer el
proyecto integrador con CDK. Vas a tener el modelo mental; solo cambia la herramienta.

---

## Recursos

- [AWS Emulator — User Guide](https://docs.aws.amazon.com/emulator/latest/userguide/what-is-service.html)
- Docs de **AWS real** para cada servicio — estudiá contra esas, no contra las del emulador
- `issues/things-that-do-not-work/` en el repo del emulador: los gaps conocidos, versionados
