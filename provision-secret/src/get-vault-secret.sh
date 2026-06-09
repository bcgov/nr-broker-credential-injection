#!/usr/bin/env sh

# Validate required environment variables
BROKER_URL="${BROKER_URL:-https://broker.io.nrs.gov.bc.ca}"
VAULT_ADDR="${VAULT_ADDR:-https://knox.io.nrs.gov.bc.ca}"
OPENSHIFT_SECRET_NAME="${OPENSHIFT_SECRET_NAME:-vault-secret}"
OPENSHIFT_TOKEN_KEY="${OPENSHIFT_TOKEN_KEY:-token}"
OPENSHIFT_ROLE_KEY="${OPENSHIFT_ROLE_KEY:-role}"
OPENSHIFT_SECRET_ID_KEY="${OPENSHIFT_SECRET_ID_KEY:-secret_id}"
: "${BROKER_JWT:?BROKER_JWT is required}"
: "${INTENTION_EVENT_URL:?INTENTION_EVENT_URL is required}"
: "${INTENTION_ENVIRONMENT:?INTENTION_ENVIRONMENT is required}"
: "${VAULT_ROLE_ID:?VAULT_ROLE_ID is required}"

INTENTION_TOKEN=""

cleanup() {
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -ne 0 ] && [ -n "$INTENTION_TOKEN" ]; then
        echo "=> Intention: close (failure)"
        curl -s -X POST "$BROKER_URL/v1/intention/close?outcome=failure" -H "X-Broker-Token: $INTENTION_TOKEN" || true
    fi
}
trap cleanup EXIT
set -e

PROVISION_NAME=$(jq -r '.actions[0].id' ./config/intention.json)

echo "=> Intention: open ($BROKER_URL)"

# Open intention
RESPONSE=$(curl -s -X POST "$BROKER_URL/v1/intention/open" \
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
curl -s -X POST "$BROKER_URL/v1/intention/action/start" -H "X-Broker-Token: $ACTION_TOKEN"

# Get wrapped id for access
echo "Get wrapped vault token from broker"
VAULT_TOKEN_WRAP=$(curl -s -X POST "$BROKER_URL/v1/provision/approle/secret-id" \
    -H "X-Broker-Token: $ACTION_TOKEN" \
    -H "X-Vault-Role-Id: $VAULT_ROLE_ID")
WRAPPED_VAULT_TOKEN=$(echo "$VAULT_TOKEN_WRAP" | jq -r '.wrap_info.token')

echo "Unwrapped vault token for secret_id"
UNWRAPPED_VAULT_TOKEN=$(curl -s -X POST "$VAULT_ADDR/v1/sys/wrapping/unwrap" -H "X-Vault-Token: $WRAPPED_VAULT_TOKEN")
VAULT_SECRET_ID=$(echo "$UNWRAPPED_VAULT_TOKEN" | jq -r '.data.secret_id')

echo "Create or update OpenShift secret $OPENSHIFT_SECRET_NAME with AppRole credentials"
kubectl create secret generic "$OPENSHIFT_SECRET_NAME" \
    --from-literal="$OPENSHIFT_TOKEN_KEY=$BROKER_JWT" \
    --from-literal="$OPENSHIFT_ROLE_KEY=$VAULT_ROLE_ID" \
    --from-literal="$OPENSHIFT_SECRET_ID_KEY=$VAULT_SECRET_ID" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

echo "Success! Secret ID saved to OpenShift secret $OPENSHIFT_SECRET_NAME"

echo "=> Action: end"
# End action
curl -s -X POST "$BROKER_URL/v1/intention/action/end" -H "X-Broker-Token: $ACTION_TOKEN"

echo "=> Intention: close"
# Use saved intention token to close intention
curl -s -X POST "$BROKER_URL/v1/intention/close" -H "X-Broker-Token: $INTENTION_TOKEN"
