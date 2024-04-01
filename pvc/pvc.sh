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

check_pvc_info_empty() {
    if [ ${#pvc_info[@]} -eq 0 ]; then
        echo -e "${red}Error: pvc_info is empty. No PVCs found in the namespace.${reset}"
        exit 1
    fi
}

rename_original_pvcs() {
    # Rename the app's PVCs
    echo -e "\n${bold}Renaming the app's PVCs...${reset}"
    mount_path_file="/mnt/$migration_path/mount_paths.txt"
    true > "$mount_path_file"
    for line in "${pvc_info[@]}"; do
        pvc_name=$(echo "${line}" | awk '{print $1}')
        volume_name=$(echo "${line}" | awk '{print $2}')
        mount_path=$(echo "${line}" | awk '{print $3}')
        old_pvc_name="$pvc_parent_path/${volume_name}"
        new_pvc_name="$migration_path/${pvc_name}"
        if zfs rename "${old_pvc_name}" "${new_pvc_name}"; then 
            echo -e "${green}Renamed ${blue}${old_pvc_name}${reset} to ${blue}${new_pvc_name}${reset}"
            echo "$pvc_name $volume_name $mount_path" >> "$mount_path_file"
        else
            echo -e "${red}Error: Failed to rename ${old_pvc_name} to ${new_pvc_name}${reset}"
            exit 1
        fi
    done
    echo
}

rename_migration_pvcs() {
    echo -e "${bold}Renaming the migration PVCs to the new app's PVC names...${reset}"

    # Create an array to store the original PVC info
    original_pvc_info=()

    # Read the mount_paths.txt file and store the original PVC info in the original_pvc_info array
    while IFS= read -r line; do
        original_pvc_info+=("${line}")
    done < "/mnt/$migration_path/mount_paths.txt"

    if [ ${#original_pvc_info[@]} -eq 0 ]; then
        echo -e "${red}Error: No original PVCs found.${reset}"
        exit 1
    fi

    # Check if the number of original PVCs matches the number of new PVCs
    if [ ${#original_pvc_info[@]} -ne ${#pvc_info[@]} ]; then
        echo -e "${red}Error: The number of original PVCs does not match the number of new PVCs.${reset}"
        exit 1
    fi

    # Match PVCs with the same mount points
    match_pvcs_with_mountpoints

    if [ ${#pvc_info[@]} -eq 0 ]; then
        echo
        return
    fi

    # Match the remaining single PVC pair
    if [ ${#original_pvc_info[@]} -eq 1 ] && [ ${#pvc_info[@]} -eq 1 ]; then
        match_remaining_single_pvc_pair
        return
    fi

    # Match the remaining PVCs based on their names
    match_remaining_pvcs_by_name

    echo
}

match_pvcs_with_mountpoints() {
    for original_pvc_line in "${original_pvc_info[@]}"; do
        original_pvc_name=$(echo "${original_pvc_line}" | awk '{print $1}')
        original_mountpath=$(echo "${original_pvc_line}" | awk '{print $3}')

        for index in "${!pvc_info[@]}"; do
            new_pvc_info="${pvc_info[index]}"
            new_pvc_name=$(echo "${new_pvc_info}" | awk '{print $1}')
            new_mountpath=$(echo "${new_pvc_info}" | awk '{print $3}')

            # do not match if the mount point is empty
            if [ -z "$original_mountpath" ] || [ -z "$new_mountpath" ]; then
                continue
            fi
            
            if [ "$new_mountpath" == "$original_mountpath" ]; then
                new_volume=$(echo "${new_pvc_info}" | awk '{print $2}')
                if zfs rename "$migration_path/${original_pvc_name}" "$pvc_parent_path/${new_volume}"; then
                    echo -e "${green}Renamed ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$pvc_parent_path/${new_volume}${reset}"
                    echo -e "${green}Matched by mount point:${green}"
                    echo -e "${blue}${original_pvc_name}${reset} -> ${blue}${new_pvc_name}${reset}"
                    echo -e "${blue}${original_mountpath}${reset} = ${blue}${new_mountpath}${reset}"
                    echo
                else
                    echo -e "${red}Error: Failed to rename ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$pvc_parent_path/${new_volume}${reset}"
                    exit 1
                fi
                # Remove the matched PVCs from the arrays
                unset "original_pvc_info[index]"
                unset "pvc_info[index]"
                break
            fi
        done
    done

    # Rebuild the arrays
    original_pvc_info=("${original_pvc_info[@]}")
    pvc_info=("${pvc_info[@]}")
}

match_remaining_single_pvc_pair() {
    if [ ${#original_pvc_info[@]} -eq 1 ] && [ ${#pvc_info[@]} -eq 1 ]; then
        original_pvc_name=$(echo "${original_pvc_info[0]}" | awk '{print $1}')
        new_pvc_info="${pvc_info[0]}"
        new_pvc_name=$(echo "${new_pvc_info}" | awk '{print $1}')
        new_volume=$(echo "${new_pvc_info}" | awk '{print $2}')
        if zfs rename "$migration_path/${original_pvc_name}" "$pvc_parent_path/${new_volume}"; then
            echo -e "${green}Renamed ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$pvc_parent_path/${new_volume}${reset}"
            echo -e "${green}Single pair left:${green}"
            echo -e "${blue}${original_pvc_name}${reset} -> ${blue}${new_pvc_name}${reset}"
            echo
        else
            echo -e "${red}Error: Failed to rename ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$pvc_parent_path/${new_volume}${reset}"
            exit 1
        fi
    fi
}

match_remaining_pvcs_by_name() {
    for original_pvc_line in "${original_pvc_info[@]}"; do
        original_pvc_name=$(echo "${original_pvc_line}" | awk '{print $1}')
        most_similar_volume=$(find_most_similar_pvc "$original_pvc_name")
        if zfs rename "$migration_path/${original_pvc_name}" "$pvc_parent_path/${most_similar_volume}"; then
            echo -e "${green}Renamed ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$pvc_parent_path/${most_similar_volume}${reset}"
            echo -e "${green}Matched by name similarity${reset}"
            echo
        else
            echo -e "${red}Error: Failed to rename ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$pvc_parent_path/${most_similar_volume}${reset}"
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
                    echo -e "${red}Error: Failed to destroy ${blue}${to_delete}${reset}"
                    echo -e "${red}Error message: ${reset}$output"
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

    pvc_path=$(k3s kubectl describe pv "$volume_name" | grep "poolname=" | awk -F '=' '{print $2}')


    if [ -z "${pvc_path}" ]; then
        echo -e "${red}PVC not found${reset}"
        exit 1
    fi

    pvc_parent_path="$pvc_path"
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

cleanup_datasets() {
    local base_path="${ix_apps_pool}/migration"
    local child_dataset datasets_to_remove base_name

    base_name="$base_path"

    # List child datasets
    while IFS= read -r child_dataset; do
        # Check if a child dataset has grandchild datasets
        if ! zfs list -H -d 1 -o name -t filesystem -r "$child_dataset" 2>/dev/null | grep -q -v "^${child_dataset}$"; then
            datasets_to_remove+=("$child_dataset")
        fi
    done < <(zfs list -H -d 1 -o name -t filesystem -r "$base_path" 2>/dev/null | grep -v "^${base_name}$")

    # Remove child datasets without grandchild datasets
    if [ ${#datasets_to_remove[@]} -gt 0 ]; then
        echo -e "${bold}Cleaning up...${reset}"
        for dataset in "${datasets_to_remove[@]}"; do
            if zfs destroy "$dataset"; then
                echo -e "${green}Removed empty dataset: ${blue}$dataset${reset}"
            else
                echo -e "${red}Error: Failed to remove empty dataset: ${blue}$dataset${reset}"
            fi
        done
        echo
    fi

    # Remove base_path dataset if it has no child datasets
    if ! zfs list -H -d 1 -o name -t filesystem -r "$base_path" 2>/dev/null | grep -q -v "^${base_name}$"; then
        echo -e "Removing base path dataset as it has no child datasets..."
        if zfs destroy -r "$base_path"; then
            echo -e "${green}Removed base path dataset: ${blue}$base_path${reset}"
        else
            echo -e "${red}Error: Failed to remove base path dataset: ${blue}$base_path${reset}"
        fi
        echo
    fi
}