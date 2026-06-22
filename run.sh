# Scaffolding local-only : reproduit dans le même Keycloak les **instances
# Keycloak BP2I** qui vivent normalement ailleurs dans le SI client (bp2i,
# bp2i-dmzrac, …). Ces Keycloaks ne sont PAS des IdP utilisateur — ce sont
# des Keycloaks "consommateurs" qui émettent leurs propres tokens à des
# backends, à partir d'identités fédérées depuis mpg via un IdP OIDC nommé
# `marketplace` dans chaque realm mock.
#
# (À ne pas confondre avec WebSSO : WebSSO est l'IdP utilisateur du realm mpg
# en staging/prod, simulé en local par l'auth directe sur mpg via le browser
# flow `browser-with-acr`. WebSSO et les Keycloak BP2I ne se mockent pas au
# même endroit.)
#
# Flux complet :
#   1. Auth user initiale → realm mpg directement (mpg-client → browser-with-acr
#      → user/password). Aucun realm mock n'intervient à ce stade.
#   2. Quand le backend MPG a besoin d'appeler une API derrière l'API gateway
#      BP2I, il invoque le grant token-exchange via son OIDC client
#      `marketplace-backend-confidential` contre l'IdP `marketplace` du realm
#      mock concerné, en présentant ses propres credentials, un subject_token
#      (token mpg) et `audience=ccc-apigw`. Le realm mock — via l'IdP
#      marketplace qui pointe vers mpg — valide le subject_token, crée le user
#      localement à la 1re fois (flow `first broker login no-form`, sans
#      review-profile), puis émet un token mock pour le client `ccc-apigw`
#      (claim `aud` = `ccc-apigw`).
#
# `ccc-apigw` n'est pas un client "actif" : il n'a ni service account ni
# standard flow. Il existe uniquement pour servir de cible résolvable du
# paramètre `audience` du grant token-exchange (sans ça, Keycloak renvoie
# "audience not found").
#
# Les URLs (authorization, token, JWKS, issuer) de l'IdP marketplace sont
# dérivées de `local.config.keycloak_url` — fonctionne aussi bien sur la stack
# de test (http://localhost:8080) que sur l'env dev cible si keycloak_url
# pointe sur https://<host>/auth.
#
# Ajouter un nouveau realm mock = ajouter une entrée dans local.bp2i_mock_realms,
# rien d'autre ne change. Chaque entrée DOIT référencer un client distinct côté
# mpg (sinon les redirect URIs broker entrent en conflit).
#
# N'existe que dans envs/local/ : staging et production utilisent les vrais
# Keycloak BP2I, pas de realm mock. La présence du fichier vaut activation.

locals {
  # Map des realms mock : clé = nom du realm, valeur = config IdP.
  # idp_client_id désigne un client du realm mpg ; son client_secret est
  # résolu au point d'usage via module.clients.client_secrets[idp_client_id]
  # (pas porté dans la map ici, pour ne pas dupliquer la dérivation).
  bp2i_mock_realms = {
    "bp2i" = {
      display_name  = "bp2i (mock local)"
      idp_client_id = "keycloak-bp2i"
    }
    "bp2i-dmzrac" = {
      display_name  = "bp2i-dmzrac (mock local)"
      idp_client_id = "keycloak-bp2i-orchestrator"
    }
    "bp2i-pprod" = {
      display_name  = "bp2i-pprod (mock local)"
      idp_client_id = "keycloak-bp2i-orchestrator-pprod"
    }
  }

  mpg_issuer = "${local.config.keycloak_url}/realms/${local.config.realm.name}"

  # Backchannel URL : utilisée par Keycloak lui-même (pod) pour les appels
  # server-to-server (userinfo, jwks, token quand il acte comme client).
  # Forme : http(s)://<svc>.<ns>.svc.cluster.local:<port>/<path>/realms/...
  # Sur l'env dev cible :
  #   https://mpg-keycloak.shared.svc.cluster.local:10443/realms/<realm>
  #   (svc=mpg-keycloak, ns=shared, port HTTPS interne, pas de relative path)
  # En local : http://keycloak.mpg.svc.cluster.local:8080/auth/realms/<realm>
  #   (svc=keycloak, ns=mpg, HTTP, KC_HTTP_RELATIVE_PATH=/auth).
  mpg_backchannel = "http://keycloak.mpg.svc.cluster.local:8080/auth/realms/${local.config.realm.name}"
}

# === Realms mock ===
resource "keycloak_realm" "mock" {
  for_each = local.bp2i_mock_realms

  realm        = each.key
  enabled      = true
  display_name = each.value.display_name
}

# Events activés sur chaque mock pour debug (login, federation, errors).
# `jboss-logging` aligne avec mpg ; les WARN apparaissent dans `make logs-keycloak`.
resource "keycloak_realm_events" "mock" {
  for_each = local.bp2i_mock_realms

  realm_id                     = keycloak_realm.mock[each.key].id
  events_enabled               = true
  events_expiration            = 604800
  admin_events_enabled         = true
  admin_events_details_enabled = true
  events_listeners             = ["jboss-logging"]
}

