#!/bin/bash

source ./github_api.sh

get_cf_stack_output() {
  local STACK_NAME=$1
  local OUTPUT_PARAM_NAME=$2
  local output=$(aws cloudformation describe-stacks \
    --stack-name="$STACK_NAME" | jq '.Stacks[0].Outputs | map(select(.OutputKey=="'$OUTPUT_PARAM_NAME'"))[0].OutputValue' -r)
  echo $output
}

get_current_rds_sgs() {
  local DB_IDENTIFIER=$1
  local sgs=$(aws rds describe-db-instances --db-instance-identifier $DB_IDENTIFIER | jq '.DBInstances[0].VpcSecurityGroups | map(.VpcSecurityGroupId)' -c)
  echo $sgs
}

configure_github_user() {
  local ENV_NAME=$1
  local GIT_AWS_USER=$2

  echo "Creating Access Key for User $GIT_AWS_USER..."
  access_key=$(aws iam create-access-key --user-name $GIT_AWS_USER | jq '.' -c)
  local NEW_AWS_ACCESS_KEY_ID=$(echo $access_key | jq '.AccessKey.AccessKeyId' -r)
  local NEW_AWS_SECRET_ACCESS_KEY=$(echo $access_key | jq '.AccessKey.SecretAccessKey' -r)
  # echo "NEW_AWS_ACCESS_KEY_ID=$NEW_AWS_ACCESS_KEY_ID"
  # echo "NEW_AWS_SECRET_ACCESS_KEY=$NEW_AWS_SECRET_ACCESS_KEY"

  # Get Public key for secret encryption
  local NEW_PUBLIC_KEY=$(github_get_env_public_key $ENV_NAME)
  local key_id=$(echo $NEW_PUBLIC_KEY | jq '.key_id' -r)
  local key=$(echo $NEW_PUBLIC_KEY | jq '.key' -r)
  # echo "key_id=$key_id"
  # echo "key=$key"

  # Encrypt NEW_AWS_SECRET_ACCESS_KEY
  local NEW_AWS_SECRET_ACCESS_KEY_ENC=$(node ../helpers/secret-encrypter/index.js \
    --public-key="$key" \
    --secret="$NEW_AWS_SECRET_ACCESS_KEY")
  # echo "NEW_AWS_SECRET_ACCESS_KEY_ENC=$NEW_AWS_SECRET_ACCESS_KEY_ENC"

  # Encrypt NEW_AWS_ACCESS_KEY_ID
  local NEW_AWS_ACCESS_KEY_ID_ENC=$(node ../helpers/secret-encrypter/index.js \
    --public-key="$key" \
    --secret="$NEW_AWS_ACCESS_KEY_ID")
  # echo "NEW_AWS_ACCESS_KEY_ID_ENC=$NEW_AWS_ACCESS_KEY_ID_ENC"

  echo "Adding AWS_SECRET_ACCESS_KEY to Github Actions Secrets..."
  github_put_env_secret \
    $ENV_NAME \
    "AWS_SECRET_ACCESS_KEY" \
    $NEW_AWS_SECRET_ACCESS_KEY_ENC \
    $key_id

  echo "Adding AWS_ACCESS_KEY_ID to Github Actions Secrets..."
  github_put_env_secret \
    $ENV_NAME \
    "AWS_ACCESS_KEY_ID" \
    $NEW_AWS_ACCESS_KEY_ID_ENC \
    $key_id
}

