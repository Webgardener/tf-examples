#!/usr/bin/env sh
set -eu

# -------- Settings (override via env) --------
GITLAB_BASE_URL="${GITLAB_BASE_URL:-https://gitlab.com}"
GITLAB_PROJECT_ID="${GITLAB_PROJECT_ID:-}"    # required for stg/prd
STATE_PREFIX="${STATE_PREFIX:-}"              # optional, e.g. "myapp-"
ENV_DIR_ROOT="${ENV_DIR_ROOT:-envs}"         # env folders live here

# -------- Helpers --------
usage() {
  cat <<EOF
Usage:
  $0 <env> <action> [extra terraform args]

Envs:    local | stg | prd
Actions: init | plan | apply | destroy | validate | fmt | output | state

Examples:
  GITLAB_PROJECT_ID=123456 ./run.sh stg init
  ./run.sh stg plan
  ./run.sh prd apply -auto-approve
  ./run.sh local plan -var 'project_id=my-local-proj'
Env vars:
  GITLAB_BASE_URL   (default: https://gitlab.com)
  GITLAB_PROJECT_ID (required for stg/prd)
  STATE_PREFIX      (optional, e.g. "myapp-")
  ENV_DIR_ROOT      (default: envs)
  CI_JOB_TOKEN or GITLAB_TOKEN must be set for stg/prd
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }
}

mk_backend_file() {
  # $1 env, $2 tmpfile
  env="$1"; tmp="$2"
  base="${GITLAB_BASE_URL%/}/api/v4/projects/${GITLAB_PROJECT_ID}/terraform/state/${STATE_PREFIX}${env}"
  cat > "$tmp" <<HCL
address        = "${base}"
lock_address   = "${base}/lock"
unlock_address = "${base}/lock"
lock_method    = "POST"
unlock_method  = "DELETE"
retry_wait_min = 5
HCL
}

var_args() {
  # echo optional -var-file if present
  if [ -f "terraform.tfvars" ]; then
    printf "%s" "-var-file=terraform.tfvars"
  fi
}

run_local() {
  action="$1"; shift || true
  case "$action" in
    init)    terraform init "$@";;
    plan)    terraform init -reconfigure >/dev/null; terraform plan $(var_args) "$@";;
    apply)   terraform init -reconfigure >/dev/null; terraform apply $(var_args) "$@";;
    destroy) terraform init -reconfigure >/dev/null; terraform destroy $(var_args) "$@";;
    validate) terraform validate "$@";;
    fmt)      terraform fmt -recursive "$@";;
    output)   terraform output "$@";;
    state)    terraform state list "$@";;
    *) echo "Unknown action: $action"; usage; exit 1;;
  esac
}

run_remote() {
  env="$1"; action="$2"; shift 2 || true

  # Pick token header: CI first, else PAT
  if [ -n "${CI_JOB_TOKEN:-}" ]; then
    TOKEN_HEADER="JOB-TOKEN: ${CI_JOB_TOKEN}"
  elif [ -n "${GITLAB_TOKEN:-}" ]; then
    TOKEN_HEADER="Authorization: Bearer ${GITLAB_TOKEN}"
  else
    echo "ERROR: Provide CI_JOB_TOKEN or GITLAB_TOKEN for env '$env'." >&2
    exit 1
  fi

  # Require project ID for remote
  if [ -z "${GITLAB_PROJECT_ID}" ]; then
    echo "ERROR: GITLAB_PROJECT_ID is required for env '$env'." >&2
    exit 1
  fi

  tmp_backend="$(mktemp -t tf-backend-XXXX.hcl)"
  trap 'rm -f "$tmp_backend"' EXIT
  mk_backend_file "$env" "$tmp_backend"

  case "$action" in
    init)
      terraform init \
        -backend-config="$tmp_backend" \
        -backend-config="header=${TOKEN_HEADER}" "$@"
      ;;
    plan)
      terraform init -reconfigure \
        -backend-config="$tmp_backend" \
        -backend-config="header=${TOKEN_HEADER}" >/dev/null
      terraform plan $(var_args) "$@"
      ;;
    apply)
      terraform init -reconfigure \
        -backend-config="$tmp_backend" \
        -backend-config="header=${TOKEN_HEADER}" >/dev/null
      terraform apply $(var_args) "$@"
      ;;
    destroy)
      terraform init -reconfigure \
        -backend-config="$tmp_backend" \
        -backend-config="header=${TOKEN_HEADER}" >/dev/null
      terraform destroy $(var_args) "$@"
      ;;
    validate) terraform validate "$@";;
    fmt)      terraform fmt -recursive "$@";;
    output)   terraform output "$@";;
    state)    terraform state list "$@";;
    *) echo "Unknown action: $action"; usage; exit 1;;
  esac
}

# -------- Main --------
if [ $# -lt 2 ]; then usage; exit 1; fi
need_cmd terraform

ENV_NAME="$1"; ACTION="$2"; shift 2 || true
ENV_DIR="${ENV_DIR_ROOT}/${ENV_NAME}"

[ -d "$ENV_DIR" ] || { echo "Unknown env '${ENV_NAME}' (expected directory ${ENV_DIR_ROOT}/local|stg|prd)"; exit 1; }

cd "$ENV_DIR"

if [ "$ENV_NAME" = "local" ]; then
  run_local "$ACTION" "$@"
else
  run_remote "$ENV_NAME" "$ACTION" "$@"
fi
