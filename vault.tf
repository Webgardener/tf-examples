list-certs:
  stage: audit
  script:
    - |
      to_epoch() {
        # $1 = date openssl, ex: "Sep 12 10:32:00 2026 GMT"
        if date -d "$1" +%s >/dev/null 2>&1; then
          date -d "$1" +%s                                  # GNU (Linux)
        else
          date -j -f "%b %d %T %Y %Z" "$1" +%s              # BSD (macOS)
        fi
      }
      printf "%-25s | %-40s | %-25s | %-12s | %s\n" "NOM" "SUBJECT" "EXPIRATION" "JOURS REST." "STATUT"
      printf -- "-%.0s" {1..120}; echo ""
      EXPIRING=0
      for name in $(vault kv list -format=yaml secret/mpg/certs | sed 's/^- //'); do
        crt=$(vault kv get -field=crt "secret/mpg/certs/$name")
        subject=$(echo "$crt" | openssl x509 -noout -subject | sed 's/^subject=//')
        enddate=$(echo "$crt" | openssl x509 -noout -enddate | cut -d= -f2)
        end_epoch=$(to_epoch "$enddate")
        days_left=$(( (end_epoch - $(date +%s)) / 86400 ))
        if [ "$days_left" -lt 0 ]; then
          status="EXPIRE"; EXPIRING=1
        elif [ "$days_left" -lt 30 ]; then
          status="A RENOUVELER"; EXPIRING=1
        else
          status="OK"
        fi
        printf "%-25s | %-40s | %-25s | %-12s | %s\n" "$name" "$subject" "$enddate" "$days_left" "$status"
      done
      exit $EXPIRING
