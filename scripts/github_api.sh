#!/bin/bash

github_get_env_public_key() {
  local ENV_NAME=$1
  local RET=$(curl -L \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repositories/$DEV_OPS_REPO_ID/environments/$ENV_NAME/secrets/public-key | jq '.' -c)
  echo $RET
}

github_get_env_var() {
  local OWNER=$1
  local REPO=$2
  local ENV_NAME=$3
  local VAR_NAME=$4
  local RET=$(curl -L \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/$OWNER/$REPO/environments/$ENV_NAME/variables/$VAR_NAME | jq '.value' -r)
  echo $RET
}

github_get_secrets_repositories() {
  local SECRET_NAME=$1
  local RET=$(curl -Ls \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/orgs/$REPO_ORG/actions/secrets/$SECRET_NAME/repositories | jq '.repositories | map(.id)' -c)
  echo $RET
}

github_put_org_secret() {
  local SECRET_NAME=$1
  local NEW_VALUE_ENCRYPTED=$2
  local ENCRYPTION_KEY_ID=$3
  local REPOS_IDS=$4
  curl -Ls \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/orgs/$REPO_ORG/actions/secrets/$SECRET_NAME \
    -d '{
      "encrypted_value": "'$NEW_VALUE_ENCRYPTED'",
      "key_id": "'$ENCRYPTION_KEY_ID'",
      "visibility": "selected",
      "selected_repository_ids": '$REPOS_IDS'
    }'
}

github_dispatch_wf() {
  local REPOSITORY=$1
  local WORKFLOW_FILE=$2
  local WORKFLOW_BRANCH=$3
  local WOKFLOW_INPUT=$4
  echo "Dispatching WF $WORKFLOW_FILE"
  echo "Workflow Branch: $WORKFLOW_BRANCH"
  echo "Workflow Input: $WOKFLOW_INPUT"
  curl -Ls \
    -X POST \
    -H 'Accept: application/vnd.github+json' \
    -H 'Authorization: Bearer '$PAT'' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    https://api.github.com/repos/$REPO_ORG/$REPOSITORY/actions/workflows/$WORKFLOW_FILE/dispatches \
    -d '{
      "ref": "'$WORKFLOW_BRANCH'",
      "inputs": '$WOKFLOW_INPUT'
    }'
}

github_get_workflow_run() {
  local REPOSITORY=$1
  local CORRELATION_ID=$2
  local status=$(curl -Ls \
    -H 'Accept: application/vnd.github+json' \
    -H 'Authorization: Bearer '$PAT'' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    https://api.github.com/repos/$REPO_ORG/$REPOSITORY/actions/runs \
    | jq '.workflow_runs | map(select(.name=="'$CORRELATION_ID'"))[0] | {id:.id, status:.status, conclusion:.conclusion, artifacts_url:.artifacts_url}' -c)
  echo $status
}

github_get_artifact_zip() {
  local ARTIFACTS_URL=$1
  echo "Getting Artifact file URL" >&2
  local zip_url=$(curl -Ls \
    -H 'Accept: application/vnd.github+json' \
    -H 'Authorization: Bearer '$PAT'' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    $ARTIFACTS_URL \
    | jq '.artifacts[0].archive_download_url' -r)
  echo $zip_url
}

github_download_artifact() {
  local URL=$1
  curl -Ls \
    -H 'Accept: application/vnd.github+json' \
    -H 'Authorization: Bearer '$PAT'' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    $URL -o artifact.zip
}

github_put_env() {
  local ENVIRONMENT_NAME=$1
  curl -L \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/$REPO_ORG/difatto-erp-devops/environments/$ENVIRONMENT_NAME
}

github_delete_env() {
  local ENVIRONMENT_NAME=$1
  curl -L \
    -X DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/$REPO_ORG/difatto-erp-devops/environments/$ENVIRONMENT_NAME
}

github_post_env_var() {
  local REPO_ID=$1
  local ENVIRONMENT_NAME=$2
  local VAR_NAME=$3
  local VAR_VALUE=$4
  curl -Ls \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repositories/$REPO_ID/environments/$ENVIRONMENT_NAME/variables \
    -d '{
      "name": "'$VAR_NAME'",
      "value": "'$VAR_VALUE'"
    }'
}

github_put_env_secret() {
  local ENV_NAME=$1
  local SECRET_NAME=$2
  local NEW_VALUE_ENCRYPTED=$3
  local ENCRYPTION_KEY_ID=$4
  curl -L \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repositories/$DEV_OPS_REPO_ID/environments/$ENV_NAME/secrets/$SECRET_NAME \
    -d '{
      "encrypted_value": "'$NEW_VALUE_ENCRYPTED'",
      "key_id": "'$ENCRYPTION_KEY_ID'"
    }'
}

github_list_deployments() {
  local ENV_ID=$1
  curl -L \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/$REPO_ORG/difatto-erp-devops/deployments | jq 'map(select(.environment=="'$ENV_ID'")) | map(.id)' -r
}

github_delete_deployments() {
  local DEPLOYMENT_ID=$1
  echo "Deleting Deployment: $1"
  curl -L \
    -X DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/$REPO_ORG/difatto-erp-devops/deployments/$DEPLOYMENT_ID
}

github_deactivate_deployment() {
  local DEPLOYMENT_ID=$1
  curl -L \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/$REPO_ORG/difatto-erp-devops/deployments/$DEPLOYMENT_ID/statuses \
    -d '{"state": "inactive"}'
}