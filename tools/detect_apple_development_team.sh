#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Apple Development signing requires macOS" >&2
  exit 1
fi

identities="$(security find-identity -v -p codesigning 2>&1)"
certificate_name="$(printf '%s\n' "$identities" |
  sed -nE '/"Apple Development:/s/.*"([^"]+)".*/\1/p' |
  head -n 1)"
subject="$(
  if [[ -n "$certificate_name" ]]; then
    security find-certificate -c "$certificate_name" -p 2>/dev/null |
      openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null || true
  fi
)"
team="$(printf '%s\n' "$subject" |
  sed -nE 's/.*[, ]OU=([A-Z0-9]{10})(,.*)?$/\1/p')"

if [[ ! "$team" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "No valid Apple Development signing identity was found in the login Keychain." >&2
  echo "Sign in to Xcode and create an Apple Development certificate first." >&2
  exit 1
fi

printf '%s\n' "$team"
