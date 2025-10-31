#!/bin/sh
set -eu

export HOSTNAME="$FLY_MACHINE_ID.vm.$FLY_APP_NAME.internal"
export BIND_ADDRESS="$FLY_PRIVATE_IP"
export SERVER_ID="fly_server_$FLY_MACHINE_ID"
export PORT=8080

ALL_MACHINE_IDS=$(dig +short "all.vms.$FLY_APP_NAME.internal" TXT \
  | tr -d '"' \
  | tr ',' '\n' \
  | sed 's/ .*//')

out=""
sep=""
for ID in $ALL_MACHINE_IDS; do
  out="${out}${sep}http://${ID}.vm.$FLY_APP_NAME.internal:${PORT}/"
  sep=","
done

export BOOTSTRAP_NODES="${out}"

echo "bootstrap_nodes=$BOOTSTRAP_NODES"

REGION="auto"

case $FLY_REGION in
  ams | cdg | fra | lhr | arn)
    REGION="eu-west"
    ;;

  ewr | iad)
    REGION="us-east"
    ;;

  lax | sjc)
    REGION="us-west"
    ;;

  gru | dfw)
    REGION="amer-south"
    ;;

  yyz | ord)
    REGION="amer-north"
    ;;

  nrt | sin)
    REGION="asia-east"
    ;;

  syd)
    REGION="pacific"
    ;;

  bom)
    REGION="asia-south"
    ;;
esac

export REGION=$REGION
export VALID_REGIONS="eu-west,us-east"

PACKAGE=joblot
BASE=$(dirname "$0")
COMMAND="${1-default}"

run() {
  exec erl \
    -pa "$BASE"/*/ebin \
    -eval "$PACKAGE@@main:run($PACKAGE)" \
    -noshell \
    -extra "$@"
}

shell() {
  erl -pa "$BASE"/*/ebin
}

case "$COMMAND" in
run)
  shift
  run "$@"
  ;;

shell)
  shell
  ;;

*)
  echo "usage:" >&2
  echo "  fly-start.sh \$COMMAND" >&2
  echo "" >&2
  echo "commands:" >&2
  echo "  run    Run the project main function" >&2
  echo "  shell  Run an Erlang shell" >&2
  exit 1
  ;;
esac
