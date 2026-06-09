set -euo pipefail

REALM="${1:?usage: $0 <realm> <client_id>}"
CID="${2:?usage: $0 <realm> <client_id>}"

KC_URL="${KC_URL:-http://localhost:8080}"
VAULT_ADDR="${VAULT_ADDR:?VAULT_ADDR requis}"
VAULT_TOKEN="${VAULT_TOKEN:?VAULT_TOKEN requis}"

TF_ADMIN_SECRET=$(curl -ksf -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/secret/data/mpg/local/terraform-admin" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['data']['client_secret'])")

ACCESS_TOKEN=$(curl -ksf -X POST \
  "$KC_URL/realms/master/protocol/openid-connect/token" \
  -d "client_id=terraform-admin" \
  -d "client_secret=$TF_ADMIN_SECRET" \
  -d "grant_type=client_credentials" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

CLIENT_UUID=$(curl -ksf -H "Authorization: Bearer $ACCESS_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients?clientId=$CID" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

curl -ksf -H "Authorization: Bearer $ACCESS_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients/$CLIENT_UUID/client-secret" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['value'])"
