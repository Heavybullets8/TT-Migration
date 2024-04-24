#!/bin/bash

create_migration_dataset() {
    local path=${ix_apps_pool}/migration

    # Check if the migration dataset exists, and create it if it doesn't
    if ! zfs list "$path" >/dev/null 2>&1; then
        echo -e "${bold}Creating migration dataset...${reset}"
        if zfs create "$path"; then
            echo -e "${green}Dataset created: ${blue}$path${reset}"
            echo
        else
            echo -e "${red}Error: Failed to create migration dataset.${reset}"
            exit 1
        fi
    fi
}

create_app_dataset() {
    local path="${ix_apps_pool}/migration/${appname}"

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

restore_traefik_ingress() {
    echo -e "\n${bold}Restoring Traefik ingress...${reset}"

    local backup_path="/mnt/${migration_path}/backup"
    local ingress_backup_file="${backup_path}/ingress_backup.json"

    if [[ ! -f "$ingress_backup_file" ]]; then
        echo -e "${red}Ingress backup file not found.${reset}"
        exit 1
    fi

    # Read the ingress backup from the file
    local ingress_backup
    ingress_backup=$(<"$ingress_backup_file")

    if [[ -z "$ingress_backup" ]]; then
        echo -e "${red}Ingress backup is empty.${reset}"
        exit 1
    fi

    echo "$ingress_backup_file"

    # Execute the command to update the chart release with the new settings
    local output
    output=$(cli -c "app chart_release update chart_release=\"$appname\" values=$ingress_backup" 2>&1)
    local status=$?

    # Check the exit status of the command
    if [[ $status -eq 0 ]]; then
        echo -e "${green}Success${reset}"
    else
        echo -e "${red}Failed${reset}"
        echo "$output"
        exit 1
    fi
}




create_backup_pvc() {
    local backup_path=/mnt/${migration_path}/backup
    local backup_name="config-backup.json"  # Use .json to emphasize the data format
    
    # Fetch the application configuration
    DATA=$(midclt call chart.release.get_instance "$appname" | jq '.')
    
    # Check if the application is Traefik and if the Traefik ingress integration is enabled
    if echo "$DATA" | jq -e '.chart_metadata.name == "traefik" and .config.ingress.main.integrations.traefik.enabled == true' >/dev/null; then
        traefik_ingress_integration_enabled=true
        # Set Traefik ingress integration to false
        
        # Backup the entire ingress configuration
        ingress_backup=$(echo "$DATA" | jq -c '.config.ingress')

        DATA=$(echo "$DATA" | jq '.config.ingress.main.integrations.traefik.enabled = false')
        update_or_append_variable traefik_ingress_integration_enabled true
    fi

    DATA=$(echo "$DATA" | jq '
        .config |
        walk(
            if type == "object" then 
                with_entries(select(.key | startswith("ix") | not)) 
            else 
                . 
            end
        ) | 
        walk(
            if type == "object" and has("storageClass") and .storageClass == "SCALE-ZFS" then
                .storageClass = ""
            else
                .
            end
        ) |
        .global.ixChartContext.isStopped = true |
        .global.stopAll = true 
    ')

    if [[ -z $DATA ]]; then
        echo -e "${red}Error: Failed to get app config.${reset}"
        exit 1
    fi

    # Ensure backup directory exists
    mkdir -p "$backup_path"

    if [[ $traefik_ingress_integration_enabled == true ]]; then
        echo "$ingress_backup" > "${backup_path}/ingress_backup.json"
    fi

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
    echo -e "Job ID: $job_id"
    echo -e "Error Output:"
    echo -e "$(midclt call core.get_jobs '[["id", "=", '"$job_id"']]' | jq -r '.')"
    exit 1
}

wait_for_pvcs() {
    local namespace="ix-$appname"
    local max_wait=500  # Total wait time for PVCs to be bound
    local interval=10   # Interval between checks
    local elapsed_time=0

    echo -e "${bold}Waiting for PVCs to be ready...${reset}"
    while [[ $elapsed_time -lt $max_wait ]]; do
        local bound_pvcs
        bound_pvcs=$(k3s kubectl get pvc -n "$namespace" --no-headers | grep -c 'Bound')
        
        if [[ $bound_pvcs -ge $original_pvs_count ]]; then
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
}
