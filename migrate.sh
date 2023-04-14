#!/bin/bash

# colors
reset='\033[0m'
red='\033[0;31m'
yellow='\033[1;33m'
green='\033[0;32m'
blue='\033[0;34m'
bold='\033[1m'
gray='\033[38;5;7m'

source stop_app.sh
source start_app.sh

dry_run=0
skip=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            dry_run=1
            ;;
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

function execute() {
    if [[ ${dry_run} -eq 1 ]]; then
        echo "[DRY RUN] ${*}"
    else
        "${@}"
    fi
}

find_apps_pool() {
    echo "Finding apps pool..."
    ix_apps_pool=$(cli -c 'app kubernetes config' | 
                       grep -E "pool\s\|" | 
                       awk -F '|' '{print $3}' | 
                       sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Check if the apps pool exists
    if [ -z "${ix_apps_pool}" ]; then
        echo "Error: Apps pool not found."
        exit 1
    else
        echo "Found: ${ix_apps_pool}"
    fi
}

create_migration_dataset() {
    # Check if the migration dataset exists, and create it if it doesn't
    if ! zfs list "${ix_apps_pool}/migration" >/dev/null 2>&1; then
        echo "Creating migration dataset..."
        cmd=("zfs" "create" "${ix_apps_pool}/migration")
        if execute "${cmd[@]}"; then
            echo "Migration dataset created."
            echo
        else
            echo "Error: Failed to create migration dataset."
            exit 1
        fi
        echo "Migration dataset created."
        echo
    fi
}

prompt_app_name() {
    # Prompt the user for the app name
    read -r -p "Enter the application name: " appname
    ix_appname="ix-${appname}"
}

get_pvc_info() {
    # Grab the app's PVC names and volume names
    pvc_info=$(k3s kubectl get pvc -n "${ix_appname}" -o custom-columns="NAME:.metadata.name,VOLUME:.spec.volumeName" --no-headers)

    # Count the number of lines in the pvc_info variable
    num_lines=$(echo "${pvc_info}" | wc -l)
}

check_pvc_count() {
    # Check if there's more than one line or no lines, print an error message, and exit the script
    if [ "${num_lines}" -gt 1 ]; then
        echo "Error: More than one volume found. This script only supports applications with a single volume."
        exit 1
    elif [[ -z "$pvc_info" ]]; then
        echo "Error: No volume found. Please ensure that the application has at least one PVC."
        exit 1
    fi
}

destroy_new_apps_pvcs() {
    # Destroy the new app's PVCs
    echo "Destroying the new app's PVCs..."

    # Grab the app's PVC names and volume names
    pvc_info=$(k3s kubectl get pvc -n "${ix_appname}" -o custom-columns="NAME:.metadata.name,VOLUME:.spec.volumeName" --no-headers)

    # check if pvcs exist
    if [ -z "${pvc_info}" ]; then
        echo "Error: No PVCs found."
        exit 1
    fi

    echo "${pvc_info}" | while read -r line; do
        volume_name=$(echo "${line}" | awk '{print $2}')
        to_delete="${ix_apps_pool}/ix-applications/releases/${appname}/volumes/${volume_name}"
        cmd=("zfs" "destroy" "${to_delete}")
        if execute "${cmd[@]}"; then
            echo "Destroyed ${to_delete}"
        else
            echo "Error: Failed to destroy ${to_delete}"
            exit 1
        fi
    done

    echo
}

rename_migration_pvcs() {
    # Rename the migration PVCs to the new app's PVC names
    echo "Renaming the migration PVCs to the new app's PVC names..."

    # Get the list of migration PVCs
    migration_pvcs=$(zfs list -r "${ix_apps_pool}/migration" | grep "${appname}" | awk '{print $1}')

    # check if the migration PVCs exist
    if [ -z "${migration_pvcs}" ]; then
        echo "Error: No migration PVCs found."
        exit 1
    fi

    # Get the list of new app's volume names
    volume_name=$(echo "${pvc_info}" | awk '{print $2}')
    new_volume_names="${ix_apps_pool}/ix-applications/releases/${appname}/volumes/${volume_name}"

    # Read migration PVCs and new app's volume names line by line
    while read -r old new; do
        # Rename the migration PVC to the new app's volume name
        cmd=("zfs" "rename" "${old}" "${new}")
        if execute "${cmd[@]}"; then
            echo "Renamed ${old} to ${new}"
        else
            echo "Error: Failed to rename ${old} to ${new}"
            exit 1
        fi
    done < <(paste <(echo "$migration_pvcs") <(echo "$new_volume_names"))

    echo
}

rename_apps_pvcs() {
    # Rename the app's PVCs
    echo "Renaming the app's PVCs..."
    echo "${pvc_info}" | while read -r line; do
        pvc_name=$(echo "${line}" | awk '{print $1}')
        volume_name=$(echo "${line}" | awk '{print $2}')
        old_pvc_name="${ix_apps_pool}/ix-applications/releases/${appname}/volumes/${volume_name}"
        new_pvc_name="${ix_apps_pool}/migration/${appname}-${pvc_name}"
        cmd=("zfs" "rename" "${old_pvc_name}" "${new_pvc_name}")
        if execute "${cmd[@]}"; then 
            echo "Renamed ${old_pvc_name} to ${new_pvc_name}"
        else
            echo "Error: Failed to rename ${old_pvc_name} to ${new_pvc_name}"
            exit 1
        fi
    done
}

verify_rename() {
    # Verify the rename was successful
    echo "Verifying the rename was successful..."
    if zfs list -r "${ix_apps_pool}/migration" | grep "${appname}" > /dev/null; then
        echo "Rename successful."
    else
        echo "Rename failed."
        exit 1
    fi
}

delete_old_version_of_app() {
    echo "Deleting the old version of the app..."

    cmd=("cli" "-c" "app chart_release delete release_name=\"${appname}\"")
    if execute "${cmd[@]}"; then
        echo "Old version of the app has been successfully deleted."
    else
        echo "Error: Failed to delete the old version of the app."
        exit 1
    fi
}

before_skip() {
    stop_app_if_needed

    echo

    # Copy the app's config to a safe place
    echo "Please copy the app's config manually from the GUI (Edit app) and save it in a safe place."
    echo "Take Screenshots or whatever you want."
    read -rp "Press Enter to continue..."

    echo

    # Rename the app's PVCs
    rename_apps_pvcs

    echo

    # Verify the rename was successful
    verify_rename

    echo

    # Delete the old version of the app
    delete_old_version_of_app

    echo
}

main() {
    find_apps_pool
    create_migration_dataset

    echo

    prompt_app_name
    get_pvc_info
    check_pvc_count

    echo

    if [ "${skip}" = false ]; then
        before_skip
    fi

    # Install the new version# of the app
    echo "Please install the new app from the catalog manually and configure it as the deleted app."
    echo "Ensure you use the same name as the old app."
    read -rp "Press Enter to continue..."

    echo

    stop_app_if_needed

    echo

    destroy_new_apps_pvcs

    echo

    rename_migration_pvcs

    echo

    start_app "${appname}"
}

stop_app_if_needed() {
    # Stop application if not stopped
    status=$(cli -m csv -c 'app chart_release query name,status' | 
                grep "^$appname," | 
                awk -F ',' '{print $2}'| 
                sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [[ "$status" != "STOPPED" ]]; then
        echo -e "\nStopping ${blue}$appname${reset} prior to mount"
        cmd=("stop_app" "$appname")
        execute "${cmd[@]}"
        result=$(handle_stop_code "$?")
        if [[ $? -eq 1 ]]; then
            echo -e "${red}${result}${reset}"
            exit 1
        else
            echo -e "${green}${result}${reset}"
        fi
    fi
    echo
}

# Run the main function
main
