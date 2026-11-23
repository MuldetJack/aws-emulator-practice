# AWS Emulator — entorno local

Emulador local de las APIs de AWS ([aws/aws-emulator](https://github.com/aws/aws-emulator),
oficial de AWS, Rust, CC0-1.0). Levanta un endpoint HTTPS en `127.0.0.1:9297`
contra el que apuntás la AWS CLI o cualquier SDK. No requiere cuenta de AWS.

Verificado en esta máquina con **aws-emulator 1.0.471-1 aarch64**, Docker 29.9.3,
AWS CLI 2.36.39, macOS arm64.

## Uso

```bash
docker compose up -d --build     # la primera vez: ~168 MB de rpm
source ./env.sh                  # apunta la CLI/SDK al emulador
aws s3 mb s3://mi-bucket
```

Para volver a tu configuración real de AWS en esa shell:

```bash
source ./env.sh off
```

Parar y limpiar:

```bash
docker compose down
```

## Archivos

| Archivo | Qué hace |
|---|---|
| `Dockerfile` | Instala el rpm del emulador sobre `amazonlinux:2023-minimal`. En macOS es el único camino: el emulador corre nativo solo en Linux. |
| `docker-compose.yml` | Puerto, límite de memoria, volumen, telemetría apagada, healthcheck. |
| `.env` | Arquitectura, puerto, tag de imagen, límite de memoria. |
| `env.sh` | Exporta las variables que apuntan la CLI/SDK al emulador. Sourcealo, no lo ejecutes. |

## Cosas que importan

**El estado vive solo en memoria.** Un `docker compose down`, un `restart` o un
recreate del contenedor borra todos los recursos emulados. No hay persistencia.

**Límite de 2 GiB.** Si lo excede, el contenedor muere con exit 137 y perdés el
estado. Subilo en `.env` (`EMULATOR_MEMORY`) si hace falta.

**Credenciales efímeras.** El emulador genera un access key nuevo en cada
arranque y lo escribe en `~/.aws/emulator/9297/emulator_credentials`, junto con
`config`, `ca.pem` y `truststore.p12` (Java). Ese directorio está montado desde
el host — por eso `env.sh` puede leerlos. Las credenciales sirven solo para esa
corrida.

**`env.sh` limpia `AWS_PROFILE` y `AWS_ACCESS_KEY_ID`/`SECRET`/`SESSION_TOKEN`**
de la shell, porque tienen prioridad sobre el archivo de credenciales del
emulador y romperían las llamadas si quedaron de una sesión con AWS real.

**Telemetría apagada** por `EMULATOR_TELEMETRY=off` y `--telemetry off`. Viene
encendida por defecto en el emulador.

**El binding es `127.0.0.1`**, nunca `9297:9297` pelado — eso expondría el
emulador a toda la red. Dentro del contenedor escucha en `0.0.0.0` (necesario
para que Docker publique el puerto) y por eso el log muestra un WARN al
arrancar; es esperado, el aislamiento lo da el binding del host.

**AWS lo marca como no apto para producción ni para probar seguridad.**

## Fijar una versión

No hay URL de descarga por versión (el listado del bucket devuelve 403), así que
`LTS/latest` siempre trae la última. El repo publica varias releases por día.
Para pinnear, etiquetá la imagen que construiste y apuntá `.env` a ese tag:

```bash
docker tag aws-emulator:local aws-emulator:1.0.471.1
# en .env:  EMULATOR_IMAGE=aws-emulator:1.0.471.1
```

Con un tag distinto de `:local`, `docker compose up -d` (sin `--build`) reusa esa
imagen en vez de reconstruir.

Para ver qué versión tiene una imagen:

```bash
docker run --rm --entrypoint cat aws-emulator:local /etc/aws-emulator-version
```

El `rpm -i` emite un warning `NOKEY`: la firma del paquete no se verifica porque
la clave GPG de AWS no está importada en la imagen. Es el mismo comportamiento
que el Dockerfile de la documentación oficial.

## Arquitectura

`.env` trae `EMULATOR_ARCH=aarch64` (Apple Silicon). En Intel/AMD, cambialo a
`x86_64` y reconstruí con `docker compose build --no-cache`.

## Fidelidad

No todo está emulado al 100%. Cada release publica `scores.json.gz` con los
resultados contra AWS real; en `v1.0.471` el global es **69,4%** (30.237/43.548
casos). Aproximados por servicio:

| Bien (>80%) | Aceptable (70-80%) | Flojo |
|---|---|---|
| SNS, KMS, Cognito IdP, EventBridge, Secrets Manager, Step Functions, Kinesis | S3, DynamoDB, SQS, API Gateway, CloudWatch Logs, IAM, ECR | Lambda behavioral (69%), AppSync (57%), SSM (47%), **CloudFormation (24%)**, Pinpoint |

No esperes desplegar un stack CloudFormation/CDK completo contra el emulador.
Los gaps concretos están versionados en `issues/things-that-do-not-work/` del repo.

## Docs

- [User Guide](https://docs.aws.amazon.com/emulator/latest/userguide/what-is-service.html)
- [Getting started with Docker](https://docs.aws.amazon.com/emulator/latest/userguide/getting-started-docker.html)
- [Pointing your AWS SDK at AWS Emulator](https://docs.aws.amazon.com/emulator/latest/userguide/point-sdk-to-emulator.html)
