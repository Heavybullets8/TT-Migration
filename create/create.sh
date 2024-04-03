#!/bin/bash

create_migration_dataset() {
    local path=${ix_apps_pool}/migration

    # Check if the migration dataset exists, and create it if it doesn't
    if ! zfs list "${ix_apps_pool}/migration" >/dev/null 2>&1; then
        echo -e "${bold}Creating migration dataset...${reset}"
        if zfs create "${ix_apps_pool}/migration"; then
            echo -e "${green}Dataset created: ${blue}${ix_apps_pool}/migration${reset}"
            echo
        else
            echo -e "${red}Error: Failed to create migration dataset.${reset}"
            exit 1
        fi
    fi
}

create_app_dataset() {
    local path=${ix_apps_pool}/migration/${appname}
    export migration_path

    # Check if the app dataset exists, and create it if it doesn't
    if ! zfs list "$path" >/dev/null 2>&1; then
        echo -e "${bold}Creating app dataset...${reset}"
        if zfs create "$path"; then
            echo -e "${green}Dataset created: ${blue}$path${reset}"
            echo
        else
            echo "${red}Error: Failed to create app dataset.${reset}"
            exit 1
        fi
    fi
    migration_path=$path
}

create_backup_pvc() {
    local backup_path=/mnt/${migration_path}/backup
    local backup_name="config-backup.json"  # Use .json to emphasize the data format

    DATA=$(midclt call chart.release.get_instance "$appname" | jq '
        .config | 
        walk(if type == "object" then with_entries(select(.key | startswith("ix") | not)) else . end) | 
        if has("persistence") then
            .persistence |= with_entries( if .value.storageClass != "SCALE-ZFS" then .value.storageClass = "" else . end)
        else
            .
        end |
        .global.ixChartContext.isStopped = true |
        .global.stopAll = true 
    ')
    
    if [[ -z $DATA ]]; then
        echo -e "${red}Error: Failed to get app config.${reset}"
        exit 1
    fi

    # Ensure backup directory exists
    mkdir -p "$backup_path"

    # Save data to backup path
    echo "$DATA" > "${backup_path}/${backup_name}"
}

create_backup_metadata() {
    local metadata_path=/mnt/${migration_path}/backup
    local metadata_name="metadata-backup.json"
    local chart_name catalog_train metadata_json

    # Fetch metadata
    chart_name=$(midclt call chart.release.get_instance "$appname" | jq -r '.chart_metadata.name')
    catalog=$(midclt call chart.release.get_instance "$appname" | jq -r '.catalog')
    catalog_train=$(midclt call chart.release.get_instance "$appname" | jq -r '.catalog_train')


    # Construct JSON object with the metadata
    metadata_json=$(jq -n \
                          --arg chart_name "$chart_name" \
                          --arg catalog "$catalog" \
                          --arg catalog_train "$catalog_train" \
                          '{chart_name: $chart_name, catalog: $catalog, catalog_train: $catalog_train}')
    

    mkdir -p "$metadata_path"
    echo "$metadata_json" > "${metadata_path}/${metadata_name}"
}

create_application() {
    local backup_path="/mnt/${migration_path}/backup"
    local metadata_name="$backup_path/metadata-backup.json"
    local backup_name="$backup_path/config-backup.json"
    local max_retries=5
    local retry_count=0
    local job_state
    local job_id
    
    echo -e "${bold}Creating the application...${reset}"

    metadata=$(cat "${metadata_path}/${metadata_name}")
    chart_name=$(echo "$metadata" | jq -r '.chart_name')
    catalog=$(echo "$metadata" | jq -r '.catalog')
    catalog_train=$(echo "$metadata" | jq -r '.catalog_train')
    DATA=$(cat "${metadata_path}/${backup_name}")

    # Construct and execute the reinstallation command, capturing the job ID
    command=$(jq -n \
                    --arg release_name "$appname" \
                    --arg chart_name "$chart_name" \
                    --arg catalog "$catalog" \
                    --arg catalog_train "$catalog_train" \
                    --argjson values "$DATA" \
                    '{release_name: $release_name, catalog: $catalog, item: $chart_name, train: $catalog_train, values: $values}')
    
    while [[ $retry_count -lt $max_retries ]]; do
        job_id=$(midclt call chart.release.create "$command" | jq -r '.')
        
        while true; do
            job_state=$(midclt call core.get_jobs '[["id", "=", '"$job_id"']]' | jq -r '.[0].state')
            if [[ $job_state == "SUCCESS" ]]; then
                echo -e "${green}Success${reset}\n"
                return 0
            elif [[ $job_state == "FAILED" ]]; then
                echo -e "${yellow}Retrying...${reset}"
                break
            else
                sleep 10  # Check again in 10 seconds
            fi
        done

        ((retry_count++))
    done

    echo -e "${red}Error: Failed to create the application after $max_retries retries.${reset}"
    return 1
}

wait_for_pvcs() {
    local namespace="ix-$appname"
    local max_wait=500  # Total wait time for PVCs to be bound
    local interval=10   # Interval between checks
    local elapsed_time=0

    echo -e "${bold}Waiting for PVCs to be ready...${reset}"

    if [[ "$skip_pvc" == true ]]; then
        echo -e "${yellow}Skipped${reset}"
    else
        while [[ $elapsed_time -lt $max_wait ]]; do
            local bound_pvcs total_pvcs
            bound_pvcs=$(k3s kubectl get pvc -n "$namespace" --no-headers | grep -c 'Bound')
            total_pvcs=$(k3s kubectl get pvc -n "$namespace" --no-headers | wc -l)
            
            if [[ $total_pvcs -gt 0 && $bound_pvcs -eq $total_pvcs ]]; then
                echo -e "${green}Success${reset}"
                return 0
            else
                sleep $interval
                elapsed_time=$((elapsed_time + interval))
                echo "Waiting... ${elapsed_time}s elapsed."
            fi
        done

        echo -e "${red}Error:${reset} Not all PVCs for $appname are bound after ${max_wait} seconds."
        exit 1
    fi
}
