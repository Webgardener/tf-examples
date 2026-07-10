# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------

locals {
  # Mapping clé Vault -> client Keycloak
  realm_clients = {
    MPG_AUTH_TOKEN = { realm = keycloak_realm.mpg.id, client_id = "mpg-client" }
    FOO_AUTH_TOKEN = { realm = keycloak_realm.foo.id, client_id = "foo-client" }
    BAR_AUTH_TOKEN = { realm = keycloak_realm.bar.id, client_id = "bar-client" }
  }

  # Clés existantes, aplaties en string -> string
  other_keys = {
    for k, v in jsondecode(file("${path.module}/mpg_secrets.json")) :
    k => can(tostring(v)) ? tostring(v) : jsonencode(v)
  }

  # Secrets générés par Keycloak, lus en computed
  auth_tokens = {
    for k, _ in local.realm_clients :
    k => keycloak_openid_client.this[k].client_secret
  }
}

# ---------------------------------------------------------------------------
# Clients Keycloak
# ---------------------------------------------------------------------------

resource "keycloak_openid_client" "this" {
  for_each = local.realm_clients

  realm_id    = each.value.realm
  client_id   = each.value.client_id
  access_type = "CONFIDENTIAL"

  standard_flow_enabled    = true
  service_accounts_enabled = true

  # client_secret non défini -> Keycloak le génère
}

# ---------------------------------------------------------------------------
# Secret Vault (KV v2) - nouvelle version à chaque changement
# ---------------------------------------------------------------------------

resource "vault_kv_secret_v2" "workload" {
  mount               = "secret"
  name                = "${var.application}/secrets" # pas de /data/ ici
  delete_all_versions = true

  data_json = jsonencode(merge(local.other_keys, local.auth_tokens))

  depends_on = [keycloak_openid_client.this]

  lifecycle {
    precondition {
      condition = length(setintersection(
        keys(local.other_keys),
        keys(local.auth_tokens),
      )) == 0
      error_message = "Collision de clés entre mpg_secrets.json et les tokens Keycloak."
    }
  }
}

# ---------------------------------------------------------------------------
# Sortie utile pour le rollout du workload
# ---------------------------------------------------------------------------

output "workload_secret_checksum" {
  description = "Hash du contenu du secret, à injecter en annotation sur le PodSpec."
  value       = sha256(jsonencode(merge(local.other_keys, local.auth_tokens)))
  sensitive   = false
}
