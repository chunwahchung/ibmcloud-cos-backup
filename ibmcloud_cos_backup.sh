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

perform_dry_run() {
    
    local __src_cos_service_instance_id=$1
    local __src_cos_bucket=$2
    local __dst_cos_service_instance_id=$3
    local __dst_cos_bucket=$4

    rclone --dry-run copy $__src_cos_service_instance_id:$__src_cos_bucket $__dst_cos_service_instance_id:$__dst_cos_bucket
}

perform_copy() {
   
    local __src_cos_service_instance_id=$1
    local __src_cos_bucket=$2
    local __dst_cos_service_instance_id=$3
    local __dst_cos_bucket=$4

    rclone -v -P copy --checksum $__src_cos_service_instance_id:$__src_cos_bucket $__dst_cos_service_instance_id:$__dst_cos_bucket
}

prepare_backup_bucket() {

    local __dst_cos_service_instance_id=$1
    local __bucket_name=$2

    local __hmac_keys=$(prepare_service_credentials $__dst_cos_service_instance_id)
    local __backup_account_cos_instance_access_key_id=$(echo $__hmac_keys | jq -r '.access_key_id')
    local __backup_account_cos_instance_secret_access_key=$(echo $__hmac_keys | jq -r '.secret_access_key')

    config_ibmcloud_cli_cos $__backup_account_cos_instance_access_key_id $__backup_account_cos_instance_secret_access_key > /dev/null 2>&1

    rclone lsd $__dst_cos_service_instance_id: | grep $__bucket > /dev/null 2>&1
    local __backup_bucket_exists=$(echo $?)
    if [[ $__backup_bucket_exists -eq 1 ]]; then 
        echo 'bucket not found. creating bucket now..'
        ibmcloud cos bucket-create --bucket $__bucket_name
    else
        echo 'backup bucket exists'
    fi
}
    
backup_cos_instances() {

    local __rclone_config_profiles=$(grep "\[" ~/.config/rclone/rclone.conf | sed -E 's/(\[|\])//g' | xargs)
    local __execute_dry_run=$1
    local __dst_cos_service_instance=$2

    for profile in $__rclone_config_profiles
    do  
        echo profile - $profile
        
        prepare_backup_bucket $__dst_cos_service_instance $profile

        rclone_list_buckets $profile
        for bucket in $(rclone_list_buckets $profile)
        do
            echo bucket - $bucket
            if [[ $__execute_dry_run -eq 1 ]]; then
                echo Executing rclone dry run!
                perform_dry_run $profile $bucket $__dst_cos_service_instance $profile
            else
                echo Executing rclone copy!
                perform_copy $profile $bucket $__dst_cos_service_instance $profile
            fi
            echo
        done
        echo "##############"
        echo
    done
}

bucket_region() {

    local __bucket=$1

    ibmcloud cos bucket-location-get --bucket $__bucket --output json | jq -r '.LocationConstraint' | sed -E 's/-(standard|smart)//g'
}

bucket_endpoint() {

    local __bucket_name=$1
    local __use_private_endpoint=$2
    local __region=$(bucket_region $__bucket_name)
    local __public_endpoint="s3.$__region.cloud-object-storage.appdomain.cloud"
    local __private_endpoint="s3.private.$__region.cloud-object-storage.appdomain.cloud"

    if [[ $__use_private_endpoint -eq 1 ]]; then
        echo $__private_endpoint
    else
        echo $__public_endpoint
    fi
}

get_HMAC_key_from_service_credential() {

    local __service_credential_name=$1
    local __hmac_keys=$(ibmcloud resource service-key $__service_credential_name --output json | jq '.[0].credentials.cos_hmac_keys')
   
    echo $__hmac_keys
}

rclone_list_buckets() {
    
    local __profile=$1

    rclone lsd $__profile: | awk 'NF>1{print $NF}'
}

get_service_instance_from_json_base64() {

    local __service_instance_json_base64=$1
    local __crn=$(echo $1 | base64 --decode | jq -r .crn)
    local __service_instance=$(echo $__crn | cut -d ':' -f 8)

    echo $__service_instance
}

create_rclone_profile() {

    local __profile_name=$1
    local __access_key_id=$2
    local __secret_access_key=$3
    local __use_private_endpoint=$4
    local __backup_profile=$5

    config_ibmcloud_cli_cos $__access_key_id $__secret_access_key > /dev/null 2>&1
    local __first_bucket=$(ibmcloud cos buckets | sed -e '1,4d' | cut -d ' ' -f 1 | head -n 1)

    if [[ -n "$__first_bucket" || -n "$__backup_profile" ]]; then

        local __endpoint=$(bucket_endpoint $__first_bucket $__use_private_endpoint)
        local __profile="[$__profile_name]\ntype = s3\nprovider = IBMCOS\nenv_auth = false\naccess_key_id = $__access_key_id\nsecret_access_key = $__secret_access_key\nendpoint = $__endpoint\n\n"

        printf "$__profile" >> ~/.config/rclone/rclone.conf
        printf "$__profile\n"
    else 
        printf "Service instance '$__profile_name' has no buckets. Not creating an rclone profile.\n"
    fi
}

prepare_service_credentials() {

    local __cos_service_instance_id=$1
    local __service_credential_name=$(create_hmac_service_credential_name "$__cos_service_instance_id")

    ibmcloud resource service-key "$__service_credential_name" > /dev/null 2>&1
    local __service_key_exists=$(echo $?)

    if [[ $__service_key_exists -eq 1 ]]; then 

        echo "Service key doesn't exist. Creating service key."
        create_hmac_service_credential "$__cos_service_instance_id" "$__service_credential_name"
    fi

    local __hmac_keys=$(get_HMAC_key_from_service_credential "$__service_credential_name")
    echo $__hmac_keys
}

create_rclone_profiles() {

    local __use_private_endpoint=$1

    local __cos_service_instances_json_base64=$(ibmcloud resource search "service_name:cloud-object-storage" --output json | jq -r '.items' | jq -r '.[] | @base64')

    for row in $__cos_service_instances_json_base64
    do
        local __cos_service_instance_id=$(get_service_instance_from_json_base64 $row)
        local __hmac_keys=$(prepare_service_credentials $__cos_service_instance_id)
        local __access_key_id=$(echo $__hmac_keys | jq -r '.access_key_id')
        local __secret_access_key=$(echo $__hmac_keys | jq -r '.secret_access_key')
        
        create_rclone_profile "$__cos_service_instance_id" $__access_key_id $__secret_access_key $__use_private_endpoint
    done    
}

create_hmac_service_credential_name() {

    local __cos_service_instance_name=$1
    local __remove_spaces=$(echo $__cos_service_instance_nam  e | sed 's/ /-/g')
    local __service_credential_suffix=".service-credentials"
    local __service_credential_name="$__remove_spaces$__service_credential_suffix"

    echo $__service_credential_name
}

create_hmac_service_credential() {

    local __cos_service_instance_name=$1
    local __service_credential_name=$2
    
    echo "__cos_service_instance_name: '$__cos_service_instance_name'"
    echo "__service_credential_name: '$__service_credential_name'"
    ibmcloud resource service-key-create "$__service_credential_name" Writer --instance-id "$__cos_service_instance_name" --parameters '{"HMAC":true}'
}