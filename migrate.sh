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
export database_found=false
export rename=false
export skip_pvc=false

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
export current_version
current_version=$(git rev-parse --abbrev-ref HEAD)

# source functions
source check/check.sh
source create/create.sh
source create/database.sh
source create/vars.sh
source find/find.sh
source lifecycle/lifecycle.sh
source lifecycle/start_app.sh
source lifecycle/stop_app.sh
source prompt/prompt.sh
source pvc/cleanup.sh
source pvc/info.sh
source pvc/match.sh
source pvc/rename.sh
source self-update/self-update.sh

script_help() {
    echo -e "${bold}Usage:${reset} bash $(basename "$0") [options]"
    echo
    echo -e "${bold}Options:${reset}"
    echo -e "  ${blue}-s${reset}, ${blue}--skip${reset}       Continue with a previously started migration"
    echo -e "  ${blue}-n${reset}, ${blue}--no-update${reset}  Do not check for script updates"
    echo -e "  ${blue}--force${reset}       Force migration without checking for db pods"
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--skip)
            skip=true
            ;;
        -n|--no-update)
            no_update=true
            ;;
        --force)
            force=true
            ;;
        -h|--help)
            script_help
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done

main() {
    check_privileges
    if [[ "${no_update}" == false ]]; then
        auto_update_script
    fi

    find_apps_pool

    if [[ "${skip}" == true ]]; then
        prompt_migration_path
        import_variables
    else
        prompt_app_name
        check_for_db
        get_pvc_info
        check_pvc_info_empty
        create_migration_dataset
        get_pvc_parent_path
        create_app_dataset
        if [[ "${database_found}" == true ]]; then
            backup_cnpg_databases "${appname}" "/mnt/${migration_path}/backup"
        fi
        stop_app_if_needed
        create_backup_pvc
        create_backup_metadata
        if [[ "$skip_pvc" == "true" ]]; then
            rename_original_pvcs
        fi
        delete_original_app
    fi
    
    prompt_rename
    create_and_wait_for_pvcs

    stop_app_if_needed
    unset pvc_info
    if [[ "${skip_pvc}" == false ]]; then
        get_pvc_info
        check_pvc_info_empty
        get_pvc_parent_path
        destroy_new_apps_pvcs
        rename_migration_pvcs
    fi
    
    if [[ "${database_found}" == true ]]; then
        restore_database "${appname}" "/mnt/${migration_path}/backup/${appname}.sql"
    fi
    cleanup_datasets
    start_app "${appname}"
}

main
