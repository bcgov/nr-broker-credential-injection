#!/usr/bin/env sh

# Validate required environment variables
BROKER_URL="${BROKER_URL:-https://broker.io.nrs.gov.bc.ca}"
VAULT_ADDR="${VAULT_ADDR:-https://knox.io.nrs.gov.bc.ca}"
: "${BROKER_JWT:?BROKER_JWT is required}"
: "${VAULT_ROLE_ID:?VAULT_ROLE_ID is required}"
: "${INTENTION_EVENT_URL:?INTENTION_EVENT_URL is required}"
: "${INTENTION_ENVIRONMENT:?INTENTION_ENVIRONMENT is required}"

INTENTION_TOKEN=""

cleanup() {
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -ne 0 ] && [ -n "$INTENTION_TOKEN" ]; then
        echo "===> Intention close (failure)"
        curl -s -X POST "$BROKER_URL/v1/intention/close?outcome=failure" -H "X-Broker-Token: $INTENTION_TOKEN" || true
    fi
}
trap cleanup EXIT
set -e

PROVISION_NAME=$(jq -r '.actions[0].id' ./config/intention.json)

filename=./output/token.txt

if [ -f "$filename" ]; then
   rm "$filename"
   echo "$filename is removed"
fi

echo "===> Intention open"

# Open intention
RESPONSE=$(curl -s -X POST "$BROKER_URL/v1/intention/open" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $BROKER_JWT" \
    -d "$(jq --arg event_url "$INTENTION_EVENT_URL" --arg user "${INTENTION_USER:-}" --arg env "$INTENTION_ENVIRONMENT" \
        '.event.url=$event_url | (if $user != "" then .user.name=$user else . end) | .actions[0].service.environment=$env' \
        ./config/intention.json)")
echo "$BROKER_URL/v1/intention/open:"
if [ "$(echo "$RESPONSE" | jq '.error')" != "null" ]; then
    echo "Exit: Error detected"
    exit 1
fi

# Save intention token for later
INTENTION_TOKEN=$(echo "$RESPONSE" | jq -r '.token')

echo "===> DB provision"

# Get token for provisioning a db access
DB_INTENTION_TOKEN=$(echo "$RESPONSE" | jq -r ".actions.$PROVISION_NAME.token")

# Start db action
curl -s -X POST "$BROKER_URL/v1/intention/action/start" -H "X-Broker-Token: $DB_INTENTION_TOKEN"

# Get wrapped id for db access
VAULT_TOKEN_WRAP=$(curl -s -X POST "$BROKER_URL/v1/provision/approle/secret-id" \
    -H "X-Broker-Token: $DB_INTENTION_TOKEN" \
    -H "X-Vault-Role-Id: $VAULT_ROLE_ID")
echo "$BROKER_URL/v1/provision/approle/secret-id:"
WRAPPED_VAULT_TOKEN=$(echo "$VAULT_TOKEN_WRAP" | jq -r '.wrap_info.token')

UNWRAPPED_VAULT_TOKEN=$(curl -s -X POST "$VAULT_ADDR/v1/sys/wrapping/unwrap" -H "X-Vault-Token: $WRAPPED_VAULT_TOKEN")
VAULT_SECRET_ID=$(echo "$UNWRAPPED_VAULT_TOKEN" | jq -r '.data.secret_id')

WRAPPED_MY_VAULT_TOKEN=$(curl -s -X POST "$VAULT_ADDR/v1/auth/vs_apps_approle/login" \
    -H "X-Vault-Wrap-TTL: 5m" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg role_id "$VAULT_ROLE_ID" --arg secret_id "$VAULT_SECRET_ID" \
        '{"role_id": $role_id, "secret_id": $secret_id}')")

WRAPPED_TOKEN=$(echo "$WRAPPED_MY_VAULT_TOKEN" | jq -r '.wrap_info.token')

echo "write wrapped token to the shared space"
echo "$WRAPPED_TOKEN" > "$filename"

echo "===> Intention close"

# End db action
curl -s -X POST "$BROKER_URL/v1/intention/action/end" -H "X-Broker-Token: $DB_INTENTION_TOKEN"

# Use saved intention token to close intention
curl -s -X POST "$BROKER_URL/v1/intention/close" -H "X-Broker-Token: $INTENTION_TOKEN"
