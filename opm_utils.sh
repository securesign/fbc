#!/usr/bin/env bash

DEFAULT_OPM_VERSION="v1.50.0"
OPM_VERSION=${OPM_VERSION:-"${DEFAULT_OPM_VERSION}"}

download_opm_client() {
  wget "https://github.com/operator-framework/operator-registry/releases/download/${OPM_VERSION}/linux-$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')-opm" -O opm
  chmod +x opm
  # check the new binary
  ./opm version
}

opm_alpha_params() {
  params=
  if [[ ! "$1" < "v4.17" ]]; then
    params="--migrate-level=bundle-object-to-csv-metadata"
  fi
  echo "${params}"
}

download_opm_client