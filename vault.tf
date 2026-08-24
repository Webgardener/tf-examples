#!/usr/bin/env bash
# scripts/list-certs.sh — inventaire des certs stockés dans Vault
set -euo pipefail

# Paths à auditer : en arguments, sinon liste par défaut
CERT_PATHS=("$@")
[ ${#CERT_PATHS[@]} -eq 0 ] && CERT_PATHS=(secret/mpg/certs secret/mpg-tools/certs)

RENEWAL_WINDOW_DAYS=${RENEWAL_WINDOW_DAYS:-30}

to_epoch() {
  if date -d "$1" +%s >/dev/null 2>&1; then
    date -d "$1" +%s                       # GNU (Linux)
  else
    date -j -f "%b %d %T %Y %Z" "$(echo "$1" | tr -s ' ')" +%s   # BSD (macOS)
  fi
}

printf "%-22s | %-25s | %-40s | %-25s | %-11s | %s\n" \
  "PATH" "NOM" "SUBJECT" "EXPIRATION" "JOURS REST." "STATUT"
printf -- "-%.0s" {1..145}; echo ""

EXPIRING=0
for path in "${CERT_PATHS[@]}"; do
  names=$(vault kv list -format=yaml "$path" 2>/dev/null | sed 's/^- //') || {
    printf "%-22s | %s\n" "$path" "!! inaccessible ou vide"
    EXPIRING=1
    continue
  }
  for name in $names; do
    crt=$(vault kv get -field=crt "$path/$name")
    subject=$(echo "$crt" | openssl x509 -noout -subject | sed 's/^subject=//')
    enddate=$(echo "$crt" | openssl x509 -noout -enddate | cut -d= -f2)
    end_epoch=$(to_epoch "$enddate")
    days_left=$(( (end_epoch - $(date +%s)) / 86400 ))
    if [ "$days_left" -lt 0 ]; then
      status="EXPIRE"; EXPIRING=1
    elif [ "$days_left" -lt "$RENEWAL_WINDOW_DAYS" ]; then
      status="A RENOUVELER"; EXPIRING=1
    else
      status="OK"
    fi
    printf "%-22s | %-25s | %-40s | %-25s | %-11s | %s\n" \
      "$path" "$name" "${subject:0:40}" "$enddate" "$days_left" "$status"
  done
done
exit $EXPIRING