# Active "Unmanaged Attributes" sur le user profile de chaque realm mock —
# nécessaire pour que les attributs custom poussés par l'IdP marketplace lors
# du first broker login soient acceptés tels quels (sinon Keycloak les rejette
# si pas déclarés). On redéclare aussi les 4 attributs par défaut Keycloak
# (username, email, firstName, lastName) sinon la ressource les écrase.
resource "keycloak_realm_user_profile" "mock" {
  for_each = local.bp2i_mock_realms

  realm_id                   = keycloak_realm.mock[each.key].id
  unmanaged_attribute_policy = "ENABLED"

  attribute {
    name         = "username"
    display_name = "$${username}"
    permissions {
      view = ["admin", "user"]
      edit = ["admin", "user"]
    }
    validator {
      name = "length"
      config = {
        min = "3"
        max = "255"
      }
    }
    validator {
      name = "username-prohibited-characters"
    }
    validator {
      name = "up-username-not-idn-homograph"
    }
  }

  attribute {
    name               = "email"
    display_name       = "$${email}"
    required_for_roles = ["user"]
    permissions {
      view = ["admin", "user"]
      edit = ["admin", "user"]
    }
    validator {
      name = "email"
    }
    validator {
      name = "length"
      config = {
        max = "255"
      }
    }
  }

  attribute {
    name         = "firstName"
    display_name = "$${firstName}"
    permissions {
      view = ["admin", "user"]
      edit = ["admin", "user"]
    }
    validator {
      name = "length"
      config = {
        max = "255"
      }
    }
    validator {
      name = "person-name-prohibited-characters"
    }
  }

  attribute {
    name         = "lastName"
    display_name = "$${lastName}"
    permissions {
      view = ["admin", "user"]
      edit = ["admin", "user"]
    }
    validator {
      name = "length"
      config = {
        max = "255"
      }
    }
    validator {
      name = "person-name-prohibited-characters"
    }
  }
}

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
  # Keycloak rejette `valid_redirect_uris` quand aucun flow n'est activé, d'où
  # l'absence du champ ici.
  standard_flow_enabled        = false
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
}

resource "keycloak_openid_client" "marketplace_backend" {
  for_each = local.bp2i_mock_realms

  realm_id    = keycloak_realm.mock[each.key].id
  client_id   = "marketplace-backend-confidential"
  name        = "marketplace-backend-confidential"
  enabled     = true
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = true
  # Authorization fine-grained exige un service account (reçoit le rôle uma_protection).
  service_accounts_enabled    = true
  frontchannel_logout_enabled = true

  # spec : "valid redirect URI: *"
  valid_redirect_uris = ["*"]
  web_origins         = ["/*"]

  authorization {
    policy_enforcement_mode          = "ENFORCING"
    allow_remote_resource_management = true
  }
}

# === Flow first-broker-login-no-form ===
# Version minimale : juste idp-create-user-if-unique en ALTERNATIVE. Skip le
# step "Review Profile" du flow Keycloak par défaut.
resource "keycloak_authentication_flow" "first_broker_login_no_form" {
  for_each = local.bp2i_mock_realms

  realm_id    = keycloak_realm.mock[each.key].id
  alias       = "first broker login no-form"
  description = "First broker login simplifié (skip review-profile)"
}

