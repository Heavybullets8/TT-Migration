#!/bin/bash

# vars
export reset='\033[0m'
export red='\033[0;31m'
export yellow='\033[1;33m'
export green='\033[0;32m'
export blue='\033[0;34m'
export bold='\033[1m'
export gray='\033[38;5;7m'
export namespace
export appname
export ix_apps_pool
skip=false

# source functions
source check/check.sh
source find/find.sh
source lifecycle/lifecycle.sh
source lifecycle/start_app.sh
source lifecycle/stop_app.sh
source prompt/prompt.sh
source pvc/pvc.sh

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--skip)
            skip=true
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done


main() {
    find_apps_pool
    check_migration_dataset

    echo

    prompt_app_name
    check_for_db_pods "${namespace}"
    get_pvc_info
    check_pvc_count "original"
    get_pvc_parent_path
    echo

    if [ "${skip}" = false ]; then
        stop_app_if_needed
        echo
        rename_original_pvcs
        echo
        verify_rename
        echo
        delete_original_app
    fi

    prompt_rename
    check_for_new_app

    echo

    stop_app_if_needed

    echo
    get_pvc_info
    check_pvc_count "new"
    destroy_new_apps_pvcs

    echo

    rename_migration_pvcs

    echo

    start_app "${appname}"
}


# Run the main function
main
