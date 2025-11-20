#!/bin/bash
mapfile -t home < <(find /home -type d -name "*@SEC.local")
EXCLUDE=$1

for dir in "${home[@]}"; do
  if ! [[ "$dir" == "$EXCLUDE" ]]; then
    echo "$(date +"%d-%m-%Y %H:%M:%S"): Removing $dir"
    rm -rf "$dir"
  fi
done