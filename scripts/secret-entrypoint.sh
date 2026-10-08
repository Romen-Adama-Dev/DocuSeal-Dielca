#!/bin/sh
set -eu
secret_file=/run/secrets/docuseal_secret_key_base
[ -s "$secret_file" ] || { echo "Application secret is missing" >&2; exit 1; }
SECRET_KEY_BASE=$(cat "$secret_file")
export SECRET_KEY_BASE

if [ "${DOCUSEAL_OIDC_ENABLED:-false}" = "true" ]; then
  oidc_secret_file=/run/secrets/docuseal_oidc_client_secret
  [ -s "$oidc_secret_file" ] || { echo "OIDC client secret is missing" >&2; exit 1; }
  DOCUSEAL_OIDC_CLIENT_SECRET=$(cat "$oidc_secret_file")
  export DOCUSEAL_OIDC_CLIENT_SECRET
fi

exec /app/bin/bundle exec puma -C /app/config/puma.rb --dir /app