add_sgs_rds_instance() {
  local STACK_NAME=$1
  local RDS_INSTANCE=$2
  local SECURITY_GROUP=$3
  echo "Adding New Security Group to $RDS_INSTANCE RDS instance..."
  # Get SG_ECS_RDS security group from stack output
  local SG_ECS_RDS=$(get_cf_stack_output $STACK_NAME $SECURITY_GROUP)
  echo "ECS-RDS Security Group to Add: $SG_ECS_RDS"

  #Get Current RDS Security Groups
  local CURRENT_SGS=$(get_current_rds_sgs $RDS_INSTANCE)
  echo "Current RDS Security Groups: $CURRENT_SGS"

  # Check if SG is already added
  local SG_EXISTS=$(echo $CURRENT_SGS | jq '. | index("'$SG_ECS_RDS'")')

  [[ "$SG_EXISTS" != "null" ]] && echo "Security Group: $SG_ECS_RDS already exist in RDS" && exit 0

  # Prepare Security groups array for RDS making it an array for next command input
  local VPC_SGS=($(echo $CURRENT_SGS | jq '. + ["'$SG_ECS_RDS'"] | join(" ")' -r))
  echo "Final Security Groups Array: ${VPC_SGS[@]}"

  # Add Security group to RDS
  echo "Setting Security Groups to RDS..."
  aws rds modify-db-instance --db-instance-identifier $RDS_INSTANCE --vpc-security-group-ids "${VPC_SGS[@]}" | jq '.DBInstance.VpcSecurityGroups'
}

remove_sgs_rds_instance() {
  local STACK_NAME=$1
  local RDS_INSTANCE=$2
  local SECURITY_GROUP=$3

  local SG_ECS_RDS=$(get_cf_stack_output $STACK_NAME $SECURITY_GROUP)

  echo "Security Group to remove: $SG_ECS_RDS"
  local CURRENT_SGS=$(get_current_rds_sgs $RDS_INSTANCE)

  echo "Current RDS Security Groups: $CURRENT_SGS"
  local VPC_SGS=($(echo $CURRENT_SGS | jq '. - ["'$SG_ECS_RDS'"] | join(" ")' -r))

  # Remove Security group to RDS
  echo "Final Security Groups Array: ${VPC_SGS[@]}"
  aws rds modify-db-instance \
    --db-instance-identifier $RDS_INSTANCE \
    --vpc-security-group-ids "${VPC_SGS[@]}" | jq '.DBInstance.VpcSecurityGroups'
}

dispatch_build_wf() {
  local REPO=$1
  local WORKFLOW=$2
  local BRANCH=$3
  local ENVIRONMENT=$4
  local WF_EXTRA_INPUT=$5

  local uid=$(uuidgen)

  echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" >&2
  echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" >&2
  echo "ECR_REPOSITORY=$ECR_REPOSITORY" >&2
  echo "WF_EXTRA_INPUT=$WF_EXTRA_INPUT" >&2

  local WF_COMMON_INPUT=$(jq -n \
    --arg environment $ENVIRONMENT \
    --arg correlation_id $uid \
    --arg aws_access_key_id $AWS_ACCESS_KEY_ID \
    --arg aws_secret_access_key $AWS_SECRET_ACCESS_KEY \
    --arg ecr_repository $ECR_REPOSITORY \
    '{
      "environment": $environment,
      "correlation_id": $correlation_id,
      "aws_access_key_id": $aws_access_key_id,
      "aws_secret_access_key": $aws_secret_access_key,
      "ecr_repository": $ecr_repository
    }' -c)

  echo "WF_COMMON_INPUT=$WF_COMMON_INPUT" >&2
  # Merge JSON objects: $WF_COMMON_INPUT and $WF_EXTRA_INPUT
  local WF_INPUT=$(echo "$WF_COMMON_INPUT" "$WF_EXTRA_INPUT" | jq --slurp 'reduce .[] as $item ({}; . * $item)' -c)

  echo "WF_INPUT=$WF_INPUT" >&2

  github_dispatch_wf \
    $REPO \
    $WORKFLOW \
    $BRANCH \
    $WF_INPUT >&2

  echo $uid
}

dispatch_delete_env_wf() {
  local ENV_ID=$1
  local WF_INPUT=$(jq -n \
    --arg environment $ENV_ID \
    '{"env_id": $environment}' -c)

  github_dispatch_wf \
    "difatto-erp-devops" \
    "difatto-delete-gh-env.yml" \
    "main" \
    $WF_INPUT
}

