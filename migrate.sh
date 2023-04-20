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
source allowed.sh

dry_run=0
skip=false
script=$(readlink -f "$0")
script_path=$(dirname "$script")
script_name="migrate.sh"
args=("$@")

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

check_privileges() {
# Check user's permissions
if [[ $(id -u) != 0 ]]; then
    echo -e "${red}This script must be run as root.${reset}" >&2
    echo -e "${red}Please run the following command:${reset}" >&2
    echo -e "${red}sudo bash migrate.sh${reset}" >&2
    echo -e "${red}or run the script as the \"root\" user${reset}" >&2
    echo -e "${red}su root${reset}" >&2

    # Prompt the user to retry with sudo
    echo -e "${yellow}Would you like to run the script with sudo? (y/n)${reset}"
    read -r answer
    if [[ $answer =~ ^[Yy]$ ]]; then
        exec sudo bash "$script_path"/$script_name "${args[@]}"
    else
        exit 1
    fi
fi
}


# Check if namespace has any database pods
check_for_db_pods() {
    local namespace=$1
    local db_regex='-(postgresql|mariadb|mysql|mongodb|redis|mssql|cnpg)'
    if k3s kubectl get pods,statefulsets -n "$namespace" -o=name | grep -E -- "$db_regex" | grep -v "pod/svclb"; then
        echo "The application contains a database pod or statefulset."
        echo "This migration script does not support migrating databases."
        echo "You may be able to restore the application following this guide instead:"
        echo "https://truecharts.org/manual/SCALE/guides/migration-pvc"
        exit 1
    fi   
}

# Function to check if the app exists
app_exists() {
    local app_name=$1
    echo
    echo "Checking if app exists..."
    cli -m csv -c 'app chart_release query name' | tr -d " \t\r" | grep -E "^${app_name}$"
}

