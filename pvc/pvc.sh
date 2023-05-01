#!/bin/bash

get_pvc_info() {
    local pvc_data workloads_data pvc
    pvc_data=$(k3s kubectl get pvc -n "$namespace" -o json)
    workloads_data=$(k3s kubectl get deployments,statefulsets,daemonsets -n "$namespace" -o json)

    while IFS= read -r pvc; do
        pvc_name=$(echo "$pvc" | jq -r '.metadata.name')
        volume=$(echo "$pvc" | jq -r '.spec.volumeName')

        mount_path=$(echo "$workloads_data" | jq --arg pvc_name "$pvc_name" -r '.items[].spec.template.spec | .volumes[] as $volume | select($volume.persistentVolumeClaim.claimName == $pvc_name) | .containers[].volumeMounts[] | select(.name == $volume.name) | .mountPath')

        if [ "$mount_path" == "null" ]; then
            mount_path=""
        fi

        pvc_info+=("$pvc_name $volume $mount_path")
    done < <(echo "$pvc_data" | jq -c '.items[]')
}

rename_original_pvcs() {
    # Rename the app's PVCs
    echo -e "${bold}Renaming the app's PVCs...${reset}"
    mount_path_file="$migration_path/mount_paths.txt"
    true > "$mount_path_file"
    for line in "${pvc_info[@]}"; do
        pvc_name=$(echo "${line}" | awk '{print $1}')
        volume_name=$(echo "${line}" | awk '{print $2}')
        mount_path=$(echo "${line}" | awk '{print $3}')
        old_pvc_name="$pvc_parent_path/${volume_name}"
        new_pvc_name="$migration_path/${pvc_name}"
        if zfs rename "${old_pvc_name}" "${new_pvc_name}"; then 
            echo -e "${green}Renamed ${blue}${old_pvc_name}${reset} to ${blue}${new_pvc_name}${reset}"
            echo "$pvc_name $mount_path" >> "$mount_path_file"
        else
            echo -e "${red}Error: Failed to rename ${old_pvc_name} to ${new_pvc_name}${reset}"
            exit 1
        fi
    done
    echo
}

