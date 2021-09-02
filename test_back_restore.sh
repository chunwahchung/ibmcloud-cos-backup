#!/bin/bash

test_rclone_config() {
    false
}

test_rclone_objects() {

    local __test_name="test_rclone_objects"
    local __source=$1
    local __destination=$2 
    local __suffix=".backup_restore_test.txt"
    local __src_file=$__source"_source"$__suffix
    local __dst_file=$__destination"_destination"$__suffix
    local __test_result=$__source"_to_"$__destination".test_result.txt"

    echo rclone profile source: $__source
    echo rclone profile destination: $__destination

    echo $__src_file
    echo $__dst_file

    rclone ls $__source: 2>&1 | tee $__src_file
    rclone ls $__destination: 2>&1 | tee $__dst_file

    diff $__src_file $__dst_file >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "PASSED $__test_name"
    else
        echo "FAILED $__test_name"
    fi
}

main() {

    local __source
    local __destination

    if [[ "$1" != "-h" && "$1" != "--help" &&  $# -lt 4 ]]; then
        printf '\033[1;31mFAILED\n\033[1;0m'
        echo Mandatory Flags '--destination' and '--source' are missing or not formatted properly. See test_back_restore.sh --help.
        exit 1
    fi

    while test $# -gt 0; do
        case "$1" in
            -d|--destination)
            shift
            __destination=$1
            shift
            ;;
            -s|--sources)
            shift
            __source=$1
            shift
            ;;
            -h|--help)
            echo "USAGE:"
            echo "./ibmcloud-cli.sh --source your_rclone_profile_name --destination your_rclone_profile_name"
            echo
            echo "DEFAULTS:"
            echo "By default, the script creates profiles with public endpoints and performs an rclone copy (not a dry run)."
            echo
            echo "OPTIONS:"
            echo "-h, --help                show brief help"
            echo "-d, --destination         destination corresponding to the rclone profile name to test"
            echo "-s, --source              source corresponding to the rclone profile name to test"
            exit 0
            ;;
            *)
            printf '\033[1;31mFAILED\n\033[1;0m'
            echo "'$1' is not a registered command. See ibmcloud-cli.sh --help."
            break
            ;;
        esac
    done

    test_rclone_objects $__source $__destination
}
main $1 $2 $3 $4