#!/bin/sh
set -eu

source_config=/run/secrets/ianvs-api-config.json
private_directory=/run/ianvs-api
private_config="$private_directory/configuration.json"

if [ "$#" -ne 3 ] || [ "$1" != serve ] || [ "$2" != --config ] || [ "$3" != "$source_config" ]; then
  echo 'container entrypoint requires: serve --config /run/secrets/ianvs-api-config.json' >&2
  exit 64
fi
if [ ! -f "$source_config" ]; then
  echo 'container configuration must be a regular file' >&2
  exit 66
fi

umask 077
install -d -m 0710 -o root -g ianvs "$private_directory"
temporary_config="$private_directory/.configuration.$$"
trap 'rm -f "$temporary_config"' EXIT HUP INT TERM
install -m 0400 -o ianvs -g ianvs "$source_config" "$temporary_config"
mv -f "$temporary_config" "$private_config"
trap - EXIT HUP INT TERM

exec su-exec ianvs:ianvs /usr/local/bin/ianvs-api serve --config "$private_config"
