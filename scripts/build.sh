#!/bin/bash

source ./helpers.sh

REPO_ORG="iofreddy85"

download_artifact() {
  local ARTIFACTS_URL=$1
  echo "Getting Artifact file URL" >&2
  local zip_url=$(github_get_artifact_zip $ARTIFACTS_URL)

  echo "Downloading Artifact" >&2
  github_download_artifact $zip_url

  # Unzip artifact and grab image tag
  echo "Unziping Artifact" >&2
  unzip artifact.zip -d ./ >&2 && rm artifact.zip >&2
  local tag=$(<tag.txt)
  rm tag.txt >&2 && echo $tag
}

for i in "$@"; do
  case $i in
    -i=*|--input-params=*)
      INPUT_PARAMS="${i#*=}"
      shift # past argument=value
      ;;
    -e=*|--environment=*)
      ENV="${i#*=}"
      shift # past argument=value
      ;;
    -r=*|--repository=*)
      REPO="${i#*=}"
      shift # past argument=value
      ;;
    -b=*|--branch=*)
      BRANCH="${i#*=}"
      shift # past argument=value
      ;;
    -w=*|--workflow=*)
      WORKFLOW="${i#*=}"
      shift # past argument=value
      ;;
    *)
      ;;
  esac
done

workflow_run=$(wait_wf $REPO $(dispatch_build_wf $REPO $WORKFLOW $BRANCH $ENV $INPUT_PARAMS))
if [ $? -eq 0 ]; then
  artifacts_url=$(echo $workflow_run | jq '.artifacts_url' -r)
  image_tag=$(download_artifact $artifacts_url)
  echo $image_tag
  exit 0
else
  exit 1
fi
