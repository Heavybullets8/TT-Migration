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
        exec sudo bash "$script_path/$script_name" "${args[@]}"
    else
        exit 1
    fi
fi
}

check_if_app_exists() {
    local app_name=$1
    echo -e "${bold}Checking if app exists...${reset}"
    cli -m csv -c 'app chart_release query name' | tr -d " \t\r" | grep -qE "^${app_name}$"
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

wait_for_namespace() {
    local timeout=500
    local interval=10
    local elapsed_time=0

    echo -e "${bold}Waiting up to ${timeout} seconds for namespace '${appname}' to be created...${reset}"

    while [[ $elapsed_time -lt $timeout ]]; do
        if k3s kubectl get namespace "ix-$appname" --no-headers -o custom-columns=":metadata.name" &> /dev/null; then
            echo -e "${green}Namespace exists.${reset}"
            return 0
        else
            sleep $interval
            elapsed_time=$((elapsed_time + interval))
        fi
    done

    echo -e "${red}Timeout reached. Namespace 'ix-${appname}' not found.${reset}"
    exit 1
}


wait_for_pvcs() {
    local max_wait interval start_time current_time timeout unbound_pvcs

    max_wait=300
    interval=10 

    start_time=$(date +%s)
    current_time=$start_time
    timeout=$((start_time + max_wait))


    echo -e "${bold}Waiting for PVCs of $appname to be bound...${reset}"

    while [[ $current_time -lt $timeout ]]; do
        unbound_pvcs=$(k3s kubectl get pvc -n "ix-$appname" --no-headers | grep -vc 'Bound')

        if [[ $unbound_pvcs -eq 0 ]]; then
            echo -e "${green}All PVCs for $appname are bound.${reset}"
            return 0
        else
            sleep $interval
        fi

        current_time=$(date +%s)
    done

    echo -e "${red}Timeout reached. Not all PVCs for $appname are bound.${reset}"
    exit 1
}
