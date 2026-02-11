Here is a clean and professional README section you can use for your Terraform module 👇

---

# Terraform Module – Vault Kubernetes Auth (ROKS)

## Overview

This module configures the **Vault Kubernetes authentication method** for a specific ROKS cluster and workload.

It creates and configures:

* A Kubernetes auth mount in Vault
* The Kubernetes auth backend configuration (`kubernetes_host`, CA, reviewer JWT, audience)
* A Vault role bound to a specific Kubernetes ServiceAccount and namespace
* Associated Vault policies

This module is designed for **external Vault deployments** authenticating workloads running in ROKS.

---

## What This Module Configures

### 1. Kubernetes Auth Backend

The module configures the Vault Kubernetes auth backend with:

* `kubernetes_host`
  → The ROKS API endpoint (typically from `oc whoami --show-server`)

* `kubernetes_ca_cert`
  → The CA certificate that validates the ROKS API server TLS certificate

* `token_reviewer_jwt`
  → A ServiceAccount token from the ROKS cluster with `system:auth-delegator` permissions

* `audience` (optional)
  → Must match the `aud` claim in workload ServiceAccount tokens

---

### 2. Vault Role

A Vault role is created with:

* `bound_service_account_names`
* `bound_service_account_namespaces`
* Attached Vault policies
* Token TTL / max TTL configuration

This ensures that only the specified Kubernetes ServiceAccount in the specified namespace can authenticate.

---

## Example Usage

```hcl
module "vault_k8s_auth" {
  source = "./modules/vault-kubernetes-auth"

  vault_namespace = "AP26541"

  mount_path      = "kubernetes_ns_app"
  role_name       = "kubernetes-app"

  kubernetes_host       = "https://api.cluster.example.com:6443"
  kubernetes_ca_cert    = file("${path.module}/roks-ca.crt")
  token_reviewer_jwt    = var.token_reviewer_jwt
  audience              = "openshift"

  service_account_name      = "default"
  service_account_namespace = "my-namespace"

  policies = ["my-app-policy"]
}
```

---

## Prerequisites

Before using this module:

1. A ServiceAccount with `system:auth-delegator` must exist in the ROKS cluster.
2. A valid reviewer JWT must be generated from that ServiceAccount.
3. The ROKS API CA certificate must be retrieved.
4. The Vault Enterprise namespace must already exist (if applicable).

---

## Common Failure Modes

If authentication fails with:

```
403 permission denied
```

Verify:

* `kubernetes_host` matches the ROKS API endpoint.
* The CA certificate corresponds to the ROKS API.
* The reviewer JWT was generated from the correct cluster and is still valid.
* The role’s bound ServiceAccount name and namespace match the workload.
* The audience matches the ServiceAccount token `aud` claim.

---

## Security Considerations

* Reviewer JWTs should be rotated regularly if short-lived.
* Do not reuse reviewer tokens across clusters.
* Avoid hardcoding reviewer tokens in source control.
* Limit Vault role bindings to specific ServiceAccounts and namespaces.

---

If you'd like, I can also generate:

* A diagram version (Vault ↔ ROKS flow)
* A shorter enterprise-style README
* Or a version tailored to your internal platform standards
