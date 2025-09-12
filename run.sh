#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Settings (override via env)
# ----------------------------
: "${GITLAB_BASE_URL:=https://gitlab.com}"
: "${GITLAB_PROJECT_ID:?Set GITLAB_PROJECT_ID (numeric project ID)}"
: "${STATE_PREFIX:=}"             # optional, e.g. "myapp-"
: "${TF_VERSION_MIN:=1.6.0}"

# Pick token header: CI first, otherwise PAT
TOKEN_HEADER=""
if [[ -n "${CI_JOB_TOKEN:-}" ]]; then
  TOKEN_HEADER="JOB-TOKEN: ${CI_JOB_TOKEN}"
elif [[ -n "${GITLAB_TOKEN:-}" ]]; then
  TOKEN_HEADER="Authorization: Bearer ${GITLAB_TOKEN}"
else
  echo "ERROR: Provide CI_JOB_TOKEN (CI) or GITLAB_TOKEN (local PAT)." >&2
  exit 1
fi

# ----------------------------
# Helpers
# ----------------------------
usage() {
  cat <<EOF
Usage:
  $0 <env> <action> [extra terraform args]

Envs:
  local | stg | prd

Actions:
  init        - terraform init with GitLab HTTP backend
  plan        - terraform plan -var-file=terraform.tfvars
  apply       - terraform apply (add -auto-approve to skip prompt)
  destroy     - terraform destroy (add -auto-approve to skip prompt)
  validate    - terraform validate
  fmt         - terraform fmt -recursive
  output      - terraform output
  state       - terraform state list

Examples:
  GITLAB_PROJECT_ID=123456 ./run.sh stg init
  ./run.sh stg plan
  ./run.sh prd apply -auto-approve
  GITLAB_TOKEN=glpat-xxx GITLAB_PROJECT_ID=123456 ./run.sh local init
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }
}

check_tf_version() {
  local v
  v=$(terraform version -json 2>/dev/null | awk -F\" '/terraform_version/{print $4}')
  if [[ -z "$v" ]]; then
    echo "WARNING: cannot detect Terraform version; continuing..."
    return
  fi
  # naive semver compare
  if ! printf "%s\n%s\n" "$TF_VERSION_MIN" "$v" | sort -V | head -n1 | grep -qx "$TF_VERSION_MIN"; then
    echo "ERROR: Terraform >= ${TF_VERSION_MIN} required (found ${v})."
    exit 1
  fi
}

make_backend_file() {
  local env="$1" tmp="$2"
  local state_name="${STATE_PREFIX}${env}"
  local base="${GITLAB_BASE_URL%/}/api/v4/projects/${GITLAB_PROJECT_ID}/terraform/state/${state_name}"

  cat > "$tmp" <<HCL
address        = "${base}"
lock_address   = "${base}/lock"
unlock_address = "${base}/lock"
lock_method    = "POST"
unlock_method  = "DELETE"
retry_wait_min = 5
HCL
}

run_tf() {
  local env="$1"; shift
  local action="$1"; shift || true

  local env_dir="envs/${env}"
  [[ -d "$env_dir" ]] || { echo "Unknown env '${env}' (expected envs/local|stg|prd)"; exit 1; }

  pushd "$env_dir" >/dev/null

  # Create a temp backend config and ensure cleanup
  local tmp_backend
  tmp_backend="$(mktemp -t tf-backend-XXXX.hcl)"
  trap 'rm -f "$tmp_backend"' EXIT
  make_backend_file "$env" "$tmp_backend"

  case "$action" in
    init)
      terraform init \
        -backend-config="$tmp_backend" \
        -backend-config="header=${TOKEN_HEADER}" \
        "$@"
      ;;
    plan)
      terraform init -backend-config="$tmp_backend" -backend-config="header=${TOKEN_HEADER}" -reconfigure >/dev/null
      terraform plan -var-file=terraform.tfvars "$@"
      ;;
    apply)
      terraform init -backend-config="$tmp_backend" -backend-config="header=${TOKEN_HEADER}" -reconfigure >/dev/null
      terraform apply -var-file=terraform.tfvars "$@"
      ;;
    destroy)
      terraform init -backend-config="$tmp_backend" -backend-config="header=${TOKEN_HEADER}" -reconfigure >/dev/null
      terraform destroy -var-file=terraform.tfvars "$@"
      ;;
    validate)
      terraform validate "$@"
      ;;
    fmt)
      terraform fmt -recursive "$@"
      ;;
    output)
      terraform output "$@"
      ;;
    state)
      terraform state list "$@"
      ;;
    *)
      echo "Unknown action: ${action}"
      usage
      exit 1
      ;;
  esac

  popd >/dev/null
}

# ----------------------------
# Main
# ----------------------------
if [[ $# -lt 2 ]]; then
  usage; exit 1
fi

need_cmd terraform
check_tf_version

ENV="$1"; shift
ACTION="$1"; shift || true

run_tf "$ENV" "$ACTION" "$@"
