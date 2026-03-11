#!/usr/bin/env sh

# Validate required environment variables
BROKER_URL="${BROKER_URL:-https://broker.io.nrs.gov.bc.ca}"
VAULT_ADDR="${VAULT_ADDR:-https://knox.io.nrs.gov.bc.ca}"
: "${BROKER_JWT:?BROKER_JWT is required}"
: "${ROLE_ID:?ROLE_ID is required}"
: "${EVENT_URL:?EVENT_URL is required}"
: "${USER:?USER is required}"
: "${ENVIRONMENT:?ENVIRONMENT is required}"

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
    -d "$(jq --arg event_url "$EVENT_URL" --arg user "$USER" --arg env "$ENVIRONMENT" \
        '.event.url=$event_url | .user.name=$user | .actions[0].service.environment=$env' \
        ./config/intention.json)")
echo "$BROKER_URL/v1/intention/open:"
if [ "$(echo "$RESPONSE" | jq '.error')" != "null" ]; then
    echo "Exit: Error detected"
    exit 0
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
    -H "X-Vault-Role-Id: $ROLE_ID")
echo "$BROKER_URL/v1/provision/approle/secret-id:"
WRAPPED_VAULT_TOKEN=$(echo "$VAULT_TOKEN_WRAP" | jq -r '.wrap_info.token')

UNWRAPPED_VAULT_TOKEN=$(curl -s -X POST "$VAULT_ADDR/v1/sys/wrapping/unwrap" -H "X-Vault-Token: $WRAPPED_VAULT_TOKEN")
SECRET_ID=$(echo "$UNWRAPPED_VAULT_TOKEN" | jq -r '.data.secret_id')

WRAPPED_MY_VAULT_TOKEN=$(curl -s -X POST "$VAULT_ADDR/v1/auth/vs_apps_approle/login" \
    -H "X-Vault-Wrap-TTL: 5m" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg role_id "$ROLE_ID" --arg secret_id "$SECRET_ID" \
        '{"role_id": $role_id, "secret_id": $secret_id}')")

WRAPPED_TOKEN=$(echo "$WRAPPED_MY_VAULT_TOKEN" | jq -r '.wrap_info.token')

echo "write wrapped token to the shared space"
echo "$WRAPPED_TOKEN" > "$filename"

echo "===> Intention close"

# End db action
curl -s -X POST "$BROKER_URL/v1/intention/action/end" -H "X-Broker-Token: $DB_INTENTION_TOKEN"

# Use saved intention token to close intention
curl -s -X POST "$BROKER_URL/v1/intention/close" -H "X-Broker-Token: $INTENTION_TOKEN"
