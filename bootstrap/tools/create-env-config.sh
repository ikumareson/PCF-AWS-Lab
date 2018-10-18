#!/bin/bash
set -e
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"

# Defaults
[ -z "$STEMCELL_VERSION" ] && STEMCELL_VERSION="3586.48"
[ -z "$STEMCELL_SHA" ] && STEMCELL_SHA="66c60fd818eb568ec349d6faa06c1f394f054878"
[ -z "$XENIAL_STEMCELL_VERSION" ] && XENIAL_STEMCELL_VERSION="97.22"
[ -z "$XENIAL_STEMCELL_SHA" ] && XENIAL_STEMCELL_SHA="ee520cf2eb3ba8ac358c441deaa5f6112a06d7b8"
#[ -z "$SUBSCRIPTION_NAME" ] && SUBSCRIPTION_NAME="Cloud Native Labs"
[ -z "$CONCOURSE_A_RECORD" ] && CONCOURSE_A_RECORD="ci"
[ -z "$PROMETHEUS_A_RECORD" ] && PROMETHEUS_A_RECORD="prometheus"
[ -z "$PARENT_DOMAIN" ] && PARENT_DOMAIN="hclcnlabs.com"
#[ -z "$DNS_RESOURCE_GROUP_NAME" ] && DNS_RESOURCE_GROUP_NAME="admin"


if [ -z "$3" ]; then
    echo "Usage: $0 <env_name> <subdomain> <region>"
    echo "e.g. $0 test-lab01 test-lab01.uk ap-south-1"
fi

ENV_NAME=$1
SUBDOMAIN=$2
REGION=$3
FORCE=$4

if [ -d "config/$ENV_NAME" ] && [ -z "$FORCE" ]; then
    echo "$ENV_NAME already seems to have a config directory, exiting..."
    exit 0
fi

config_dir="$SCRIPTPATH/../config/$ENV_NAME"
template_dir="$SCRIPTPATH/../templates"

mkdir -p $config_dir

while read line
do
    eval echo "$line"
done < "$template_dir/bbl-vars.yml" > "$config_dir/bbl-vars.yml"

# Concourse vars probably don't need to be changed so we just copy the template as it is
cp "$template_dir/concourse-vars.yml" "$config_dir/concourse-vars.yml"

echo "Config for $ENV_NAME generated!"
