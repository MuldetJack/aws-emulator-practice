# AWS Emulator — imagen local.
#
# En macOS y Windows este es el único camino soportado: el emulador corre
# nativo solo en Linux (x86_64 / aarch64, glibc >= 2.17).
# Docs: https://docs.aws.amazon.com/emulator/latest/userguide/getting-started-docker.html

FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal

# aarch64 = Apple Silicon / Graviton; x86_64 = Intel/AMD. Lo pasa docker-compose.yml.
ARG EMULATOR_ARCH=aarch64
# No hay URL por versión publicada (el listado del bucket devuelve 403), así que
# esto siempre trae la última LTS. Para fijar una versión, construí una vez y
# etiquetá la imagen resultante — ver README.md.
ARG EMULATOR_CHANNEL=LTS/latest

ADD https://downloads.aws.com/aws-emulator/packages/aws-emulator/${EMULATOR_CHANNEL}/aws-emulator-${EMULATOR_ARCH}.rpm /tmp/aws-emulator.rpm

RUN rpm -qp --queryformat '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n' /tmp/aws-emulator.rpm > /etc/aws-emulator-version \
 && rpm -i /tmp/aws-emulator.rpm \
 && rm -f /tmp/aws-emulator.rpm \
 && mkdir -p /home/emulator && chown 1000 /home/emulator

USER 1000
ENV HOME=/home/emulator
EXPOSE 9297

# -b 0.0.0.0 para que Docker pueda publicar el puerto hacia afuera del contenedor.
# El binding en el host se restringe a 127.0.0.1 desde docker-compose.yml.
ENTRYPOINT ["aws-emulator", "-b", "0.0.0.0"]
