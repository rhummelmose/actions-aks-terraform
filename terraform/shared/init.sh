#!/bin/bash

# Exit if anything breaks
set -e

# Get terraform relative path
terraform_relative_path=$1

# Ensure portability
scripts_path="$(cd "$(dirname "$0")" && pwd)"

# Install Terraform 0.12.12 if on Linux
echo $(uname)
if [[ $(uname) == *"Linux"* ]] && [[ $(terraform version) != *"0.12.12"* ]]; then
    wget "https://releases.hashicorp.com/terraform/0.12.12/terraform_0.12.12_linux_amd64.zip"
    unzip terraform_0.12.12_linux_amd64.zip
    sudo mv terraform /usr/local/bin/
fi

# Sets global variables in the environment
set -o allexport
source "${scripts_path}/terraform_backend.env"
source "${scripts_path}/terraform_global.env"
set +o allexport

# Source from env set either locally via IDE or CI/CD
backend_client_secret=$AKSCOMM_TF_BACKEND_CLIENT_SECRET

# Set Azure CLI subscription (hidden requirement on the Azure AD Terraform resource provider)

## tfvars assignments
# takes *.tfvars and assigns env=value
# - works with terraform 0.6 types: string, map
# - map.key becomes map_key
function source_tfvars() {
    eval "$(
        awk 'BEGIN {FS=OFS="="}
        !/^(#| *$)/ && /^.+=.+$/ {
            gsub(/^[ \t]+|[ \t]+$/, "", $1);
            gsub(/\./, "_", $1);
            gsub(/^[ \t]+|[ \t]+$/, "", $2);
            if ($1 && $2) print $0
        }' "$@"
    )"
}

source_tfvars "${scripts_path}/../${terraform_relative_path}/terraform.tfvars"
declare azure_cli_target_subscription
if [ ! -z $subscription_id ]; then
    azure_cli_target_subscription=$subscription_id
elif [ ! -z $tenant_id ]; then
    azure_cli_target_subscription=$(az account list --query "[?tenantId == '${tenant_id}'] | [0].id" --output tsv)
else
    azure_cli_target_subscription=$TF_VAR_subscription_id
fi

az account set --subscription $azure_cli_target_subscription

# If we're running on Azure DevOps, we have to get credentials from env vars
if [ ! -z $servicePrincipalId ]; then
    export ARM_CLIENT_ID=$servicePrincipalId
fi

if [ ! -z $servicePrincipalKey ]; then
    export ARM_CLIENT_SECRET=$servicePrincipalKey
fi

if [ ! -z $tenantId ]; then
    export ARM_TENANT_ID=$tenantId
    export ARM_SUBSCRIPTION_ID=$(az account show --query 'id' --output tsv)
fi

# Terraform
terraform init \
    -backend-config="tenant_id=${TF_VAR_tf_backend_tenant_id}" \
    -backend-config="client_id=${TF_VAR_tf_backend_client_id}" \
    -backend-config="subscription_id=${TF_VAR_tf_backend_subscription_id}" \
    -backend-config="resource_group_name=${TF_VAR_tf_backend_resource_group_name}" \
    -backend-config="storage_account_name=${TF_VAR_tf_backend_storage_account_name}" \
    -backend-config="container_name=${TF_VAR_tf_backend_container_name}" \
    -backend-config="client_secret=${backend_client_secret}" \
    "${scripts_path}/../${terraform_relative_path}"