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
export migration_path
export rename=false
export script=$(readlink -f "$0")
export script_path=$(dirname "$script")
export script_name="migrate.sh"
export args=("$@")
skip=false
script=$(readlink -f "$0")
script_path=$(dirname "$script")
script_name="migrate.sh"
args=("$@")

# source functions
source check/check.sh
source create/create.sh
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


# TODO: 1. create the datasets only if PV's were found for the app
#       2. Remove check_pvc_count and instead check if PV's exist with get_pvc_info
#       3. Create a function to cleanup empty datasets on successful migration
#       4. Also remove the migration dataset if no child datasets exist within it
main() {
    check_privileges
    prompt_app_name
    check_for_db_pods "${namespace}"
    find_apps_pool
    create_migration_dataset

    if [[ "${skip}" == true ]]; then
        prompt_migration_path
    else
        create_app_dataset
    fi

    get_pvc_info
    # check_pvc_count "original"
    get_pvc_parent_path

    if [[ "${skip}" == false ]]; then
        stop_app_if_needed
        prompt_create_backup
        rename_original_pvcs
        delete_original_app
        prompt_rename
        check_for_new_app
    fi
    
    stop_app_if_needed
    get_pvc_info
    
    if [[ "${rename}" = true ]]; then
        get_pvc_parent_path
    fi
    
    # check_pvc_count "new"
    destroy_new_apps_pvcs
    rename_migration_pvcs
    remove_migration_app_dataset
    start_app "${appname}"
}


# Run the main function
main
