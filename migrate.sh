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
export no_update=false
export pvc_info=()


# source functions
source check/check.sh
source create/create.sh
source find/find.sh
source lifecycle/lifecycle.sh
source lifecycle/start_app.sh
source lifecycle/stop_app.sh
source prompt/prompt.sh
source pvc/pvc.sh
source self-update/self-update.sh

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--skip)
            skip=true
            ;;
        -n|--no-update)
            no_update=true
            ;;
        -h|--help)
            help
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done

help() {
    echo -e "${bold}Usage:${reset} $(basename "$0") [options]"
    echo
    echo -e "${bold}Options:${reset}"
    echo -e "  ${blue}-s${reset}, ${blue}--skip${reset}       Continue with a previously started migration"
    echo -e "  ${blue}-n${reset}, ${blue}--no-update${reset}  Do not check for script updates"
}

main() {
    check_privileges
    if [[ "${no_update}" == false ]]; then
        auto_update_script
    fi
    prompt_app_name
    check_for_db_pods "${namespace}"
    get_pvc_info
    check_pvc_info_empty
    find_apps_pool
    create_migration_dataset
    get_pvc_parent_path

    if [[ "${skip}" == true ]]; then
        prompt_migration_path
    else
        create_app_dataset
        stop_app_if_needed
        prompt_create_backup
        rename_original_pvcs
        delete_original_app
        prompt_rename
        check_for_new_app
    fi
    
    stop_app_if_needed
    unset pvc_info
    get_pvc_info
    check_pvc_info_empty
    
    if [[ "${rename}" = true ]]; then
        get_pvc_parent_path
    fi
    
    destroy_new_apps_pvcs
    rename_migration_pvcs
    cleanup_datasets
    start_app "${appname}"
}


# Run the main function
main
