#!/usr/bin/env bash

# Knox Secret Sync - Sync Vault secrets to OpenShift secrets
# This script logs into Vault using AppRole credentials and syncs
# configured Vault keys to OpenShift secrets for non-integrated usage.

# Validate required environment variables
VAULT_ADDR="${VAULT_ADDR:-https://knox.io.nrs.gov.bc.ca}"
VAULT_ROLE_ID_KEY="${VAULT_ROLE_ID_KEY:-role_id}"
VAULT_SECRET_ID_KEY="${VAULT_SECRET_ID_KEY:-secret_id}"
SECRET_SOURCE_NAME="${SECRET_SOURCE_NAME:-knox-secret}"

# Parse sync configuration from environment
# SYNC_VAULT_PATHS is a comma-separated list of Vault secret paths to read
# SYNC_SECRET_NAMES is a comma-separated list of OpenShift secret names to create/update
# SYNC_SECRET_KEYS is a comma-separated list of keys within each secret
# SYNC_VAULT_PATHS is required - comma-separated Vault secret paths (e.g., 'secret/data/app,secret/data/db')
: "${SYNC_VAULT_PATHS:?SYNC_VAULT_PATHS is required - comma-separated Vault secret paths}"
: "${SYNC_SECRET_NAMES:?SYNC_SECRET_NAMES is required - comma-separated OpenShift secret names to create/update}"

echo "=== Knox Secret Sync ==="
echo "Vault Address: $VAULT_ADDR"
echo "Source Secret: $SECRET_SOURCE_NAME"
echo "Vault Paths: $SYNC_VAULT_PATHS"
echo "Target Secrets: $SYNC_SECRET_NAMES"

# Read AppRole credentials from source secret
echo "Reading AppRole credentials from OpenShift secret $SECRET_SOURCE_NAME"
VAULT_ROLE_ID=$(kubectl get secret "$SECRET_SOURCE_NAME" -o jsonpath="{.data['$VAULT_ROLE_ID_KEY']}" | base64 -d)
VAULT_SECRET_ID=$(kubectl get secret "$SECRET_SOURCE_NAME" -o jsonpath="{.data['$VAULT_SECRET_ID_KEY']}" | base64 -d)

if [ -z "$VAULT_ROLE_ID" ] || [ -z "$VAULT_SECRET_ID" ]; then
    echo "ERROR: Failed to read AppRole credentials from secret $SECRET_SOURCE_NAME"
    exit 1
fi

echo "Logging into Vault using AppRole"
LOGIN_RESPONSE=$(curl -s -X POST "$VAULT_ADDR/v1/auth/vs_apps_approle/login" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg role_id "$VAULT_ROLE_ID" --arg secret_id "$VAULT_SECRET_ID" \
        '{"role_id": $role_id, "secret_id": $secret_id}')")

if [ "$(echo "$LOGIN_RESPONSE" | jq '.errors // empty')" != "" ]; then
    echo "ERROR: Failed to login to Vault"
    echo "$LOGIN_RESPONSE" | jq '.'
    exit 1
fi

VAULT_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.auth.client_token')
VAULT_TOKEN_TTL=$(echo "$LOGIN_RESPONSE" | jq -r '.auth.lease_ttl')

echo "Successfully logged into Vault (TTL: ${VAULT_TOKEN_TTL}s)"

# Parse comma-separated values into arrays
IFS=',' read -ra VAULT_PATHS <<< "$SYNC_VAULT_PATHS"
IFS=',' read -ra SECRET_NAMES <<< "$SYNC_SECRET_NAMES"

# Validate equal number of paths and secret names
if [ "${#VAULT_PATHS[@]}" -ne "${#SECRET_NAMES[@]}" ]; then
    echo "ERROR: Number of vault paths (${#VAULT_PATHS[@]}) must match number of secret names (${#SECRET_NAMES[@]})"
    exit 1
fi

# Sync each Vault path to corresponding OpenShift secret
for i in "${!VAULT_PATHS[@]}"; do
    VAULT_PATH="${VAULT_PATHS[$i]}"
    SECRET_NAME="${SECRET_NAMES[$i]}"

    echo ""
    echo "Processing: Vault path '$VAULT_PATH' -> OpenShift secret '$SECRET_NAME'"

    # Read secret from Vault
    echo "Reading secret from Vault: $VAULT_PATH"
    VAULT_SECRET_DATA=$(curl -s -X GET "$VAULT_ADDR/v1/$VAULT_PATH" \
        -H "X-Vault-Token: $VAULT_TOKEN")

    if [ "$(echo "$VAULT_SECRET_DATA" | jq '.errors // empty')" != "" ]; then
        echo "WARNING: Failed to read secret from Vault path '$VAULT_PATH'"
        echo "$VAULT_SECRET_DATA" | jq '.'
        continue
    fi
    SECRET_MAP=$(echo "$VAULT_SECRET_DATA" | jq '.data.data // .data // empty')

    if [ -z "$SECRET_MAP" ] || [ "$SECRET_MAP" = "null" ]; then
        echo "WARNING: No data found in Vault path '$VAULT_PATH'"
        continue
    fi

    echo "Creating/updating OpenShift secret '$SECRET_NAME'"
    jq -n --arg name "$SECRET_NAME" --argjson data "$SECRET_MAP" '{
      apiVersion: "v1",
      kind: "Secret",
      metadata: { name: $name },
      type: "Opaque",
      stringData: $data
    }' | kubectl apply -f -

    if [ $? -eq 0 ]; then
        echo "SUCCESS: OpenShift secret '$SECRET_NAME' created/updated"
    else
        echo "ERROR: Failed to create/update OpenShift secret '$SECRET_NAME'"
    fi
done

# Revoke the Vault token
echo ""
echo "Revoking Vault token"
curl -s -X POST "$VAULT_ADDR/v1/auth/token/revoke-self" \
    -H "X-Vault-Token: $VAULT_TOKEN"

echo ""
echo "=== Secret Sync Complete ==="
echo ""
echo "NOTICE: This job must be run before changes are reflected in OpenShift."
echo "For applications requiring dynamic secrets, Vault should be connected to during runtime."
echo "Consider using the Vault Agent Sidecar Injector for dynamic secret rotation."