resource "keycloak_authentication_execution" "create_user_if_unique" {
  for_each = local.bp2i_mock_realms

  realm_id          = keycloak_realm.mock[each.key].id
  parent_flow_alias = keycloak_authentication_flow.first_broker_login_no_form[each.key].alias
  authenticator     = "idp-create-user-if-unique"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

# === IdP marketplace : broker vers le realm mpg ===
resource "keycloak_oidc_identity_provider" "marketplace" {
  for_each = local.bp2i_mock_realms

  realm        = keycloak_realm.mock[each.key].id
  alias        = "marketplace"
  display_name = "marketplace"

  # Endpoints OIDC du realm mpg.
  # - frontchannel (browser-facing) : authorization, logout → https public
  # - backchannel (Keycloak server-to-server, utilisé entre autres pour
  #   token_url/jwks_url/user_info_url) → DNS cluster interne, pas de TLS.
  # Reproduit la séparation typique de l'env dev cible.
  authorization_url = "${local.mpg_issuer}/protocol/openid-connect/auth"
  logout_url        = "${local.mpg_issuer}/protocol/openid-connect/logout"
  token_url         = "${local.mpg_backchannel}/protocol/openid-connect/token"

  # Issuer attendu dans les tokens reçus de mpg (validé contre le claim `iss`).
  issuer = local.mpg_issuer

  # ClientId/secret côté upstream (= un client du realm mpg, distinct par mock
  # pour que les redirect URIs broker n'entrent pas en conflit). Le secret est
  # résolu via la map générique du module clients.
  client_id     = each.value.idp_client_id
  client_secret = module.clients.client_secrets[each.value.idp_client_id]

  validate_signature = true
  jwks_url           = "${local.mpg_backchannel}/protocol/openid-connect/certs"

  # accessTokenIsJwt=false (cf. extra_config plus bas) → Keycloak valide les
  # subject_tokens via le userinfo endpoint de l'IdP, pas via signature JWT.
  # Backchannel (cluster DNS) car appelée depuis le pod Keycloak — le hostname
  # public marketplace.cmoi.local n'y résout pas.
  user_info_url = "${local.mpg_backchannel}/protocol/openid-connect/userinfo"

  # Token storage : on n'a pas besoin de stocker le token externe côté Keycloak.
  store_token                   = false
  add_read_token_role_on_create = false

  trust_email = true

  # IMPORT : crée le user à la 1re fédération, puis ré-utilise tel quel
  # ensuite (pas de force-refresh des attributs sur chaque login). FORCE
  # rafraîchit à chaque login.
  sync_mode = "IMPORT"

  # link_only=true : l'IdP n'apparaît PAS sur la page de login standard et
  # ne peut être invoqué via auth code flow + kc_idp_hint. Reste utilisable
  # via le grant token-exchange (= ce que fait notre mock app et l'app cible).
  link_only = true

  first_broker_login_flow_alias = keycloak_authentication_flow.first_broker_login_no_form[each.key].alias
  post_broker_login_flow_alias  = "" # explicitement aucun

  # Provider 5.x : useJwksUrl, pkceEnabled, clientAuthMethod, accessTokenIsJwt
  # ne sont pas exposés comme attributs natifs ; passage par extra_config
  # (clés Keycloak server).
  extra_config = {
    "pkceEnabled"      = "false"
    "clientAuthMethod" = "client_secret_post"
    "accessTokenIsJwt" = "false"
  }
}

# === Permission token-exchange sur l'IdP marketplace ===
# Active la fine-grained permission "token-exchange" sur l'IdP marketplace
# de chaque mock realm, et autorise marketplace-backend-confidential (le caller
# côté MPG) à l'invoquer. Sans ça, link_only=true bloque tout (le grant
# token-exchange n'est utilisable que si le client appelant a explicitement
# la permission).
# Requiert features Keycloak: token-exchange + admin-fine-grained-authz:v1.
resource "keycloak_identity_provider_token_exchange_scope_permission" "marketplace" {
  for_each = local.bp2i_mock_realms

  realm_id       = keycloak_realm.mock[each.key].id
  provider_alias = keycloak_oidc_identity_provider.marketplace[each.key].alias
  clients        = [keycloak_openid_client.marketplace_backend[each.key].id]
}

# === Permission token-exchange ciblant le client ccc-apigw ===
# Avec admin-fine-grained-authz:v1, autoriser le caller sur l'IdP ne suffit
# pas : Keycloak vérifie aussi que le caller a la permission "token-exchange"
# sur le **client cible** (l'audience). Sans ce bloc, on obtient
# `access_denied: Client not allowed to exchange`.
#
# Les permissions fine-grained vivent dans le client built-in `realm-management`
# de chaque realm (Keycloak les stocke comme des resources d'authorization de
# ce client). On récupère donc son UUID via data source, puis :
#  - une "client policy" qui dit "le caller autorisé = marketplace-backend-confidential"
#  - le bloc token_exchange_scope sur ccc-apigw qui consomme cette policy
data "keycloak_openid_client" "realm_management" {
  for_each = local.bp2i_mock_realms

  realm_id  = keycloak_realm.mock[each.key].id
  client_id = "realm-management"
}

resource "keycloak_openid_client_client_policy" "allow_marketplace_backend" {
  for_each = local.bp2i_mock_realms

  realm_id           = keycloak_realm.mock[each.key].id
  resource_server_id = data.keycloak_openid_client.realm_management[each.key].id
  name               = "allow-marketplace-backend-confidential"
  description        = "Autorise marketplace-backend-confidential à invoquer les permissions fine-grained de ce realm"
  logic              = "POSITIVE"
  decision_strategy  = "AFFIRMATIVE"
  clients            = [keycloak_openid_client.marketplace_backend[each.key].id]
}

resource "keycloak_openid_client_permissions" "ccc_apigw" {
  for_each = local.bp2i_mock_realms

  realm_id  = keycloak_realm.mock[each.key].id
  client_id = keycloak_openid_client.ccc_apigw[each.key].id

  token_exchange_scope {
    policies          = [keycloak_openid_client_client_policy.allow_marketplace_backend[each.key].id]
    description       = "Allow marketplace-backend-confidential to token-exchange into ccc-apigw"
    decision_strategy = "AFFIRMATIVE"
  }
}

