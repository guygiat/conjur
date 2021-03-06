#!/bin/bash

#	---------------------------------------------------------------------------------------------------------------------
# This script obtains all of the GCP identity tokens required by authn-gcp cucumber tests
# The scripts accepts the GCE instance name as an argument.
# The script does the following:
# 1. Validates gcloud is installed (requires a GCP account)
#   To install gcloud goto: https://cloud.google.com/sdk/docs, download and install the SDK by running:
#   ./google-cloud-sdk/install.sh
#   ./google-cloud-sdk/bin/gcloud init
# 2. Verifies the GCE instance exists and is running
# 3. Executes a ssh curl command and write the output token with the appropriate token name to '../ci/authn-gcp/tokens'.
#	---------------------------------------------------------------------------------------------------------------------

PROGNAME=$(basename "$0")
INSTANCE_ZONE=""
TOKENS_OUT_DIR_PATH=../ci/authn-gcp/tokens
TOKEN_FILE_NAME_PREFIX=gcp_token_
INSTANCE_EXISTS=0
INSTANCE_RUNNING=0

main() {
  echo "-- ------------------------------------------ --"
  echo "-- Generate Google Cloud GCP Identity tokens --"
  echo "-- ------------------------------------------ --"

  echo "-- Verifying 'gcloud' is installed..."
  ensure_gcloud_is_installed
  echo "-- Verifying GCE instance name..."
  check_instance_name_arg "$1"
  echo "-- Checking if GCE instance: '${INSTANCE_NAME}' exists..."
  ensure_instance_exists_and_running "$INSTANCE_NAME"
  echo "-- Deleting stale token files..."
  rm -rf ${TOKENS_OUT_DIR_PATH}/${TOKEN_FILE_NAME_PREFIX}*
  echo "-- Generate tokens and writing to files under '${TOKENS_OUT_DIR_PATH}'..."
  get_tokens_into_files
  echo "-- Finished obtaining and writing tokens to files."
}

ensure_gcloud_is_installed() {
  COMMAND=gcloud

  if ! command -v $COMMAND &> /dev/null; then
    error_exit "-- ${COMMAND} could not be found."
  fi
  echo "-- ${COMMAND} command exists"
}

check_instance_name_arg() {
  if [ -z "$1" ]; then
    echo "-- GCE instance name is required. Usage: ./${PROGNAME} [GCE_INSTANCE_NAME]"
    print_running_gce_instances
    error_exit "GCE instance name is required!"
  else
    INSTANCE_NAME=$1
    echo "-- GCE instance name is set to: '${INSTANCE_NAME}'."
  fi
}

#	----------------------------------------------------------------
# Checks if the given instance name argument exist and in RUNNING
# status, extracts the instance zone for later use;
# exit the script with error otherwise.
#	----------------------------------------------------------------
ensure_instance_exists_and_running() {
  local instance_name="$1"
  # 'gcloud' response format: 'instance-zone;STATUS', (e.g. europe-west3-c;RUNNING).
  local format="value[separator=';'](zone.basename(),status)"

  # Get list of GCE instances in all zones filtered by exact match regex '$instance_name'.
  # Returns 'instance-zone;STATUS'
  # if the instance exists; empty string otherwise.
  local instance_info=$(gcloud compute instances list --filter="name ~ ^$instance_name$" --format="$format")

  if [[ "$instance_info" != "" ]]; then
    INSTANCE_EXISTS=1
    #	----------------------------------------------------------------
    # The $instance_info output is in the form of 'instance-zone;STATUS',
    # (e.g. europe-west3-c;RUNNING).
    # Below we extract the following:
    # - instance zone: used in the 'gcloud compute ssh' command.
    # - instance status: used to validate that the instance is running.
    #	----------------------------------------------------------------
    set_instance_zone "$instance_info"
    local instance_status=$(echo "$instance_info" | cut -f2 -d ';')

    if [ "$instance_status" = "RUNNING" ]; then
      echo "-- GCE instance '${instance_name}', zone: '$INSTANCE_ZONE', status: '$instance_status'."
      INSTANCE_RUNNING=1
    else
      echo "-- GCE instance '${instance_name}', zone: '$INSTANCE_ZONE', NOT RUNNING!, status: '$instance_status'."
      print_running_gce_instances
      error_exit "GCE instance '${instance_name}', zone: '$INSTANCE_ZONE' is not running, status: '$instance_status'."
    fi
  else
    echo "-- GCE instance '${instance_name}' NOT FOUND!"
    print_running_gce_instances
    error_exit "GCE instance '${instance_name}' not found."
  fi
}

set_instance_zone() {
  local instance_info="$1"
  INSTANCE_ZONE=$(echo "$instance_info" | cut -f1 -d ';')
}

print_running_gce_instances() {
  echo "-- Retrieving running instances..."
  gcloud compute instances list --limit=50\
    --format="table[box,title='Running Compute Instances'](name,machine_type.basename(),status)" \
    --filter="STATUS=RUNNING"
}

get_tokens_into_files() {
  if [ "${INSTANCE_EXISTS}" = "0" ] | [ "${INSTANCE_RUNNING}" = "0" ]; then
    error_exit "-- Cannot run command, GCE instance '${INSTANCE_NAME}' not in a valid state!"
  fi

  get_token_into_file "full" "conjur/cucumber/host/test-app" "valid"
  get_token_into_file "full" "conjur/cucumber/host/non-existing" "non_existing_host"
  get_token_into_file "full" "conjur/cucumber/host/non-rooted/test-app" "non_rooted_host"
  get_token_into_file "full" "conjur/cucumber/test-app" "user"
  get_token_into_file "full" "conjur/non-existing/host/test-app" "non_existing_account"
  get_token_into_file "full" "invalid_audience" "invalid_audience"
  get_token_into_file "standard" "conjur/cucumber/host/test-app" "standard_format"
  wait
}

get_token_into_file() {
  local token_format="$1"
  local audience="$2"
  local filename="$3"
  local token_file="${TOKENS_OUT_DIR_PATH}/${TOKEN_FILE_NAME_PREFIX}${filename}"
  local curl_cmd="curl -s -G -H 'Metadata-Flavor: Google' \
  --data-urlencode 'format=${token_format}' \
  --data-urlencode 'audience=${audience}' \
  'http://metadata/computeMetadata/v1/instance/service-accounts/default/identity'"

  echo "-- Obtain an ID token in '${token_format}' format, audience: '${audience}' and persist to: '${token_file}'"

  gcloud compute ssh "$INSTANCE_NAME" --zone="${INSTANCE_ZONE}" --command "${curl_cmd}" > "${token_file}" &
}

error_exit() {
  #	----------------------------------------------------------------
  #	Function for exit due to fatal program error
  #		Accepts 1 argument:
  #			string containing descriptive error message
  #	----------------------------------------------------------------

  echo "${PROGNAME}:${LINENO}: ${1:-"Unknown Error"}" 1>&2
  exit 1
}

main "$1"
