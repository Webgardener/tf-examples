preflight_vault() {
  # $1 = path logique, ex: secret/mpg/certs/mon_cert
  local logical=$1
  local mount=${logical%%/*}          # secret
  local rest=${logical#*/}            # mpg/certs/mon_cert

  vault token lookup >/dev/null 2>&1 \
    || { echo "!! token Vault invalide ou expiré (vault login ?)"; exit 1; }

  local data_caps meta_caps
  data_caps=$(vault token capabilities "$mount/data/$rest")
  meta_caps=$(vault token capabilities "$mount/metadata/$rest")

  case "$data_caps" in
    *create*|*update*|*root*) ;;
    *) echo "!! droits insuffisants sur $mount/data/$rest (capabilities: $data_caps)"; exit 1 ;;
  esac
  case "$meta_caps" in
    *update*|*create*|*root*) ;;
    *) echo "!! droits insuffisants sur $mount/metadata/$rest (capabilities: $meta_caps)"; exit 1 ;;
  esac
}

preflight_vault "$VAULT_PATH"
