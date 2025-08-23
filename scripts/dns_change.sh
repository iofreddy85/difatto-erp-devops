#!/bin/bash

source ./cloudflare_api.sh

change_dns() {
  local NEW_IP=$1
  echo "Changing DNS in Cloudflare" >&2
  cloudflare_put_dns_record $RECORD_ID $DNS_NAME $NEW_IP
}

get_tasks() {
  echo $(aws ecs list-tasks --cluster $ECS_CLUSTER --service-name $ECS_SERVICE | jq  ".taskArns" -r)
}

get_task_ip() {
  local ipv4=""
  local tasks_length=$(get_tasks | jq "length")
  [[ $tasks_length == "0" ]] && echo $CURRENT_IP && return 0
  # we're expecting only 1 task, so if we get more it means we're in blue/green deployment
  if [[ "$tasks_length" > "1" ]]; then
    echo "Deployment in progress..." >&2
    echo $CURRENT_IP
  else
    local task_id=$(get_tasks | jq  ".[0]" -r)
    echo "Task: $task_id" >&2
    local eni=$(aws ecs describe-tasks --cluster $ECS_CLUSTER --tasks ${task_id} | jq '.tasks[0].attachments | map(select(.status=="ATTACHED"))[] | .details | map(select(.value | contains("eni")))[0].value' -r)
    [ ! -z "$eni" ] && ipv4=$(aws ec2 describe-network-interfaces --filters Name=network-interface-id,Values=${eni} | jq .NetworkInterfaces[0].Association.PublicIp -r) && echo $ipv4
    [ ! -z "$eni" ] || echo $CURRENT_IP
  fi
}

check_service_ready() {
  echo "Checking Service task Health..." >&2
  local task_id=$(get_tasks | jq  ".[0]" -r)
  local count=0
  while true; do
    health_status=$(aws ecs describe-tasks --cluster $ECS_CLUSTER --tasks ${task_id} | jq ".tasks[0].healthStatus" -r)
    if [[ "$health_status" == "HEALTHY" ]]; then
      echo "Health check passed! Deploy finished!" >&2
      # code 0 means ok (true)
      return 0
    fi

    if [ $count -eq $RETRY_COUNT ]; then
      echo "Timeout! Service Health didn't pass!" >&2
      exit 1
    fi
    echo "Waiting for green Health check..." >&2
    (( count++ ))
    sleep $INTERVAL
  done
}

# DESIRED_TASKS=$(aws ecs describe-services --cluster $ECS_CLUSTER --services $ECS_SERVICE  | jq ".services[0].desiredCount")
# [[ $DESIRED_TASKS == 0 ]] && echo "Service sleeping. No desired tasks!" && exit 0

# if the script is executed late in the deploy process, CURRENT_IP might be empty.
# either way it should work as it will detect the change when new_ip has a value
CURRENT_IP=$(cloudflare_get_current_ip $RECORD_ID)
[ ! -z "$CURRENT_IP" ] && echo "CURRENT_IP -> $CURRENT_IP"

TIME_OUT=300
INTERVAL=10
COUNT=1
RETRY_COUNT=$((TIME_OUT / INTERVAL))

while true; do
  new_ip=$(get_task_ip)
  if [[ "$CURRENT_IP" != "$new_ip" ]]; then
    echo "IP change detected NEW_IP: $new_ip" >&2
    check_service_ready && change_dns "$new_ip"
    break
  fi
  if [ $COUNT -eq $RETRY_COUNT ]; then
      echo "Timeout! NO_IP Change detected!" >&2
      exit 1
  fi
  echo "Checking ip for change..." >&2
  (( COUNT++ ))
  sleep $INTERVAL
done
exit 0
