list-certs:
  stage: audit
  script:
    - |
      printf "%-25s | %-40s | %-25s | %-12s | %s\n" "NOM" "SUBJECT" "EXPIRATION" "JOURS REST." "STATUT"
      printf -- "-%.0s" {1..120}; echo ""
      EXPIRING=0
      for name in $(vault kv list -format=yaml secret/mpg/certs | sed 's/^- //'); do
        crt=$(vault kv get -field=crt "secret/mpg/certs/$name")
        subject=$(echo "$crt" | openssl x509 -noout -subject | sed 's/^subject=//')
        enddate=$(echo "$crt" | openssl x509 -noout -enddate | cut -d= -f2)
        end_epoch=$(date -d "$enddate" +%s)
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
