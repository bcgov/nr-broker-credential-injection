#!/usr/bin/env sh

# Validate required environment variables
BROKER_ADDR="${BROKER_ADDR:-https://broker.io.nrs.gov.bc.ca}"
VAULT_ADDR="${VAULT_ADDR:-https://knox.io.nrs.gov.bc.ca}"
OPENSHIFT_SECRET_NAME="${OPENSHIFT_SECRET_NAME:-vault-secret}"
OPENSHIFT_TOKEN_KEY="${OPENSHIFT_TOKEN_KEY:-token}"
OPENSHIFT_ROLE_KEY="${OPENSHIFT_ROLE_KEY:-role}"
OPENSHIFT_SECRET_ID_KEY="${OPENSHIFT_SECRET_ID_KEY:-secret_id}"
VAULT_ROLE_NAME="${VAULT_ROLE_NAME:-}"
VAULT_SECRET_ID_EXPIRE_DELAY_SECONDS="${VAULT_SECRET_ID_EXPIRE_DELAY_SECONDS:-5}"
CREDENTIAL_SYNC_ENABLED="${CREDENTIAL_SYNC_ENABLED:-false}"
VAULT_SECRET_PATH="${VAULT_SECRET_PATH:-}"
OPENSHIFT_SERVICE_SECRET_NAME="${OPENSHIFT_SERVICE_SECRET_NAME:-${OPENSHIFT_SECRET_NAME}-service}"
VAULT_SECRET_ID="${VAULT_SECRET_ID:-}"
OLD_SECRET_ID_VALUE=""
ACTION_TOKEN=""
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

validate_delay_seconds() {
    case "$VAULT_SECRET_ID_EXPIRE_DELAY_SECONDS" in
        ''|*[!0-9]*)
            echo "VAULT_SECRET_ID_EXPIRE_DELAY_SECONDS must be a non-negative integer"
            exit 1
            ;;
    esac
}

