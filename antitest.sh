#!/bin/bash
CLEARACCOUNTS_SCRIPT='#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/clearaccounts.log"
mkdir -p "$(dirname "$LOG_FILE")"

DAYS_LIMIT=120
SECONDS_LIMIT=$(( DAYS_LIMIT * 86400 ))

epoch_now=$(date +%s)

for dir in /home/*; do
  [[ -d "$dir" ]] || continue

  user="${dir##*/}"
  [[ "$user" == "*" ]] && continue
  [[ "$user" == "secsuperuser" ]] && continue

  line=$(last -F -- "$user" 2>/dev/null | grep "login screen" | head -n1 || true)
  if [[ -z "$line" ]]; then
    timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
    echo "$timestamp ERROR: no login screen record found for $user" >> "$LOG_FILE"
    continue
  fi

  collapsed=$(echo "$line" | tr -s " ")
  date=$(echo "$collapsed" | awk '\''{ for(i=5;i<=9;i++) printf "%s%s", $i, (i<9?" ":""); }'\'')
  if [[ -z "$date" ]]; then
    timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
    echo "$timestamp ERROR: could not extract timestamp from $line" >> "$LOG_FILE"
    continue
  fi

  if ! epoch_last=$(date -d "$date" +%s 2>/dev/null); then
    timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
    echo "$timestamp ERROR: failed to parse date $date for $user" >> "$LOG_FILE"
    continue
  fi

  seconds_passed=$(( epoch_now - epoch_last ))

  timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
  echo "$timestamp INFO: user=$user seconds_passed=$seconds_passed days_passed=$(( seconds_passed / 86400 ))" >> "$LOG_FILE"

  if (( seconds_passed > SECONDS_LIMIT )); then
    timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
    echo "$timestamp INFO: $user has not logged in $DAYS_LIMIT days" >> "$LOG_FILE"
    timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
    echo "$timestamp INFO: $user home directory has been cleared" >> "$LOG_FILE"
  fi
done'

echo "$CLEARACCOUNTS_SCRIPT" > "test.sh"
