##########################
# Variables & Locals
##########################

# Pour chaque namespace, liste des ServiceAccounts autorisés à s’authentifier
variable "vault_namespaces" {
  description = "Namespaces Kubernetes qui utilisent Vault, avec leurs ServiceAccounts autorisés."
  type        = map(list(string))

  # Exemple à adapter
  default = {
    backend  = ["vault-client", "api-backend"]
    frontend = ["vault-client"]
    # prod     = ["vault-client"]
  }
}

# Produit (namespace, serviceAccount) pour créer les alias
locals {
  ns_sa_pairs = flatten([
    for ns, sa_list in var.vault_namespaces : [
      for sa in sa_list : {
        ns = ns
        sa = sa
      }
    ]
  ])
}

##########################
# Provider & Backend K8s
##########################

provider "vault" {
  # address = "https://vault.example.com"  # si besoin
  # token   = var.vault_token              # ou via VAULT_TOKEN
}

data "vault_auth_backend" "kubernetes" {
  # Chemin de ton backend Kubernetes, adapter si différent
  path = "auth/kubernetes"
}

##########################
# 1 Entity par Namespace
##########################

resource "vault_identity_entity" "ns" {
  for_each = var.vault_namespaces

  # Nom logique de l’entity, ex : k8s-backend, k8s-frontend
  name = "k8s-${each.key}"

  # Pas de policies attachées directement à l’entity (comme demandé)
  # policies = []
}

##########################
# Alias (Namespace, ServiceAccount)
##########################

resource "vault_identity_entity_alias" "ns_sa" {
  for_each = {
    for pair in local.ns_sa_pairs :
    "${pair.ns}-${pair.sa}" => pair
  }

  # Nom du ServiceAccount (tel qu’il apparaît dans le token K8s)
  name           = each.value.sa
  mount_accessor = data.vault_auth_backend.kubernetes.accessor

  # Tous les SAs d’un même namespace pointent vers la même entity
  canonical_id = vault_identity_entity.ns[each.value.ns].id

  # Metadata purement informative
  metadata = {
    service_account_name      = each.value.sa
    service_account_namespace = each.value.ns
  }
}

##########################
# Rôle Kubernetes Auth par Namespace
##########################

resource "vault_kubernetes_auth_backend_role" "ns" {
  for_each = var.vault_namespaces

  backend   = data.vault_auth_backend.kubernetes.path
  role_name = "ns-${each.key}" # ex: ns-backend, ns-frontend

  # Restreint aux SAs explicitement listés pour ce namespace
  bound_service_account_names      = each.value
  bound_service_account_namespaces = [each.key]

  # Pas de policies spécifiques au token ici (comme demandé)
  # token_policies = []
  token_ttl = 3600
}
