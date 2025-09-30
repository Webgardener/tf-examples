Parfait. Voici la **même structure “state-of-the-art”** mise à jour avec **`root.hcl`** au lieu de `terragrunt.hcl`, y compris les `include` corrigés. Backend Terraform toujours sur **GitLab (backend http)**.

# Arborescence

```
infra/
├── live/
│   ├── root.hcl                    # root Terragrunt (nouveau nom)
│   ├── _envcommon/
│   │   ├── env.hcl
│   │   └── providers.hcl
│   ├── dev/
│   │   ├── env.hcl
│   │   ├── network/
│   │   │   └── vpc/terragrunt.hcl
│   │   └── data/
│   │       └── postgres/terragrunt.hcl
│   └── prod/
│       ├── env.hcl
│       ├── network/
│       │   └── vpc/terragrunt.hcl
│       └── data/
│           └── postgres/terragrunt.hcl
└── modules/
    ├── vpc/
    └── postgres/
```

# `live/root.hcl`

```hcl
# live/root.hcl
terraform_version_constraint = ">= 1.7, < 2.0"
terragrunt_version_constraint = ">= 0.58, < 1.0"

locals {
  org               = "monorga"
  project           = "ecommerce"
  app               = "shop"
  env               = regex("(dev|prod)", path_relative_to_include())
  gitlab_project_id = get_env("TG_VAR_GITLAB_PROJECT_ID", "12345678")

  # nom du state = env/app/stack
  state_name_prefix = "${local.env}/${local.app}"

  common_labels = {
    org     = local.org
    project = local.project
    app     = local.app
    env     = local.env
    managed = "terraform"
  }
}

include "providers" {
  path = find_in_parent_folders("_envcommon/providers.hcl")
}

dependency "envcommon" {
  config_path = find_in_parent_folders("_envcommon/env.hcl")
  mock_outputs = {}
  mock_outputs_allowed_terraform_commands = ["validate","plan","apply","destroy","output","graph"]
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    terraform {
      backend "http" {
        address        = "https://gitlab.com/api/v4/projects/${local.gitlab_project_id}/terraform/state/${local.state_name_prefix}-${basename(get_terragrunt_dir())}"
        lock_address   = "https://gitlab.com/api/v4/projects/${local.gitlab_project_id}/terraform/state/${local.state_name_prefix}-${basename(get_terragrunt_dir())}/lock"
        unlock_address = "https://gitlab.com/api/v4/projects/${local.gitlab_project_id}/terraform/state/${local.state_name_prefix}-${basename(get_terragrunt_dir())}/lock"

        username       = "gitlab-ci-token"
        password       = "${get_env("CI_JOB_TOKEN", "")}"  # en local: PAT si besoin
        lock_method    = "POST"
        unlock_method  = "DELETE"
        skip_cert_verification = false
      }
    }
  EOT
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    terraform {
      required_version = ">= 1.7, < 2.0"
      required_providers {
        google = { source = "hashicorp/google", version = "~> 5.40" }
        random = { source = "hashicorp/random", version = "~> 3.6" }
      }
    }
  EOT
}

terraform {
  extra_arguments "common" {
    commands  = ["init","validate","plan","apply","destroy","refresh"]
    arguments = ["-input=false"]
  }
}

inputs = {
  common_labels = local.common_labels
}
```

# Communs

`live/_envcommon/providers.hcl`

```hcl
locals {
  region     = "europe-west1"
  project_id = "gcp-${include.env.locals.env}-${include.env.locals.app}"
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "google" {
      project = "${local.project_id}"
      region  = "${local.region}"
    }
  EOT
}

inputs = {
  region     = local.region
  project_id = local.project_id
}
```

`live/dev/env.hcl` (idem pour `prod/env.hcl` avec valeurs fortes)

```hcl
locals {
  env    = "dev"
  db_tier = "db-custom-2-8"
}
```

# Module 1 (VPC)

`live/dev/network/vpc/terragrunt.hcl`

```hcl
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/infra/modules/vpc"
  # ou: git::https://gitlab.com/monorga/terraform-modules.git//vpc?ref=v1.2.3
}

inputs = {
  name            = "${include.root.locals.app}-${include.root.locals.env}-vpc"
  cidr_block      = "10.10.0.0/16"
  secondary_cidrs = { pods = "10.20.0.0/16", services = "10.30.0.0/16" }
  labels          = merge(include.root.locals.common_labels, { component = "network" })
}
```

# Module 2 (Postgres, dépend du VPC)

`live/dev/data/postgres/terragrunt.hcl`

```hcl
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/infra/modules/postgres"
}

dependency "vpc" {
  config_path = "${get_terragrunt_dir()}/../../network/vpc"
  mock_outputs = { subnet_id = "mock-subnet", network = "mock-network" }
  mock_outputs_allowed_terraform_commands = ["validate","plan"]
}

inputs = {
  instance_name = "${include.root.locals.app}-${include.root.locals.env}-pg"
  machine_tier  = try(dependency.envcommon.outputs.db_tier, "db-custom-2-8")
  network       = dependency.vpc.outputs.network
  subnet_id     = dependency.vpc.outputs.subnet_id
  storage_gb    = 100
  labels        = merge(include.root.locals.common_labels, { component = "database" })
}
```

# Rappels pratiques

* **Backend GitLab** : `username=gitlab-ci-token`, `password=$CI_JOB_TOKEN` en CI.
  En local, exportez un **PAT** dans `CI_JOB_TOKEN` (ou utilisez un backend local).
* **Nom du state** lisible et sans collision : `${env}/${app}-${stack}` via `state_name_prefix`.
* **`root.hcl`** devient votre point d’entrée (pinning versions, providers via `generate`, backend, conventions).
* **`dependency` + `mock_outputs`** pour permettre `plan` sans appliquer les dépendances.
* **Séparation `live/` vs `modules/`** pour garder les modules Terraform portables.

Si tu veux, je te fournis aussi un **`.gitlab-ci.yml` minimal** calé sur cette arbo (jobs `validate/plan/apply` par répertoire) avec cache providers, parallélisation et règles `changes:`.
