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
export original_pvs_count
export ix_apps_pool
export migration_path
export rename=false
export migrate_pvs=false
export migrate_db=false
export cnpgpvc=false
export script_progress="start"
export traefik_ingress_integration_enabled=false

# flags
export force=false
export skip=false
export no_update=false


export script=$(readlink -f "$0")
export script_path=$(dirname "$script")
export script_name="migrate.sh"
export args=("$@")
script=$(readlink -f "$0")
script_path=$(dirname "$script")
script_name="migrate.sh"
args=("$@")
cd "$script_path" || { echo "Error: Failed to change to script directory"; exit; } 

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
    echo -e "  ${blue}--force${reset}               Force migration without checking for db pods"
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
    check_privileges || exit 1
    if [[ "${no_update}" == false ]]; then
        auto_update_script
    fi

    echo -e "\n${yellow}You are on the legacy branch, don't forget to switch back to the main branch once you are done finishing your in-progress legacy migrations!:${reset}"
    echo -e "${blue}git checkout main${reset}\n"

    find_apps_pool || exit 1

    if [[ "${skip}" == true ]]; then
        prompt_migration_path || exit 1
        # import_variables
        source "/mnt/$migration_path/variables.txt" 
    fi

    case $script_progress in
        start)
            prompt_app_name
            if [[ "${force}" == false ]]; then
                check_health || exit 1
            fi
            check_for_db
            get_pvc_info
            check_pvc_info_empty
            create_migration_dataset || exit 1
            create_app_dataset || exit 1
            if [[ "${migrate_pvs}" == true ]]; then
                get_pvc_parent_path || exit 1
                get_original_pvs_count
            fi
            update_or_append_variable "appname" "${appname}"
            update_or_append_variable "namespace" "${namespace}"
            update_or_append_variable "migrate_db" "${migrate_db}"
            update_or_append_variable "migrate_pvs" "${migrate_pvs}"
            update_or_append_variable "script_progress" "backup_cnpg_databases"
            ;& 
        backup_cnpg_databases)
            if [[ "${migrate_db}" == true ]]; then
                if prompt_dump_type; then  
                    backup_cnpg_databases "${appname}" "/mnt/${migration_path}/backup" || exit 1
                else
                    mkdir -p "/mnt/${migration_path}/backup"
                    if search_for_database_file "/mnt/${migration_path}/backup" "${appname}.sql"; then
                        echo -e "${green}Database file found. ${reset}" 
                    else
                        echo -e "${yellow}Database file not found. Please provide the database file in the backup folder ${blue}/mnt/${migration_path}/backup${yellow} and re-run the script with the ${blue}--skip${yellow} flag, then select the manual option again.${reset}"
                        exit 1 
                    fi
                fi
                [[ "${migrate_pvs}" == true && $skip == true ]] && get_pvc_info
            fi
            update_or_append_variable "script_progress" "create_backup_pvc"
            ;&
        create_backup_pvc)
            create_backup_pvc || exit 1
            update_or_append_variable "script_progress" "create_backup_metadata"
            ;&
        create_backup_metadata)
            create_backup_metadata || exit 1
            update_or_append_variable "script_progress" "rename_original_pvcs"
            ;&
        rename_original_pvcs)
            if [[ "$migrate_pvs" == true ]]; then
                stop_app_if_needed || exit 1
                rename_original_pvcs || exit 1
            fi
            update_or_append_variable "script_progress" "delete_original_app"
            ;&
        delete_original_app)
            if check_if_app_exists "${appname}" >/dev/null 2>&1; then
                delete_original_app || exit 1
            fi
            update_or_append_variable "script_progress" "prompt_rename"
            ;&
        prompt_rename)
            prompt_rename
            update_or_append_variable "script_progress" "create_application"
            ;&
        create_application)
            if ! check_if_app_exists "${appname}" >/dev/null 2>&1; then
                create_application || exit 1
            fi
            update_or_append_variable "script_progress" "wait_for_pvcs"
            ;&
        wait_for_pvcs)
            if [[ "${migrate_pvs}" == true ]]; then
                wait_for_pvcs || exit 1
            fi
            update_or_append_variable "script_progress" "swap_pvc"
            ;&
        swap_pvc)
            if [[ "${migrate_pvs}" == true ]]; then
                stop_app_if_needed || exit 1
                unset pvc_info
                get_pvc_info
                check_pvc_info_empty
                get_pvc_parent_path || exit 1
                destroy_new_apps_pvcs || exit 1
                rename_migration_pvcs || exit 1
            fi
            update_or_append_variable "script_progress" "restore_database"
            ;&
        restore_database)
            if [[ "${migrate_db}" == true ]]; then
                restore_database "${appname}" || exit 1
            fi
            update_or_append_variable "script_progress" "restore_traefik_ingress"
            ;&
        restore_traefik_ingress)
            if [[ "${traefik_ingress_integration_enabled}" == true ]]; then
                restore_traefik_ingress || exit 1
            fi
            update_or_append_variable "script_progress" "cleanup_datasets"
            ;&
        cleanup_datasets)
            cleanup_datasets || exit 1
            ;&
        start_app)
            start_app "${appname}"
            ;;
        *)
            echo -e "${red}Error: Invalid script progress${reset}"
            exit 1
            ;;
    esac
}

main
