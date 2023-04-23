#!/bin/bash

check_privileges() {
# Check user's permissions
if [[ $(id -u) != 0 ]]; then
    echo -e "${red}This script must be run as root.${reset}" >&2
    echo -e "${red}Please run the following command:${reset}" >&2
    echo -e "${red}sudo bash migrate.sh${reset}" >&2
    echo -e "${red}or run the script as the ${blue}root${reset} user${reset}" >&2
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
check_if_app_exists() {
    local app_name=$1
    echo
    echo -e "${bold}Checking if app exists...${reset}"
    cli -m csv -c 'app chart_release query name' | tr -d " \t\r" | grep -qE "^${app_name}$"
}

check_pvc_count() {
    check_type=$1
    # Check if there's more than one line or no lines, print an error message, and exit the script
    
    if [[ -z "$pvc_info" && $check_type == "original" ]]; then
        echo -e "${red}Error: No volume found. Please ensure that the application has at least one PVC.${reset}"
        exit 1
    elif [[ -z "$pvc_info" && $check_type == "new" ]]; then
        echo -e "${red}Error: The new app does not appear to have any PVCs.${reset}"
        echo -e "If you previously ran this script for the same app, you may need to do the following:"
        echo -e "    1. Delete the new app"
        echo -e "    2. Download the new app's chart again with the same settings as the original"
        echo -e "    3. Run this script again with ${blue}bash migrate.sh --skip${reset}"
        exit 1
    fi
}

check_for_new_app() {
    # Keep asking to continue until app is found
    echo -e "Please install the new version of the app from the catalog manually."
    echo -e "Ensure you use ${blue}${appname}${reset} as the name."
    while true; do
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
        if check_if_app_exists "${appname}"; then
            echo -e "${green}Found: ${blue}${appname}${reset}"
            break
        else
            echo -e "App not found. Please install the new version of the app from the catalog manually."
            echo -e "Ensure you use ${blue}${appname}${reset} as the name."
        fi
    done
}

check_filtered_apps() {
    # Define a function to process each app name
    process_app_name() {
        appname=$1

        # Run the command and directly check if the values are true, and include the reason
        midclt call chart.release.get_instance "$appname" | jq -r '
            if .config.operator.enabled == true then
                .name + ",operator"
            else
                empty
            end,
            if .config.cnpg.main.enabled == true then
                .name + ",cnpg"
            else
                empty
            end
            | select(length > 0)
        '
    }

    # Define a function to wait for a free slot in the semaphore
    wait_for_slot() {
        while true; do
            # Count the number of background jobs
            job_count=$(jobs -p | wc -l)

            # Check if there's a free slot
            if [[ $job_count -lt 5 ]]; then
                break
            fi

            # Wait for a short period before checking again
            sleep 0.1
        done
    }

    # Check if an array was passed as an argument
    if [ $# -eq 0 ]; then
        # Define the app names array using the command
        mapfile -t app_names < <(cli -m csv -c 'app chart_release query name' | tail -n +2 | sort | tr -d " \t\r" | awk 'NF')
    else
        # Use the passed array
        app_names=("$@")
    fi

    # Process the app names with a maximum of 5 concurrent processes
    for appname in "${app_names[@]}"; do
        wait_for_slot
        process_app_name "$appname" &
    done

    # Wait for any remaining jobs to finish
    wait
}