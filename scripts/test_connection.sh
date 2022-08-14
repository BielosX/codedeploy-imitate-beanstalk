#!/bin/bash

RETRIES=10

while ((RETRIES > 0)); do
  RESPONSE=$(curl --write-out '%{http_code}' --silent --output /dev/null http://localhost:8080/health)
  if [ "$RESPONSE" = "200" ]; then
    exit 0
  fi
  RETRIES=$((RETRIES - 1))
  sleep 2
done

exit 1