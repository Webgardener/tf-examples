#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Settings (override via env)
# ----------------------------
: "${GITLAB_BASE_URL:=https://gitlab.com}"
: "${GITLAB_PROJECT_ID:?Set GITLAB_PROJECT_ID (numeric GitLab project ID)}"
: "${STATE_PREFIX:=}"                 # optional, e.g., "myapp-"
: "${ENV_DIR_ROOT:=envs}"            # where env dirs live (envs/stg/hub, envs/stg/workspace, ...)

VALID_ENVS=("stg" "prd")
VALID_STACKS=("hub" "workspace" "all")

# ----------------------------
# Helpers
# ----------------------------
usage() {
  cat <<EOF
Usage:
  $0 <env> <stack> <action> [extra terraform args]

env:    stg | prd
stack:  hub | workspace | all   (all runs "hub" then "workspace")
action: init | plan | apply | destroy | validate | fmt | output | state

Examples:
  GITLAB_PROJECT_ID=123456 ./run.sh stg hub init
  ./run.sh stg workspace plan -out=tfplan
  ./run.sh prd all apply -auto-approve

Env vars:
  GITLAB_BASE_URL   (default: https://gitlab.com)
  GITLAB_PROJECT_ID (required)
  STATE_PREFIX      (optional, e.g. "myapp-")
  ENV_DIR_ROOT      (default: envs)
  CI_JOB_TOKEN or GITLAB_TOKEN (required for auth)
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }
}

in_list() {
  local needle="$1"; shift
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

token_header() {
  if [[ -n "${CI_JOB_TOKEN:-}" ]]; then
    printf "JOB-TOKEN: %s" "${CI_JOB_TOKEN}"
  elif [[ -n "${GITLAB_TOKEN:-}" ]]; then
    printf "Authorization: Bearer %s" "${GITLAB_TOKEN}"
  else
    echo "ERROR: Provide CI_JOB_TOKEN (CI) or GITLAB_TOKEN (local PAT) for GitLab backend auth." >&2
    exit 1
  fi
}

mk_backend_file() {
  local env="$1" stack="$2" path_out="$3"
  local state="${STATE_PREFIX}${env}-${stack}"
  local base="${GITLAB_BASE_URL%/}/api/v4/projects/${GITLAB_PROJECT_ID}/terraform/state/${state}"
  cat > "$path_out" <<HCL
address        = "${base}"
lock_address   = "${base}/lock"
unlock_address = "${base}/lock"
lock_method    = "POST"
unlock_method  = "DELETE"
retry_wait_min = 5
HCL
}

var_args() {
  [[ -f "terraform.tfvars" ]] && printf "%s" "-var-file=terraform.tfvars" || true
}

run_stack() {
  local env="$1" stack="$2" action="$3"; shift 3 || true
  local dir="${ENV_DIR_ROOT}/${env}/${stack}"

  [[ -d "$dir" ]] || { echo "Missing directory: $dir"; exit 1; }

  pushd "$dir" >/dev/null

  local hdr
  hdr="$(token_header)"

  local tmp_backend
  tmp_backend="$(mktemp -t tf-backend-XXXX.hcl)"
  trap 'rm -f "$tmp_backend"' RETURN
  mk_backend_file "$env" "$stack" "$tmp_backend"

  case "$action" in
    init)
      terraform init \
        -backend-config="$tmp_backend" \
        -backend-config="header=${hdr}" \
        "$@"
      ;;
    plan)
      terraform init -reconfigure \
        -backend-config="$tmp_backend" \
        -backend-config="header=${hdr}" >/dev/null
      terraform plan $(var_args) "$@"
      ;;
    apply)
      terraform init -reconfigure \
        -backend-config="$tmp_backend" \
        -backend-config="header=${hdr}" >/dev/null
      terraform apply $(var_args) "$@"
      ;;
    destroy)
      terraform init -reconfigure \
        -backend-config="$tmp_backend" \
        -backend-config="header=${hdr}" >/dev/null
      terraform destroy $(var_args) "$@"
      ;;
    validate) terraform validate "$@";;
    fmt)      terraform fmt -recursive "$@";;
    output)   terraform output "$@";;
    state)    terraform state list "$@";;
    *) echo "Unknown action: $action"; usage; exit 1;;
  esac

  popd >/dev/null
}

run_all_in_order() {
  local env="$1" action="$2"; shift 2 || true
  # Declare the order: hub -> workspace
  run_stack "$env" "hub" "$action" "$@"
  run_stack "$env" "workspace" "$action" "$@"
}

# ----------------------------
# Main
# ----------------------------
if [[ $# -lt 3 ]]; then usage; exit 1; fi
need_cmd terraform

ENV="$1"; STACK="$2"; ACTION="$3"; shift 3 || true

in_list "$ENV"    "${VALID_ENVS[@]}"    || { echo "Invalid env: $ENV"; usage; exit 1; }
in_list "$STACK"  "${VALID_STACKS[@]}"  || { echo "Invalid stack: $STACK"; usage; exit 1; }

if [[ "$STACK" == "all" ]]; then
  run_all_in_order "$ENV" "$ACTION" "$@"
else
  run_stack "$ENV" "$STACK" "$ACTION" "$@"
fi
