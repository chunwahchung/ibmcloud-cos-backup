#!/bin/bash

ibmcloud_cli_login() {
    local __api_key=$1
    ibmcloud login --quiet --no-region --apikey $__api_key
}

set_cos_auth_to_hmac() {
    echo 2 | ibmcloud cos config auth
}

config_ibmcloud_cli_cos() {

    local __access_key_id=$1
    local __secret_access_key=$2

    echo "$__access_key_id
    $__secret_access_key" | ibmcloud cos config hmac
}