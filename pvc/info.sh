#!/bin/bash

get_pvc_info() {
    local version=$1
    local pvc_backup_file="${backup_path}/pvcs_${version}.json"
    local pvc_data workloads_data pvc_name volume mount_path pvc_parent_path

    # Ensure backup directory exists
    mkdir -p "$backup_path" || return 1
    touch "$pvc_backup_file" || return 1

    # Fetch all PVCs and workload data in JSON format
    if ! pvc_data=$(k3s kubectl get pvc -n "$namespace" -o json); then
        echo -e "${red}Error: Failed to fetch PVCs.${reset}"
        return 1
    fi

    if ! workloads_data=$(k3s kubectl get deployments,statefulsets,daemonsets -n "$namespace" -o json); then
        echo -e "${red}Error: Failed to fetch workloads.${reset}"
        return 1
    fi

    echo '[' > "$pvc_backup_file" || return 1

    local first_entry=true
    while IFS= read -r pvc; do
        pvc_name=$(echo "$pvc" | jq -r '.metadata.name // empty')
        volume=$(echo "$pvc" | jq -r '.spec.volumeName // empty')
        mount_path=$(echo "$workloads_data" | jq --arg pvc_name "$pvc_name" -r '.items[].spec.template.spec | .volumes[] as $volume | select($volume.persistentVolumeClaim.claimName == $pvc_name) | .containers[].volumeMounts[] | select(.name == $volume.name) | .mountPath // empty' | head -n 1)
        pvc_parent_path=$(k3s kubectl describe pv "$volume" | grep "poolname=" | awk -F '=' '{print $2}')

        # Validate required fields
        if ! echo "$pvc_name" | grep -qE -- '-cnpg-|-redis-0'; then
            if [ -z "$pvc_name" ] || [ -z "$volume" ] || [ -z "$mount_path" ] || [ -z "$pvc_parent_path" ]; then
                echo -e "${red}Error: Required field is missing or empty. PVC: \"${pvc_name:-"EMPTY"}\", Volume: \"${volume:-"EMPTY"}\", Mount Path: \"${mount_path:-"EMPTY"}\", Parent Path: \"${parent_path:-"EMPTY"}\"${reset}"
                rm -f "$pvc_backup_file"
                return 1
            fi
        fi

        # Format entry as JSON object and append to file, handling commas for valid JSON
        if [ "$first_entry" = true ]; then
            first_entry=false
        else
            echo ',' >> "$pvc_backup_file" || return 1
        fi

        jq -n \
        --arg pvc_name "$pvc_name" \
        --arg volume "$volume" \
        --arg mount_path "$mount_path" \
        --arg pvc_parent_path "$pvc_parent_path" \
        '{ 
            pvc_name: $pvc_name, 
            pvc_volume_name: $volume, 
            mount_path: $mount_path, 
            pvc_parent_path: $pvc_parent_path, 
            original_rename_complete: false, 
            matched: false,
            destroyed: false,
            ignored: false
        }' >> "$pvc_backup_file" || return 1

    done < <(echo "$pvc_data" | jq -c '.items[]')

    echo ']' >> "$pvc_backup_file" || return 1
}


update_pvc_migration_status() {
    local pvc_backup_file="${backup_path}/pvcs_original.json"

    # Calculate the number of original PVCs
    original_pvs_count=$(jq '[.[] | select(.ignored == false)] | length' "$pvc_backup_file")
    
    # Determine if migration should occur based on count
    if [ "$original_pvs_count" -eq 0 ]; then
        migrate_pvs=false
    else
        migrate_pvs=true
    fi
}


verify_matching_num_pvcs() {    
    local original_app_pvc_info="${backup_path}/pvcs_original.json"
    local new_app_pvc_info="${backup_path}/pvcs_new.json"
    local original_pvc_count new_pvc_count

    original_pvc_count=$(jq '[.[] | select(.ignored == false)] | length' "$original_app_pvc_info")
    new_pvc_count=$(jq '[.[] | select(.ignored == false)] | length' "$new_app_pvc_info")

    if [[ "$original_pvc_count" -gt "$new_pvc_count" ]]; then
        local difference=$((original_pvc_count - new_pvc_count))

        echo -e "${red}Error: The number of original PVCs is greater than the number of new PVCs.${reset}"
        echo -e "${red}Original PVC Count: ${original_pvc_count}${reset}"
        echo -e "${red}New PVC Count: ${new_pvc_count}${reset}"
        echo -e "Restoring now would result in possible data loss, depending on what PV's are unable to be matched."
        echo -e "Here are the contents of the two JSON files which include the data for the original and new PVCs respectively:"

        echo -e "\n${blue}ORIGINAL PVC INFO:${reset}"
        cat "$original_app_pvc_info"
        echo -e "\n${blue}NEW PVC INFO:${reset}"
        cat "$new_app_pvc_info"

        echo -e "\nThere is a difference of ${red}${difference}${reset} PVC(s) between the two JSON files."
        echo -e "Meaning you need to set the ${blue}ignored${reset} field to ${blue}true${reset} for ${red}${difference}${reset} PVC(s) in the original PVC info file."
        echo -e "Take a look at the mount paths and names for each of the PVCs, and whichever one you cannot find a match for, set the ${blue}ignored${reset} field to true for that PVC in the original PVC info file."
        echo -e "Please reach out to support if you have any concerns or questions regarding this process."
        echo -e "Original PVC File Path: ${blue}$original_app_pvc_info${reset}"
        echo -e "Once you have done that, run the script again with ${blue}--skip${reset}"
        return 1
    fi

    return 0
}