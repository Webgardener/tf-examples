terraform {
  required_version = ">= 1.5"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "5.0.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "4.5.0"
    }
  }

  # State local et jetable : il ne survit pas à Vault (inmem).
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "keycloak" {
  client_id = "admin-cli"
  username  = var.keycloak_admin_user
  password  = var.keycloak_admin_password
  url       = var.keycloak_url

  # Keycloak est joignable via le frontdoor, préfixe /auth stripé par nginx.
  base_path = ""
}

provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}


variable "application" {
  description = "Nom applicatif, utilisé comme préfixe du path KV."
  type        = string
  default     = "mpg"
}

variable "keycloak_url" {
  type    = string
  default = "https://marketplace.cmoi.local/auth"
}

variable "keycloak_admin_user" {
  type    = string
  default = "admin"
}

variable "keycloak_admin_password" {
  type      = string
  sensitive = true
}

variable "vault_addr" {
  type    = string
  default = "http://vault.green.svc.cluster.local:8200"
}

variable "vault_token" {
  description = "Root token du Vault dev (fixe : root)."
  type        = string
  default     = "root"
  sensitive   = true
}

variable "secrets_file" {
  description = "JSON des clés existantes, versionné dans le repo."
  type        = string
  default     = "mpg_secrets.json"
}




locals {
  # Clé Vault -> client Keycloak. Seul endroit à modifier pour ajouter un realm.
  realm_clients = {
    MPG_AUTH_TOKEN = { realm = "mpg", client_id = "mpg-client" }
    FOO_AUTH_TOKEN = { realm = "foo", client_id = "foo-client" }
    BAR_AUTH_TOKEN = { realm = "bar", client_id = "bar-client" }
  }

  # Clés existantes, aplaties en string -> string.
  other_keys = {
    for k, v in jsondecode(file("${path.module}/${var.secrets_file}")) :
    k => can(tostring(v)) ? tostring(v) : jsonencode(v)
  }

  auth_tokens = {
    for k, _ in local.realm_clients :
    k => data.keycloak_openid_client.this[k].client_secret
  }
}

# Lecture seule : les clients sont provisionnés par tf-config-keycloak.
data "keycloak_openid_client" "this" {
  for_each = local.realm_clients

  realm_id  = each.value.realm
  client_id = each.value.client_id
}

resource "vault_kv_secret_v2" "workload" {
  mount               = "secret"
  name                = "${var.application}/secrets" # sans /data/
  delete_all_versions = true

  data_json = jsonencode(merge(local.other_keys, local.auth_tokens))

  lifecycle {
    precondition {
      condition = length(setintersection(
        keys(local.other_keys),
        keys(local.auth_tokens),
      )) == 0
      error_message = "Collision de clés entre ${var.secrets_file} et les tokens Keycloak."
    }

    precondition {
      condition = alltrue([
        for k, _ in local.realm_clients :
        data.keycloak_openid_client.this[k].client_secret != ""
      ])
      error_message = "client_secret vide : le client doit être CONFIDENTIAL et le compte Terraform avoir view-clients."
    }
  }
}



VAULT_SEED_DIR := terraform/vault-seed

.PHONY: tf-vault-seed
tf-vault-seed:
	rm -f $(VAULT_SEED_DIR)/terraform.tfstate $(VAULT_SEED_DIR)/terraform.tfstate.backup
	terraform -chdir=$(VAULT_SEED_DIR) init -upgrade
	terraform -chdir=$(VAULT_SEED_DIR) apply -auto-approve

.PHONY: rollout-workload
rollout-workload:
	kubectl -n green rollout restart deployment/mpg-app
	kubectl -n green rollout status deployment/mpg-app --timeout=180s
