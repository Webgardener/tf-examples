 local logical=$1
  local probe="${logical%/*}/_preflight_probe"

  vault token lookup >/dev/null 2>&1 \
    || { echo "ERROR: Vault token invalid or expired (vault login?)"; exit 1; }

  vault kv put "$probe" ts="$(date -u +%s)" >/dev/null \
    || { echo "ERROR: cannot write under ${logical%/*} (check policy/namespace)"; exit 1; }
  vault kv metadata put -custom-metadata=probe=true "$probe" >/dev/null \
    || { echo "ERROR: cannot write metadata under ${logical%/*}"; exit 1; }
