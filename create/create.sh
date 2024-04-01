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

    DATA=$(midclt call chart.release.get_instance "$appname" | jq -c '.config')
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
    catalog_train=$(midclt call chart.release.get_instance "$appname" | jq -r '.catalog_train')


    # Construct JSON object with the metadata
    metadata_json=$(jq -n \
                          --arg chart_name "$chart_name" \
                          --arg catalog_train "$catalog_train" \
                          '{chart_name: $chart_name, catalog_train: $catalog_train}')
    

    mkdir -p "$metadata_path"
    echo "$metadata_json" > "${metadata_path}/${metadata_name}"
}

create_application() {
    local backup_path=/mnt/${migration_path}/backup
    local metadata_name="$backup_path/metadata-backup.json"
    local backup_name="$backup_path/config-backup.json"
    local metadata chart_name catalog_train DATA command

    metadata=$(cat "${metadata_path}/${metadata_name}")
    chart_name=$(echo "$metadata" | jq -r '.chart_name')
    catalog_train=$(echo "$metadata" | jq -r '.catalog_train')
    DATA=$(cat "${metadata_path}/${backup_name}")

    # Construct the reinstallation command
    command=$(jq -n \
                    --arg release_name "$appname" \
                    --arg chart_name "$chart_name" \
                    --arg catalog_train "$catalog_train" \
                    --argjson values "$DATA" \
                    '{release_name: $release_name, catalog: "TRUECHARTS", item: $chart_name, train: $catalog_train, values: $values}')
    
    midclt call chart.release.create "$command" > /dev/null
}

create_and_wait() {
    local max_retries=3
    local retry_count=0

    echo -e "${bold}Creating the application...${reset}"

    if [[ $skip == true ]]; then
        wait_for_pvcs && return 0
    fi

    while [[ $retry_count -lt $max_retries ]]; do
        create_application
        sleep 15  # Allow some time for the application to be created
        
        if wait_for_pvcs; then
            echo -e "${green}Success:${blue} All PVCs are bound.${reset}"
            break  # Exit the loop if PVCs are bound
        else
            echo -e "${yellow}Warning: Waiting for PVCs failed, retrying (${retry_count}/${max_retries})...${reset}"
            ((retry_count++))
        fi
    done

    if [[ $retry_count -eq $max_retries ]]; then
        echo -e "${red}Error:${reset} Failed to create the application after ${max_retries} attempts."
        exit 1
    fi
}