#!/usr/bin/env bash
# Apunta la AWS CLI y los SDK al emulador local.
#
#   source ./env.sh             # usa EMULATOR_PORT de .env, o 9297
#   source ./env.sh off         # revierte: vuelve a la config real de AWS
#   EMULATOR_PORT=9298 source ./env.sh
#
# Docs: https://docs.aws.amazon.com/emulator/latest/userguide/point-sdk-to-emulator.html

if [ "$1" = "off" ]; then
  unset AWS_ENDPOINT_URL AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE \
        AWS_CA_BUNDLE AWS_EC2_METADATA_DISABLED AWS_DISABLE_HOST_PREFIX_INJECTION
  echo "aws-emulator: variables limpiadas, volvés a tu config real de AWS."
  return 0 2>/dev/null || exit 0
fi

# Lee EMULATOR_PORT de .env si no viene del entorno.
if [ -z "$EMULATOR_PORT" ] && [ -f "${BASH_SOURCE%/*}/.env" ]; then
  EMULATOR_PORT=$(grep -E '^EMULATOR_PORT=' "${BASH_SOURCE%/*}/.env" | tail -1 | cut -d= -f2)
fi
_port="${EMULATOR_PORT:-9297}"
_dir="$HOME/.aws/emulator/$_port"

if [ ! -r "$_dir/emulator_credentials" ]; then
  echo "aws-emulator: no encuentro $_dir/emulator_credentials" >&2
  echo "              ¿está corriendo el emulador?  docker compose up -d" >&2
  unset _port _dir
  return 1 2>/dev/null || exit 1
fi

# Estas tienen prioridad sobre el archivo de credenciales del emulador, así que
# si quedaron de una sesión con AWS real romperían las llamadas.
unset AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

export AWS_ENDPOINT_URL="https://127.0.0.1:$_port"
export AWS_SHARED_CREDENTIALS_FILE="$_dir/emulator_credentials"
export AWS_CONFIG_FILE="$_dir/config"
export AWS_CA_BUNDLE="$_dir/ca.pem"
export AWS_EC2_METADATA_DISABLED=true
export AWS_DISABLE_HOST_PREFIX_INJECTION=true
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "aws-emulator: apuntando a $AWS_ENDPOINT_URL  (region $AWS_REGION)"
unset _port _dir
