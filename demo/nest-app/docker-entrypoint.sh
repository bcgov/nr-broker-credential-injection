#!/usr/bin/env sh

set -e

: "${VAULT_ADDR:?VAULT_ADDR is required}"
: "${VAULT_SECRET_PATH:?VAULT_SECRET_PATH is required}"

echo "Starting Vault Agent AppRole authentication"
vault agent -config=/config/vault-agent/agent.hcl -exit-after-auth

if [ ! -f /vault/secrets/.vault-token ]; then
  echo "Vault token file was not created"
  exit 1
fi

export VAULT_TOKEN="$(cat /vault/secrets/.vault-token)"

echo "Fetching secrets from Vault path: $VAULT_SECRET_PATH"
vault kv get -format=json "$VAULT_SECRET_PATH" \
  | jq -r '.data.data | to_entries[] | "export \(.key)=\(.value|@sh)"' > /vault/secrets/app.env

# shellcheck disable=SC1091
. /vault/secrets/app.env

exec node dist/main