#!/bin/bash


rename_original_pvcs() {
    local pvc_backup_file="${backup_path}/pvcs_original.json"

    # Confirm the existence of the JSON file
    if [ ! -f "$pvc_backup_file" ]; then
        echo -e "${red}Error: Backup file does not exist at ${pvc_backup_file}${reset}"
        return 1
    fi

    echo -e "\n${bold}Renaming the app's PVCs...${reset}"

    # Read and process each entry from the JSON file
    local failures=0
    while read -r pvc_entry; do
        local pvc_name=$(echo "$pvc_entry" | jq -r '.pvc_name')
        local volume_name=$(echo "$pvc_entry" | jq -r '.pvc_volume_name')
        local pvc_parent_path=$(echo "$pvc_entry" | jq -r '.pvc_parent_path')
        local old_pvc_name="$pvc_parent_path/${volume_name}"
        local new_pvc_name="$migration_path/${pvc_name}"

        if zfs rename "${old_pvc_name}" "${new_pvc_name}"; then
            echo -e "${green}Renamed ${blue}${old_pvc_name}${reset} to ${blue}${new_pvc_name}${reset}"
            # Update the JSON file to set original_rename_complete to true for this PVC
            update_json_file "$pvc_backup_file" \
                            ".pvc_name == \"$pvc_name\"" \
                            ".original_rename_complete = true"
        else
            echo -e "${red}Error: Failed to rename ${old_pvc_name} to ${new_pvc_name}${reset}"
            ((failures++))
        fi
    done < <(jq -c '.[] | select(.original_rename_complete == false and .ignored == false)' "$pvc_backup_file")

    if [[ $failures -gt 0 ]]; then
        echo -e "${red}Some PVCs failed to rename. Check logs for details.${reset}"
        return 1
    fi
    return 0
}


swap_pvcs() {
    local original_app_pvc_info="${backup_path}/pvcs_original.json"
    local new_app_pvc_info="${backup_path}/pvcs_new.json"
    local original_pvc_count new_pvc_count

    echo -e "${bold}Renaming the migration PVCs to the new app's PVC names...${reset}"

    # Check if there are any PVCs left to process in the original app info
    original_pvc_count=$(jq '[.[] | select(.ignored == false)] | length' "$original_app_pvc_info")
    if [ "$original_pvc_count" -eq 0 ]; then
        echo -e "${yellow}Warning: There are no PVCs left to process in the original app info.${reset}"
        return 0
    fi

    # Check if the number of original PVCs matches the number of new PVCs
    new_pvc_count=$(jq '[.[] | select(.ignored == false)] | length' "$new_app_pvc_info")
    if [ "$original_pvc_count" -ne "$new_pvc_count" ]; then
        echo -e "${red}Error: The number of original PVCs does not match the number of new PVCs.${reset}"
        return 1
    fi


    match_pvcs_with_mountpoints "$original_app_pvc_info" "$new_app_pvc_info" || return 1
    original_pvc_count=$(jq '[.[] | select(.matched == false and .ignored == false)] | length' "$original_app_pvc_info")
    new_pvc_count=$(jq '[.[] | select(.matched == false and .ignored == false)] | length' "$new_app_pvc_info")

    if [ "$original_pvc_count" -eq 0 ]; then
        return 0
    fi

    # Match the remaining single PVC pair
    if [ "$original_pvc_count" -eq 1 ]; then
        match_remaining_single_pvc_pair "$original_app_pvc_info" "$new_app_pvc_info" || return 1
        return 0
    fi

    # Match the remaining PVCs based on their names
    match_remaining_pvcs_by_name "$original_app_pvc_info" "$new_app_pvc_info" || return 1

    return 0
}
