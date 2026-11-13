# === Scope mappings du dedicated scope : rôles realm injectés par client ===
# Nécessaire depuis full_scope_allowed = false (défaut Keycloak 27) : les
# rôles realm ne sont plus automatiquement inclus dans les tokens, il faut
# les lister explicitement via le dedicated scope du client.
locals {
  dedicated_role_pairs = flatten([
    for k, _ in var.clients : [
      for role_name in var.catalog[k].dedicated_scope_realm_roles : {
        client_key = k
        role_name  = role_name
      }
    ]
  ])
  dedicated_role_map = {
    for p in local.dedicated_role_pairs : "${p.client_key}/${p.role_name}" => p
  }
}

resource "keycloak_generic_role_mapper" "dedicated_realm_roles" {
  for_each = local.dedicated_role_map

  realm_id  = var.realm_id
  client_id = keycloak_openid_client.oidc[each.value.client_key].id
  role_id   = var.realm_role_ids[each.value.role_name]
}