rename_migration_pvcs() {
    echo -e "${bold}Renaming the migration PVCs to the new app's PVC names...${reset}"

    # Create an array to store the migration PVCs
    migration_pvcs=()

    # Get the list of migration PVCs
    migration_pvcs_info=$(zfs list -r "$migration_path" | grep -v "${migration_path}$" | awk 'NR>1 {print $1}')

    # Read the migration_pvcs_info line by line and store the migration PVCs in the migration_pvcs array
    while read -r line; do
        pvc_name=$(basename "${line}")
        migration_pvcs+=("${pvc_name}")
    done < <(echo "${migration_pvcs_info}")

    if [ ${#migration_pvcs[@]} -eq 0 ]; then
        echo "Error: No migration PVCs found."
        exit 1
    fi

    # Create an associative array to store the new PVCs and their mount paths
    declare -A new_pvcs_mount_paths
    for line in "${pvc_info[@]}"; do
        pvc_name=$(echo "${line}" | awk '{print $1}')
        mount_path=$(echo "${line}" | awk '{print $3}')
        new_pvcs_mount_paths["$pvc_name"]="$mount_path"
    done

    # Match PVCs with the same mount points
    match_pvcs_with_mountpoints

    # Match the remaining single PVC pair
    if [ ${#migration_pvcs[@]} -eq 1 ] && [ ${#new_pvcs_mount_paths[@]} -eq 1 ]; then
        match_remaining_single_pvc_pair
        return
    fi

    # Match the remaining PVCs based on their names
    match_remaining_pvcs_by_name

    echo
}

match_pvcs_with_mountpoints() {
    for original_pvc in "${migration_pvcs[@]}"; do
        for new_pvc in "${!new_pvcs_mount_paths[@]}"; do
            if [ "${new_pvcs_mount_paths[$new_pvc]}" == "$migration_path/$original_pvc" ]; then
                if zfs rename "$migration_path/${original_pvc}" "$pvc_parent_path/${new_pvc}"; then
                    echo -e "${green}Renamed ${blue}$migration_path/${original_pvc}${reset} to ${blue}$pvc_parent_path/${new_pvc}${reset} (matched by mount point)"
                else
                    echo -e "${red}Error: Failed to rename ${blue}$migration_path/${original_pvc}${reset} to ${blue}$pvc_parent_path/${new_pvc}${reset}"
                    exit 1
                fi
                # Remove the matched PVCs from the arrays
                migration_pvcs=("${migration_pvcs[@]/$original_pvc}")
                unset "new_pvcs_mount_paths[$new_pvc]"
                break
            fi
        done
    done
}

match_remaining_single_pvc_pair() {
    if [ ${#migration_pvcs[@]} -eq 1 ] && [ ${#new_pvcs_mount_paths[@]} -eq 1 ]; then
        original_pvc="${migration_pvcs[0]}"
        new_pvc="${!new_pvcs_mount_paths[@]}"
        if zfs rename "$migration_path/${original_pvc}" "$pvc_parent_path/${new_pvc}"; then
            echo -e "${green}Renamed ${blue}$migration_path/${original_pvc}${reset} to ${blue}$pvc_parent_path/${new_pvc}${reset} (single pair left)"
        else
            echo -e "${red}Error: Failed to rename ${blue}$migration_path/${original_pvc}${reset} to ${blue}$pvc_parent_path/${new_pvc}${reset}"
            exit 1
        fi
    fi
}

match_remaining_pvcs_by_name() {
    for original_pvc in "${migration_pvcs[@]}"; do
        most_similar_pvc=$(find_most_similar_pvc "$original_pvc")
        if zfs rename "$migration_path/${original_pvc}" "$pvc_parent_path/${most_similar_pvc}"; then
            echo -e "${green}Renamed ${blue}$migration_path/${original_pvc}${reset} to ${blue}$pvc_parent_path/${most_similar_pvc}${reset} (matched by name similarity)"
        else
            echo -e "${red}Error: Failed to rename ${blue}$migration_path/${original_pvc}${reset} to ${blue}$pvc_parent_path/${most_similar_pvc}${reset}"
            exit 1
        fi
    done
}

destroy_new_apps_pvcs() {
    echo -e "${bold}Destroying the new app's PVCs...${reset}"

    # Create an array to store the new PVCs
    new_pvcs=()
    
    # Read the PVC info from the pvc_info array and store the new PVCs in the new_pvcs array
    for line in "${pvc_info[@]}"; do
        pvc_and_volume=$(echo "${line}" | awk '{print $1 "," $2}')
        new_pvcs+=("${pvc_and_volume}")
    done

    if [ ${#new_pvcs[@]} -eq 0 ]; then
        echo -e "${red}Error: No new PVCs found.${reset}"
        exit 1
    fi

    for new_pvc in "${new_pvcs[@]}"; do
        IFS=',' read -ra pvc_and_volume_arr <<< "$new_pvc"
        volume_name="${pvc_and_volume_arr[1]}"
        to_delete="$pvc_parent_path/${volume_name}"

        success=false
        attempt_count=0
        max_attempts=2

        while ! $success && [ $attempt_count -lt $max_attempts ]; do
            if output=$(zfs destroy "${to_delete}"); then
                echo -e "${green}Destroyed ${blue}${to_delete}${reset}"
                success=true
            else
                if echo "$output" | grep -q "dataset is busy" && [ $attempt_count -eq 0 ]; then
                    echo -e "${yellow}Dataset is busy, restarting middlewared and retrying...${green}"
                    systemctl restart middlewared
                    sleep 5
                    stop_app_if_needed "$appname"
                    sleep 5
                else
                    echo "${red}Error: Failed to destroy ${blue}${to_delete}${reset}"
                    echo "${red}Error message: ${reset}$output"
                    exit 1
                fi
            fi
            attempt_count=$((attempt_count + 1))
        done
    done
    echo
}

get_pvc_parent_path() {
    local volume_name
    volume_name=$(echo "$pvc_info" | awk '{print $2}' | head -n 1)

    pvc_path=$(zfs list -r "${ix_apps_pool}/ix-applications" -o name -H | grep "${volume_name}")

    if [ -z "${pvc_path}" ]; then
        echo -e "${red}PVC not found${reset}"
        exit 1
    fi

    pvc_parent_path=$(dirname "${pvc_path}")
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
        dist=$(python pvc/levenshtein.py "$source_pvc" "$target_pvc_name")
        local similarity=$(( 100 * ( maxlen - dist ) / maxlen ))

        if [ "$similarity" -gt "$max_similarity" ]; then
            max_similarity=$similarity
            most_similar_pvc=$target_pvc_name
            most_similar_volume=$target_volume_name
        fi
    done
    echo "$most_similar_volume"
}

remove_migration_app_dataset() {
    echo -e "${bold}Removing the migration app dataset...${reset}"
    if zfs destroy -r "$migration_path"; then
        echo -e "${green}Removed ${blue}$migration_path${reset}"
        echo
    else
        echo "${red}Error: Failed to remove ${blue}$migration_path${reset}"
        exit 1
    fi
}