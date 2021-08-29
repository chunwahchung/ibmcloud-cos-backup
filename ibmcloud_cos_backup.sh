#!/bin/bash

ibmcloud_cli_login() {
    local __api_key=$1
    ibmcloud login --quiet --no-region --apikey $__api_key
}