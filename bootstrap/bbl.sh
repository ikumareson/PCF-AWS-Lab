#!/bin/bash

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
source $SCRIPTPATH/tools/check-cli-tools.sh

set -e
[ -z "$ENV" ] && echo "You must set the ENV environment variable!" && exit 1
set -u

export BBL_STATE_DIRECTORY=$PWD/state/$ENV
export CONFIG_DIRECTORY=$PWD/config/$ENV
export BBL_IAAS=aws
export BBL_AWS_REGION="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml bbl_azure_region)"
export BBL_ENV_NAME="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml bbl_env_name)"

stemcell_version="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml stemcell_version)"
stemcell_sha="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml stemcell_sha)"
concourse_a_record="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml concourse_a_record)"
prometheus_a_record="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml prometheus_a_record)"
subdomain="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml subdomain)"
parent_domain="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml parent_domain)"
# dns_resource_group_name="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml dns_resource_group_name)"

#if [ "$1" != "--dangerously-no-pull" ]; then
#    [ "$1" != "print-env" ] && echo "Pulling state from bucket..."
#    $SCRIPTPATH/tools/bbl-state-sync-azure.sh pull quiet
#else
#    shift
#fi

set +u
if [ "$1" == "create" ]; then
    set -u
    mkdir -p $BBL_STATE_DIRECTORY
    
    # Comment out this line temporarily if you are having trouble with broken Terraform files
    # Preventing a plan from completing
    #bbl plan --lb-type concourse
    
    # copy additional terraform templates for bbl to create
    #cp -v terraform/*.tf $BBL_STATE_DIRECTORY/terraform
    #[ -d "$CONFIG_DIRECTORY/terraform" ] && cp -v $CONFIG_DIRECTORY/terraform/*.tf $BBL_STATE_DIRECTORY/terraform
#
    ## copy operations files to modify the cloud config created by bbl
    #cp -v cloud-config/*.yml $BBL_STATE_DIRECTORY/cloud-config
    #[ -d "$CONFIG_DIRECTORY/cloud-config" ] && cp -v $CONFIG_DIRECTORY/cloud-config/*.yml $BBL_STATE_DIRECTORY/cloud-config

    bbl plan --lb-type concourse

    # set up some additional terraform vars
    echo "concourse_a_record=\"$concourse_a_record.$subdomain\"" > $BBL_STATE_DIRECTORY/vars/hcl.tfvars
    echo "prometheus_a_record=\"$prometheus_a_record.$subdomain\"" >> $BBL_STATE_DIRECTORY/vars/hcl.tfvars
    echo "subdomain=\"$subdomain\"" >> $BBL_STATE_DIRECTORY/vars/hcl.tfvars
    echo "parent_domain=\"$parent_domain\"" >> $BBL_STATE_DIRECTORY/vars/hcl.tfvars
    echo "dns_resource_group_name=\"$dns_resource_group_name\"" >> $BBL_STATE_DIRECTORY/vars/hcl.tfvars

    # copy our create director override and additional ops files:
    cp $SCRIPTPATH/operations/bosh/*.yml $BBL_STATE_DIRECTORY
    cp $SCRIPTPATH/create-director-override.sh $BBL_STATE_DIRECTORY

    bbl up
    eval "$(bbl print-env)"

elif [ "$1" == "down" ]; then
    echo "Deleting state from Azure bucket..."
    $SCRIPTPATH/tools/bbl-state-sync-azure.sh delete
    bbl destroy --no-confirm
else
    bbl $@
fi

case "$1" in
    create|up|rotate|plan|cleanup-leftovers)
        echo "Pushing state to bucket..."
        $SCRIPTPATH/tools/bbl-state-sync-azure.sh push quiet
        ;;
esac
