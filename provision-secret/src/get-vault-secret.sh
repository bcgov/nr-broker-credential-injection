#!/usr/bin/env sh

# Validate required environment variables
BROKER_ADDR="${BROKER_ADDR:-https://broker.io.nrs.gov.bc.ca}"
VAULT_ADDR="${VAULT_ADDR:-https://knox.io.nrs.gov.bc.ca}"
OPENSHIFT_SECRET_NAME="${OPENSHIFT_SECRET_NAME:-vault-secret}"
OPENSHIFT_TOKEN_KEY="${OPENSHIFT_TOKEN_KEY:-token}"
OPENSHIFT_ROLE_KEY="${OPENSHIFT_ROLE_KEY:-role}"
OPENSHIFT_SECRET_ID_KEY="${OPENSHIFT_SECRET_ID_KEY:-secret_id}"
CREDENTIAL_SYNC_ENABLED="${CREDENTIAL_SYNC_ENABLED:-false}"
VAULT_SECRET_PATH="${VAULT_SECRET_PATH:-}"
OPENSHIFT_SERVICE_SECRET_NAME="${OPENSHIFT_SERVICE_SECRET_NAME:-${OPENSHIFT_SECRET_NAME}-service}"
VAULT_SECRET_ID="${VAULT_SECRET_ID:-}"
: "${VAULT_ROLE_ID:?VAULT_ROLE_ID is required}"
: "${BROKER_JWT:?BROKER_JWT is required}"
: "${INTENTION_EVENT_URL:?INTENTION_EVENT_URL is required}"
: "${INTENTION_ENVIRONMENT:?INTENTION_ENVIRONMENT is required}"

INTENTION_TOKEN=""

cleanup() {
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -ne 0 ] && [ -n "$INTENTION_TOKEN" ]; then
        echo "=> Intention: close (failure)"
        curl -s -X POST "$BROKER_ADDR/v1/intention/close?outcome=failure" -H "X-Broker-Token: $INTENTION_TOKEN" || true
    fi
}
trap cleanup EXIT
set -e

