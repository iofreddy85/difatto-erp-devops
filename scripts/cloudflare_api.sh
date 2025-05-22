#!/bin/bash

cloudflare_post_dns_record() {
  local DNS_NAME=$1
  local DNS_IP=$2
  echo "DNS_NAME=$DNS_NAME" >&2
  echo "DNS_IP=$DNS_IP" >&2
  echo "DNS_ZONE=$DNS_ZONE" >&2
  local result=$(curl --request POST \
    --url https://api.cloudflare.com/client/v4/zones/$DNS_ZONE/dns_records \
    --header 'Content-Type: application/json' \
    --header 'Authorization: Bearer '$CLOUDFLARE_TOKEN'' \
    --data '{
    "content": "'$DNS_IP'",
    "name": "'$DNS_NAME'",
    "proxied": true,
    "type": "A",
    "ttl": 1
  }')
  echo $result | jq ".success" | { var=$(cat); echo "IP Creation for $DNS_NAME Success? ${var}"; } >&2
  echo $result | jq ".result.id" -r
}

cloudflare_put_dns_record() {
  local DNS_RECORD_ID=$1
  local DNS_NAME=$2
  local DNS_IP=$3

  curl --silent \
    --request PUT \
    --url https://api.cloudflare.com/client/v4/zones/$DNS_ZONE/dns_records/$DNS_RECORD_ID \
    --header 'Content-Type: application/json' \
    --header 'Authorization: Bearer '$CLOUDFLARE_TOKEN'' \
    --data '{
    "content": "'$DNS_IP'",
    "name": "'$DNS_NAME'",
    "proxied": true,
    "type": "A"
  }' | jq ".success" | { var=$(cat); echo "IP Change for $DNS_NAME Success? ${var}"; }
}

cloudflare_delete_dns_record() {
  local DNS_RECORD_ID=$1
  curl --request DELETE \
    --url https://api.cloudflare.com/client/v4/zones/$DNS_ZONE/dns_records/$DNS_RECORD_ID \
    --header 'Content-Type: application/json' \
    --header 'Authorization: Bearer '$CLOUDFLARE_TOKEN''
}

cloudflare_get_current_ip() {
  local RECORD_ID=$1
  local cur_ip=$(curl --silent \
    --request GET \
    --url https://api.cloudflare.com/client/v4/zones/$DNS_ZONE/dns_records/$RECORD_ID \
    --header 'Content-Type: application/json' \
    --header 'Authorization: Bearer '$CLOUDFLARE_TOKEN'' | jq '.result.content' -r)
  echo $cur_ip
}