dispatch_backend_build_for_lambda_wf() {
  local REPO=$1
  local WORKFLOW=$2
  local BRANCH=$3
  local STACK_NAME=$4
  local ENVIRONMENT=$5

  local uid=$(uuidgen)
  local WF_INPUT=$(jq -n \
    --arg stack $STACK_NAME \
    --arg correlation_id $uid \
    --arg environment $ENVIRONMENT \
    '{
      "correlation_id": $correlation_id,
      "stack": $stack,
      "environment": $environment,
      "Deploy": false,
      "Backend": true,
      "FrontEnd": false,
      "Admin": false
    }' -c)

  echo "WF_INPUT=$WF_INPUT" >&2

  github_dispatch_wf \
    $REPO \
    $WORKFLOW \
    $BRANCH \
    $WF_INPUT >&2

  echo $uid
}

dispatch_dump_prod_data_wf() {
  local REPO=$1
  local WORKFLOW=$2
  local BRANCH=$3
  local FUNCTION_NAME=$4

  local uid=$(uuidgen)
  local WF_INPUT=$(jq -n \
    --arg correlation_id $uid \
    --arg function_name $FUNCTION_NAME \
    --arg efsPath '/mnt/ftw-qa-postgres-dumps' \
    --arg aws_access_key_id $AWS_ACCESS_KEY_ID \
    --arg aws_secret_access_key $AWS_SECRET_ACCESS_KEY \
    '{
      "correlation_id": $correlation_id,
      "function_name": $function_name,
      "efsPath": $efsPath,
      "aws_access_key_id": $aws_access_key_id,
      "aws_secret_access_key": $aws_secret_access_key
    }' -c)

  echo "WF_INPUT=$WF_INPUT" >&2

  github_dispatch_wf \
    $REPO \
    $WORKFLOW \
    $BRANCH \
    $WF_INPUT >&2

  echo $uid
}

dispatch_final_deploy() {
  local REPO=$1
  local WORKFLOW=$2
  local BRANCH=$3
  local STACK_NAME=$4
  local ENVIRONMENT=$5

  local uid=$(uuidgen)
  local WF_INPUT=$(jq -n \
    --arg stack $STACK_NAME \
    --arg environment $ENVIRONMENT \
    --arg correlation_id $uid \
    '{
      "correlation_id": $correlation_id,
      "stack": $stack,
      "environment": $environment,
      "Deploy": true,
      "Backend": true,
      "FrontEnd": true,
      "Admin": true
    }' -c)

  echo "WF_INPUT=$WF_INPUT" >&2

  github_dispatch_wf \
    $REPO \
    $WORKFLOW \
    $BRANCH \
    $WF_INPUT >&2

  echo $uid
}

wait_wf() {
  local REPO=$1
  local CORRELATION_ID=$2
  local INTERVAL=5
  local COUNT=1
  echo "Dispatch id: $CORRELATION_ID" >&2

  sleep 10
  while true; do
    workflow_run=$(github_get_workflow_run $REPO $CORRELATION_ID)
    workflow_status=$(echo $workflow_run | jq '.status' -r)
    workflow_conclusion=$(echo $workflow_run | jq '.conclusion' -r)

    if [[ $workflow_status = "completed" && $workflow_conclusion = "success" ]]; then
      echo "Workflow completed with success!" >&2
      echo $workflow_run
      return 0
    fi
    if [[ $workflow_status = "completed" && $workflow_conclusion != "success" ]]; then
      echo "Workflow completed with status: $workflow_conclusion!" >&2
      return 1
    fi
    (( COUNT++ ))
    [ $(( COUNT % 3 )) -eq 0 ] && echo "Workflow running..." >&2
    sleep $INTERVAL
  done
}