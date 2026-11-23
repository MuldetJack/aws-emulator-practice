# labs — ejercicios del plan

Scripts del plan de [`../APRENDIZAJE.md`](../APRENDIZAJE.md). Uno por módulo.

```bash
docker compose up -d        # desde la raíz del repo
./labs/00-entorno.sh        # módulo 00
```

Los scripts **sourcean `env.sh` solos**: no hace falta que apuntes la shell al
emulador antes de correrlos. Si querés usar la CLI a mano en la misma terminal,
igual necesitás `source ./env.sh`.

## La convención

| | |
|---|---|
| `lib.sh` | Helpers compartidos. No se ejecuta solo. |
| `_template.sh` | Plantilla para los módulos nuevos. **Corre tal cual**, para que veas el patrón funcionando. |
| `NN-nombre.sh` | Un módulo. Acepta `up`, `check` y `down`. |

Para empezar un módulo:

```bash
cp labs/_template.sh labs/01-iam.sh
```

## Las tres reglas

1. **Idempotente.** Correrlo dos veces seguidas da el mismo resultado, sin errores.
2. **Imprime lo que creó.** Si no ves los ARNs y las URLs, no sabés qué pasó.
3. **Sabe borrarse.** `down` deja el emulador como estaba.

La tercera no es opcional: el estado del emulador vive en RAM y se pierde con
cualquier `docker compose down`, restart o OOM. Si tu entorno no se reconstruye
con un comando, no existe. Este es el hábito que después te salva en AWS real,
donde además lo que no borrás lo pagás.

## Helpers de `lib.sh`

```bash
lab::require_emulator        # falla con mensaje útil si el emulador no responde
lab::idem "<qué>" <comando>  # crea tolerando que ya exista
lab::rm   "<qué>" <comando>  # borra tolerando que no esté
lab::main "$@"               # despacha up/check/down a lab_up/lab_check/lab_down
lab::title / step / ok / skip / warn / note / die
```

Una lección de AWS escondida en `lab::idem`: las APIs de creación **no se
comportan igual**. S3 `create-bucket` y SQS `create-queue` devuelven 200 si el
recurso ya existe — son idempotentes por diseño. IAM `create-role`, DynamoDB
`create-table` y Lambda `create-function` tiran `EntityAlreadyExists`,
`ResourceInUseException` y `ResourceConflictException` respectivamente. Un script
que no contempla las dos familias se rompe la segunda vez que lo corrés.

## Estado

| Módulo | Script | Estado |
|---|---|---|
| 00 · Cómo le hablás a AWS | `00-entorno.sh` | **listo** |
| 01 · IAM | `01-iam.sh` | **listo** |
| 02 · S3 y presigned URL | `02-s3.sh` | **listo** |
| 03 · DynamoDB | `03-dynamodb.sh` | **listo** |
| 04 · Lambda | `04-lambda.sh` | por escribir |
| 05 · API Gateway | `05-apigateway.sh` | por escribir |
| 06 · Cognito | `06-cognito.sh` | por escribir |
| 07 · SQS, SNS, EventBridge | `07-mensajeria.sh` | por escribir |
| 08 · Step Functions y secretos | `08-orquestacion.sh` | por escribir |
| 09 · Proyecto integrador | `proyecto/` | por escribir |

La semana 1 está completa. Corrélos en orden:

```bash
./labs/00-entorno.sh     # el modelo de credenciales
./labs/01-iam.sh         # trust policy vs permission policy
./labs/02-s3.sh          # presigned URLs
./labs/03-dynamodb.sh    # single-table design
```

Cada uno termina con preguntas para responder por escrito. Esa parte es el
ejercicio real: los scripts solo te muestran el comportamiento.

## `tools/`

| | |
|---|---|
| `presign-put.mjs` | Firma una URL de subida (PUT) a S3 con SigV4, en Node puro y sin dependencias. Existe porque `aws s3 presign` solo firma GET, y porque ver la firma armarse enseña más que llamar a un SDK. Lo usa el módulo 02. |