create_or_update_secret_from_json() {
    secret_name="$1"
    vault_data_json="$2"

    echo "$vault_data_json" | jq -r 'keys[] | select(test("^[A-Za-z0-9._-]+$") | not)' | while IFS= read -r key; do
        echo "Skip unsupported key '$key' (allowed: A-Za-z0-9._-)"
    done

    SECRET_MANIFEST=$(echo "$vault_data_json" | jq -c --arg name "$secret_name" '
        {
            apiVersion: "v1",
            kind: "Secret",
            metadata: {name: $name},
            type: "Opaque",
            stringData: (
                to_entries
                | map(select(.key | test("^[A-Za-z0-9._-]+$")))
                | from_entries
                | with_entries(.value |= if type == "string" then . else tojson end)
            )
        }
    ')

    if [ "$(echo "$SECRET_MANIFEST" | jq '.stringData | length')" -eq 0 ]; then
        echo "No supported secret keys found for $secret_name"
        exit 1
    fi

    echo "$SECRET_MANIFEST" | kubectl apply -f -
}

capture_old_secret_id() {

    if ! kubectl get secret "$OPENSHIFT_SECRET_NAME" >/dev/null 2>&1; then
        echo "No existing OpenShift secret $OPENSHIFT_SECRET_NAME found; skip old secret_id capture"
        return 0
    fi

    OLD_SECRET_ID_VALUE=$(kubectl get secret "$OPENSHIFT_SECRET_NAME" -o json \
        | jq -r --arg key "$OPENSHIFT_SECRET_ID_KEY" '.data[$key] // empty | @base64d' 2>/dev/null || true)

    if [ -n "$OLD_SECRET_ID_VALUE" ]; then
        echo "Found existing secret_id in $OPENSHIFT_SECRET_NAME"
    fi
}

open_intention_and_start_action() {
    PROVISION_NAME=$(jq -r '.actions[0].id' ./config/intention.json)

    echo "=> Intention: open ($BROKER_ADDR)"
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

    INTENTION_TOKEN=$(echo "$RESPONSE" | jq -r '.token')
    ACTION_TOKEN=$(echo "$RESPONSE" | jq -r ".actions.$PROVISION_NAME.token")

    echo "=> Action: start"
    curl -s -X POST "$BROKER_ADDR/v1/intention/action/start" -H "X-Broker-Token: $ACTION_TOKEN"
}

rotate_secret_id() {
    echo "Get wrapped vault token from broker"
    VAULT_TOKEN_WRAP=$(curl -s -X POST "$BROKER_ADDR/v1/provision/approle/secret-id" \
        -H "X-Broker-Token: $ACTION_TOKEN" \
        -H "X-Vault-Role-Id: $VAULT_ROLE_ID")
    WRAPPED_VAULT_TOKEN=$(echo "$VAULT_TOKEN_WRAP" | jq -r '.wrap_info.token // empty')

    if [ -z "$WRAPPED_VAULT_TOKEN" ]; then
        echo "Failed to get wrapped vault token"
        echo "$VAULT_TOKEN_WRAP"
        exit 1
    fi

    echo "Unwrapped vault token for secret_id"
    UNWRAPPED_VAULT_TOKEN=$(curl -s -X POST "$VAULT_ADDR/v1/sys/wrapping/unwrap" -H "X-Vault-Token: $WRAPPED_VAULT_TOKEN")
    VAULT_SECRET_ID=$(echo "$UNWRAPPED_VAULT_TOKEN" | jq -r '.data.secret_id // empty')

    if [ -z "$VAULT_SECRET_ID" ]; then
        echo "Failed to unwrap secret_id"
        echo "$UNWRAPPED_VAULT_TOKEN"
        exit 1
    fi
}

update_approle_secret() {
    echo "Create or update OpenShift secret $OPENSHIFT_SECRET_NAME with AppRole credentials"
    kubectl create secret generic "$OPENSHIFT_SECRET_NAME" \
        --from-literal="$OPENSHIFT_TOKEN_KEY=$BROKER_JWT" \
        --from-literal="$OPENSHIFT_ROLE_KEY=$VAULT_ROLE_ID" \
        --from-literal="$OPENSHIFT_SECRET_ID_KEY=$VAULT_SECRET_ID" \
        --dry-run=client \
        -o yaml | kubectl apply -f -

    echo "Success! Secret ID saved to OpenShift secret $OPENSHIFT_SECRET_NAME"
}

destroy_old_secret_id_with_delay() {
    if [ -z "$OLD_SECRET_ID_VALUE" ]; then
        echo "No previous secret_id found; skip old secret_id destroy"
        return 0
    fi

    if [ -z "$VAULT_ROLE_NAME" ]; then
        echo "VAULT_ROLE_NAME is empty; skip old secret_id destroy"
        return 0
    fi

    if [ "$OLD_SECRET_ID_VALUE" = "$VAULT_SECRET_ID" ]; then
        echo "Old secret_id matches new secret_id; skip destroy"
        return 0
    fi

    if [ "$VAULT_SECRET_ID_EXPIRE_DELAY_SECONDS" -gt 0 ]; then
        echo "Delay old secret_id destroy by ${VAULT_SECRET_ID_EXPIRE_DELAY_SECONDS}s"
        sleep "$VAULT_SECRET_ID_EXPIRE_DELAY_SECONDS"
    fi

    echo "Login to Vault with old secret_id"
    OLD_VAULT_LOGIN_RESPONSE=$(curl -s -X POST "$VAULT_ADDR/v1/auth/vs_apps_approle/login" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n --arg role_id "$VAULT_ROLE_ID" --arg secret_id "$OLD_SECRET_ID_VALUE" '{role_id: $role_id, secret_id: $secret_id}')")
    OLD_VAULT_LOGIN_TOKEN=$(echo "$OLD_VAULT_LOGIN_RESPONSE" | jq -r '.auth.client_token // empty')

    if [ -z "$OLD_VAULT_LOGIN_TOKEN" ]; then
        echo "Old secret_id login failed; skip destroy (may already be expired or invalid)"
        return 0
    fi

    echo "Destroy old Vault secret_id for role $VAULT_ROLE_NAME"
    OLD_SECRET_ID_DESTROY_RESPONSE=$(curl -s -X POST "$VAULT_ADDR/v1/auth/vs_apps_approle/role/$VAULT_ROLE_NAME/secret-id/destroy" \
        -H "X-Vault-Token: $OLD_VAULT_LOGIN_TOKEN" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n --arg secret_id "$OLD_SECRET_ID_VALUE" '{secret_id: $secret_id}')")

    if [ "$(echo "$OLD_SECRET_ID_DESTROY_RESPONSE" | jq '.errors // [] | length')" -gt 0 ]; then
        echo "Failed to destroy old secret_id"
        echo "$OLD_SECRET_ID_DESTROY_RESPONSE"
        return 0
        # exit 1
    fi
}

complete_action_and_close_intention() {
    echo "=> Action: end"
    curl -s -X POST "$BROKER_ADDR/v1/intention/action/end" -H "X-Broker-Token: $ACTION_TOKEN"

    echo "=> Intention: close"
    curl -s -X POST "$BROKER_ADDR/v1/intention/close" -H "X-Broker-Token: $INTENTION_TOKEN"
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

    echo "Create or update OpenShift secret $OPENSHIFT_SERVICE_SECRET_NAME from Vault path data"
    create_or_update_secret_from_json "$OPENSHIFT_SERVICE_SECRET_NAME" "$VAULT_DATA_JSON"
}

validate_delay_seconds
open_intention_and_start_action
capture_old_secret_id
rotate_secret_id
update_approle_secret
destroy_old_secret_id_with_delay
sync_service_secret
complete_action_and_close_intention
