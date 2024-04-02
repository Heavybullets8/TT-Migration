#!/bin/bash


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