find_most_similar_pvc() {
    local source_pvc=$1
    local max_similarity=0
    local most_similar_pvc=""
    local most_similar_volume=""

    for target_pvc_info in "${new_pvcs[@]}"; do
        IFS=',' read -ra pvc_and_volume_arr <<< "$target_pvc_info"
        target_pvc_name="${pvc_and_volume_arr[0]}"
        target_volume_name="${pvc_and_volume_arr[1]}"

        local len1=${#source_pvc}
        local len2=${#target_pvc_name}
        local maxlen=$(( len1 > len2 ? len1 : len2 ))
        local dist
        dist=$(python levenshtein.py "$source_pvc" "$target_pvc_name")
        local similarity=$(( 100 * ( maxlen - dist ) / maxlen ))

        if [ "$similarity" -gt "$max_similarity" ]; then
            max_similarity=$similarity
            most_similar_pvc=$target_pvc_name
            most_similar_volume=$target_volume_name
        fi
    done
    echo "$most_similar_volume"
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
            echo "Dataset created: ${ix_apps_pool}/migration"
            echo
        else
            echo "Error: Failed to create migration dataset."
            exit 1
        fi
    fi
}

prompt_app_name() {
    while true
    do
        # Prompt the user for the app name
        read -r -p "Enter the application name: " appname
        ix_appname="ix-${appname}"

        # Check if the app exists
        if app_exists "${appname}"; then
            echo "Found: ${appname}"
            break
        else
            echo "Error: App not found."
        fi
    done
}

get_pvc_info() {
    # Grab the app's PVC names and volume names
    pvc_info=$(k3s kubectl get pvc -n "${ix_appname}" -o custom-columns="NAME:.metadata.name,VOLUME:.spec.volumeName" --no-headers)
}

check_pvc_count() {
    check_type=$1
    # Check if there's more than one line or no lines, print an error message, and exit the script
    
    if [[ -z "$pvc_info" && $check_type == "original" ]]; then
        echo "Error: No volume found. Please ensure that the application has at least one PVC."
        exit 1
    elif [[ -z "$pvc_info" && $check_type == "new" ]]; then
        echo "Error: The new app does not appear to have any PVCs."
        echo "If you previously ran this script for the same app, you may need to do the following:"
        echo "    1. Delete the new app"
        echo "    2. Download the new app's chart again with the same settings as the original"
        echo "    3. Run this script again with ${blue}bash migrate.sh --skip${reset}"
        exit 1
    fi
}

destroy_new_apps_pvcs() {
    echo "Destroying the new app's PVCs..."

    # Create an array to store the new PVCs
    new_pvcs=()
    
    # Read the PVC info line by line and store the new PVCs in the new_pvcs array
    while read -r line; do
        pvc_and_volume=$(echo "${line}" | awk '{print $1 "," $2}')
        new_pvcs+=("${pvc_and_volume}")
    done < <(echo "${pvc_info}")

    if [ ${#new_pvcs[@]} -eq 0 ]; then
        echo "Error: No new PVCs found."
        exit 1
    fi

    for new_pvc in "${new_pvcs[@]}"; do
        IFS=',' read -ra pvc_and_volume_arr <<< "$new_pvc"
        volume_name="${pvc_and_volume_arr[1]}"
        to_delete="${ix_apps_pool}/ix-applications/releases/${appname}/volumes/${volume_name}"
        cmd=("zfs" "destroy" "${to_delete}")

        success=false
        attempt_count=0
        max_attempts=2

        while ! $success && [ $attempt_count -lt $max_attempts ]; do
            if output=$(execute "${cmd[@]}"); then
                echo "Destroyed ${to_delete}"
                success=true
            else
                if echo "$output" | grep -q "dataset is busy" && [ $attempt_count -eq 0 ]; then
                    echo "Dataset is busy, restarting middlewared and retrying..."
                    systemctl restart middlewared
                    sleep 5
                    stop_app_if_needed "$appname"
                    sleep 5
                else
                    echo "Error: Failed to destroy ${to_delete}"
                    echo "Error message: $output"
                    exit 1
                fi
            fi
            attempt_count=$((attempt_count + 1))
        done
    done
    echo
}

rename_migration_pvcs() {
    echo "Renaming the migration PVCs to the new app's PVC names..."

    # Create an array to store the migration PVCs
    migration_pvcs=()

    # Get the list of migration PVCs
    migration_pvcs_info=$(zfs list -r "${ix_apps_pool}/migration" | grep "${appname}" | awk '{print $1}')

    # Read the migration_pvcs_info line by line and store the migration PVCs in the migration_pvcs array
    while read -r line; do
        pvc_name=$(basename "${line}")
        migration_pvcs+=("${pvc_name}")
    done < <(echo "${migration_pvcs_info}")

    if [ ${#migration_pvcs[@]} -eq 0 ]; then
        echo "Error: No migration PVCs found."
        exit 1
    fi

    for old_pvc in "${migration_pvcs[@]}"; do
        most_similar_pvc=$(find_most_similar_pvc "$old_pvc")
        cmd=("zfs" "rename" "${ix_apps_pool}/migration/${old_pvc}" "${ix_apps_pool}/ix-applications/releases/${appname}/volumes/${most_similar_pvc}")
        if execute "${cmd[@]}"; then
            echo "Renamed ${ix_apps_pool}/migration/${old_pvc} to ${ix_apps_pool}/ix-applications/releases/${appname}/volumes/${most_similar_pvc}"
        else
            echo "Error: Failed to rename ${ix_apps_pool}/migration/${old_pvc} to ${ix_apps_pool}/ix-applications/releases/${appname}/volumes/${most_similar_pvc}"
            exit 1
        fi
    done

    echo
}

check_for_new_app() {
    # Keep asking to continue until app is found
    while true; do
        echo "Please install the new version of the app from the catalog manually."
        echo "Ensure you use the same name as the old app."
        while true; do
            read -n1 -s -rp "Press 'x' to continue..." key
            if [[ $key == "x" ]]; then
                echo -e "\nContinuing..."
                break
            else
                echo -e "\nInvalid key. Please press 'x' to continue."
            fi
        done

        echo

        # Check if the app exists
        if app_exists "${appname}"; then
            echo "Found: ${appname}"
            break
        else
            echo "App not found. Please install the new version of the app from the catalog manually."
            echo "Ensure you use the same name as the old app."
        fi
    done
}

rename_apps_pvcs() {
    # Rename the app's PVCs
    echo "Renaming the app's PVCs..."
    echo "${pvc_info}" | while read -r line; do
        pvc_name=$(echo "${line}" | awk '{print $1}')
        volume_name=$(echo "${line}" | awk '{print $2}')
        old_pvc_name="${ix_apps_pool}/ix-applications/releases/${appname}/volumes/${volume_name}"
        new_pvc_name="${ix_apps_pool}/migration/${pvc_name}"
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
    echo "I personally open two tabs, one tab with the old config open, and another tab with the new config open."
    while true; do
        read -n1 -s -rp "Press 'x' to continue..." key
        if [[ $key == "x" ]]; then
            echo -e "\nContinuing..."
            break
        else
            echo -e "\nInvalid key. Please press 'x' to continue."
        fi
    done


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
    check_privileges
    find_apps_pool
    create_migration_dataset

    echo

    prompt_app_name
    check_for_db_pods "${ix_appname}"
    get_pvc_info
    check_pvc_count "original"

    echo

    if [ "${skip}" = false ]; then
        before_skip
    fi

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

stop_app_if_needed() {
    # Stop application if not stopped
    status=$(cli -m csv -c 'app chart_release query name,status' | 
                grep "^$appname," | 
                awk -F ',' '{print $2}'| 
                sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [[ "$status" != "STOPPED" ]]; then
        echo -e "\nStopping ${blue}$appname${reset}"
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
