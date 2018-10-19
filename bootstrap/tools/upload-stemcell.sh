#!/bin/bash

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
source $SCRIPTPATH/check-cli-tools.sh

set -e
[ -z "$ENV" ] && echo "You must set the ENV environment variable!" && exit 1
set -u

export CONFIG_DIRECTORY=$SCRIPTPATH/../config/$ENV

stemcell_version="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml stemcell_version)"
stemcell_sha="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml stemcell_sha)"
xenial_stemcell_version="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml xenial_stemcell_version)"
xenial_stemcell_sha="$(yq r $CONFIG_DIRECTORY/bbl-vars.yml xenial_stemcell_sha)"

bosh upload-stemcell --sha1 $stemcell_sha \
  https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent?v=$stemcell_version

bosh upload-stemcell --sha1 $xenial_stemcell_sha \
  https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-xenial-go_agent?v=$xenial_stemcell_version