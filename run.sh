# === Clients mock ===
# Deux clients par realm mock :
#   - `marketplace-backend-confidential` : caller actif du grant token-exchange
#     (s'authentifie en client_credentials, doit avoir la permission sur l'IdP
#     marketplace, cf. bloc plus bas)
#   - `ccc-apigw` : client "passif" — pas de flow ni de service account.
#     Existe uniquement pour servir de cible résolvable du paramètre `audience`
#     du grant token-exchange. Le claim `aud` des tokens issus du grant pointe
#     vers ce client.
resource "keycloak_openid_client" "ccc_apigw" {
  for_each = local.bp2i_mock_realms

  realm_id    = keycloak_realm.mock[each.key].id
  client_id   = "ccc-apigw"
  name        = "ccc-apigw"
  enabled     = true
  access_type = "CONFIDENTIAL"

  # Aucun flow : pas d'auth interactive ni server-to-server "depuis" ce client.
  # Il est purement la cible des tokens émis "vers" lui par le grant token-exchange.
  standard_flow_enabled        = false
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  # Requis par Keycloak même pour un client passif.
  valid_redirect_uris = ["/*"]
}

