  for name in $names; do
    # Cas 1 : pas de champ 'crt' dans l'entrée
    if ! crt=$(vault kv get -field=crt "$path/$name" 2>/dev/null); then
      printf "%-22s | %-25s | %s\n" "$path" "$name" "-- ignoré (pas de champ 'crt')"
      continue
    fi
    # Cas 2 : le champ existe mais n'est pas un certificat x509 valide
    if ! echo "$crt" | openssl x509 -noout 2>/dev/null; then
      printf "%-22s | %-25s | %s\n" "$path" "$name" "-- ignoré (contenu non x509)"
      continue
    fi
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
