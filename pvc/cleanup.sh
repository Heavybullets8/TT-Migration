#!/bin/bash


destroy_new_apps_pvcs() {
    local new_app_pvc_info="${backup_path}/pvcs_new.json"
    local length

    echo -e "${bold}Destroying the new app's PVCs...${reset}"

    length=$(jq '[.[] | select(.ignored == false)] | length' "$new_app_pvc_info")

    if [ "$length" -eq 0 ]; then
        echo -e "${red}Error: No new PVCs found.${reset}"
        return 1
    fi

    while read -r pvc_entry; do
        local pvc_parent_path volume_name
        volume_name=$(echo "$pvc_entry" | jq -r '.pvc_volume_name')
        pvc_parent_path=$(echo "$pvc_entry" | jq -r '.pvc_parent_path')

        to_delete="$pvc_parent_path/${volume_name}"

        success=false
        attempt_count=0
        max_attempts=2

        while ! $success && [ $attempt_count -lt $max_attempts ]; do
            if output=$(zfs destroy "${to_delete}" 2>&1); then
                echo -e "${green}Destroyed ${blue}${to_delete}${reset}"
                update_json_file "$new_app_pvc_info" \
                                ".volume_name == \"$volume_name\"" \
                                ".destroyed = true"
                success=true
            else
                if echo "$output" | grep -q "dataset is busy" && [ $attempt_count -eq 0 ]; then
                    echo -e "${yellow}Dataset is busy, restarting middlewared and retrying...${green}"
                    systemctl restart middlewared
                    sleep 5
                    stop_app_if_needed "$appname"
                    sleep 5
                else
                    echo -e "${red}Error: Failed to destroy ${blue}${to_delete}${reset}"
                    echo -e "${red}Error message: ${reset}$output"
                    return 1
                fi
            fi
            attempt_count=$((attempt_count + 1))
        done
    done < <(jq -c '.[] | select(.destroyed == false and .ignored == false)' "$new_app_pvc_info")
    echo
    return 0
}

cleanup_datasets() {
    local base_path="${ix_apps_pool}/migration"
    local app_dataset="${migration_path}"

    if [ -z "$app_dataset" ]; then
        echo -e "${red}Error: No app dataset provided.${reset}"
        return 1
    fi

    # Remove the app dataset
    echo -e "${bold}Cleaning up app dataset...${reset}"
    if zfs destroy -r "${app_dataset}"; then
        echo -e "${green}Removed app dataset: ${blue}${app_dataset}${reset}"
    else
        echo -e "${red}Error: Failed to remove app dataset: ${blue}${app_dataset}${reset}"
        return 1
    fi
    echo

    # Check if the base path has any remaining child datasets
    if ! zfs list -H -d 1 -o name -t filesystem -r "$base_path" 2>/dev/null | grep -q -v "^${base_path}$"; then
        # Remove the base path dataset if it's empty
        echo -e "Removing base path dataset as it has no child datasets..."
        if zfs destroy "$base_path"; then
            echo -e "${green}Removed base path dataset: ${blue}${base_path}${reset}"
        else
            echo -e "${red}Error: Failed to remove base path dataset: ${blue}${base_path}${reset}"
            return 1
        fi
            echo
    fi
    return 0
}