create_or_update_secret_from_dir() {
    secret_name="$1"
    data_dir="$2"

    set -- kubectl create secret generic "$secret_name"
    for file in "$data_dir"/*; do
        if [ -f "$file" ]; then
            key=$(basename "$file")
            set -- "$@" --from-file="$key=$file"
        fi
    done

    "$@" --dry-run=client -o yaml | kubectl apply -f -
}

write_vault_data_to_dir() {
    vault_data_json="$1"
    output_dir="$2"

    echo "$vault_data_json" | jq -r 'to_entries[] | @base64' | while IFS= read -r entry; do
        decoded_entry=$(printf '%s' "$entry" | base64 -d)
        key=$(printf '%s' "$decoded_entry" | jq -r '.key')

        if ! echo "$key" | grep -Eq '^[A-Za-z0-9._-]+$'; then
            echo "Skip unsupported key '$key' (allowed: A-Za-z0-9._-)"
            continue
        fi

        value=$(printf '%s' "$decoded_entry" | jq -r 'if (.value | type) == "string" then .value else (.value | tojson) end')
        printf '%s' "$value" > "$output_dir/$key"
    done
}

sync_service_secret() {
    if [ "$CREDENTIAL_SYNC_ENABLED" != "true" ]; then
        echo "credentialSync disabled; skip Vault path sync"
        return 0
    fi

    if [ -z "$VAULT_SECRET_PATH" ]; then
        echo "credentialSync enabled but VAULT_SECRET_PATH is empty; skip Vault path sync"
        return 0
    fi

    echo "Login to Vault using AppRole"
    VAULT_LOGIN_RESPONSE=$(curl -s -X POST "$VAULT_ADDR/v1/auth/vs_apps_approle/login" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n --arg role_id "$VAULT_ROLE_ID" --arg secret_id "$VAULT_SECRET_ID" '{role_id: $role_id, secret_id: $secret_id}')")
    VAULT_LOGIN_TOKEN=$(echo "$VAULT_LOGIN_RESPONSE" | jq -r '.auth.client_token // empty')

    if [ -z "$VAULT_LOGIN_TOKEN" ]; then
        echo "Failed to login to Vault with AppRole"
        echo "$VAULT_LOGIN_RESPONSE"
        exit 1
    fi

    echo "Read Vault path $VAULT_SECRET_PATH"
    VAULT_PATH_RESPONSE=$(curl -s -X GET "$VAULT_ADDR/v1/$VAULT_SECRET_PATH" -H "X-Vault-Token: $VAULT_LOGIN_TOKEN")
    if [ "$(echo "$VAULT_PATH_RESPONSE" | jq '.errors // [] | length')" -gt 0 ]; then
        echo "Vault returned errors for path $VAULT_SECRET_PATH"
        echo "$VAULT_PATH_RESPONSE"
        exit 1
    fi

    VAULT_DATA_JSON=$(echo "$VAULT_PATH_RESPONSE" | jq -c 'if (.data.data | type) == "object" then .data.data elif (.data | type) == "object" then .data else empty end')
    if [ -z "$VAULT_DATA_JSON" ]; then
        echo "No secret data found at Vault path $VAULT_SECRET_PATH"
        exit 1
    fi

    TEMP_SERVICE_DIR=$(mktemp -d)
    write_vault_data_to_dir "$VAULT_DATA_JSON" "$TEMP_SERVICE_DIR"

    echo "Create or update OpenShift secret $OPENSHIFT_SERVICE_SECRET_NAME from Vault path data"
    create_or_update_secret_from_dir "$OPENSHIFT_SERVICE_SECRET_NAME" "$TEMP_SERVICE_DIR"
    rm -rf "$TEMP_SERVICE_DIR"
}

PROVISION_NAME=$(jq -r '.actions[0].id' ./config/intention.json)

echo "=> Intention: open ($BROKER_ADDR)"

# Open intention
RESPONSE=$(curl -s -X POST "$BROKER_ADDR/v1/intention/open" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $BROKER_JWT" \
    -d "$(jq --arg event_url "$INTENTION_EVENT_URL" --arg user "${INTENTION_USER:-}" --arg env "$INTENTION_ENVIRONMENT" \
        '.event.url=$event_url | (if $user != "" then .user.name=$user else . end) | .actions[0].service.environment=$env' \
        ./config/intention.json)")

if [ "$(echo "$RESPONSE" | jq '.error')" != "null" ]; then
    echo "Exit: Error detected"
    exit 1
fi

# Save intention token for later
INTENTION_TOKEN=$(echo "$RESPONSE" | jq -r '.token')
# Get token for provisioning access
ACTION_TOKEN=$(echo "$RESPONSE" | jq -r ".actions.$PROVISION_NAME.token")

echo "=> Action: start"
# Start action
curl -s -X POST "$BROKER_ADDR/v1/intention/action/start" -H "X-Broker-Token: $ACTION_TOKEN"

# Always rotate secret_id on every run to avoid using expired credentials.
echo "Get wrapped vault token from broker"
VAULT_TOKEN_WRAP=$(curl -s -X POST "$BROKER_ADDR/v1/provision/approle/secret-id" \
    -H "X-Broker-Token: $ACTION_TOKEN" \
    -H "X-Vault-Role-Id: $VAULT_ROLE_ID")
WRAPPED_VAULT_TOKEN=$(echo "$VAULT_TOKEN_WRAP" | jq -r '.wrap_info.token')

echo "Unwrapped vault token for secret_id"
UNWRAPPED_VAULT_TOKEN=$(curl -s -X POST "$VAULT_ADDR/v1/sys/wrapping/unwrap" -H "X-Vault-Token: $WRAPPED_VAULT_TOKEN")
VAULT_SECRET_ID=$(echo "$UNWRAPPED_VAULT_TOKEN" | jq -r '.data.secret_id')

TEMP_CREDENTIAL_DIR=$(mktemp -d)
printf '%s' "$BROKER_JWT" > "$TEMP_CREDENTIAL_DIR/$OPENSHIFT_TOKEN_KEY"
printf '%s' "$VAULT_ROLE_ID" > "$TEMP_CREDENTIAL_DIR/$OPENSHIFT_ROLE_KEY"
printf '%s' "$VAULT_SECRET_ID" > "$TEMP_CREDENTIAL_DIR/$OPENSHIFT_SECRET_ID_KEY"

echo "Create or update OpenShift secret $OPENSHIFT_SECRET_NAME with AppRole credentials"
create_or_update_secret_from_dir "$OPENSHIFT_SECRET_NAME" "$TEMP_CREDENTIAL_DIR"
rm -rf "$TEMP_CREDENTIAL_DIR"

echo "Success! Secret ID saved to OpenShift secret $OPENSHIFT_SECRET_NAME"

sync_service_secret

echo "=> Action: end"
# End action
curl -s -X POST "$BROKER_ADDR/v1/intention/action/end" -H "X-Broker-Token: $ACTION_TOKEN"

echo "=> Intention: close"
# Use saved intention token to close intention
curl -s -X POST "$BROKER_ADDR/v1/intention/close" -H "X-Broker-Token: $INTENTION_TOKEN"
