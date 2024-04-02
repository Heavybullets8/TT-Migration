#!/bin/bash


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
            if output=$(zfs destroy "${to_delete}" 2>&1); then
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