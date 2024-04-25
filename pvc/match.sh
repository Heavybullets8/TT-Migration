#!/bin/bash


match_pvcs_with_mountpoints() {
    local original_pvc_info_file="$1"
    local new_pvc_info_file="$2"
    local original_pvc_name original_mountpath new_pvc_name new_mountpath new_volume migration_path
    local new_pvc_parent_path new_volume 
    local failed=0

    # Fetch all PVCs from both files that have not been renamed yet
    original_pvcs=$(jq -c '.[] | select(.matched == false)' "$original_pvc_info_file")
    new_pvcs=$(jq -c '.[] | select(.matched == false)' "$new_pvc_info_file")

    # Iterate over each original PVC and attempt to match with new PVCs based on mount points
    while read -r original_pvc; do
        original_pvc_name=$(echo "$original_pvc" | jq -r '.pvc_name')
        original_mountpath=$(echo "$original_pvc" | jq -r '.mount_path')

        # Skip if the mount path is empty
        if [ -z "$original_mountpath" ]; then
            continue
        fi

        while read -r new_pvc; do
            new_pvc_name=$(echo "$new_pvc" | jq -r '.pvc_name')
            new_mountpath=$(echo "$new_pvc" | jq -r '.mount_path')
            new_volume=$(echo "$new_pvc" | jq -r '.pvc_volume_name')
            new_pvc_parent_path=$(echo "$new_pvc" | jq -r '.pvc_parent_path')


            if [ "$new_mountpath" == "$original_mountpath" ]; then
                if zfs rename "$migration_path/${original_pvc_name}" "$new_pvc_parent_path/${new_volume}"; then
                    echo -e "${green}Renamed ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$new_pvc_parent_path/${new_volume}${reset}"
                    echo -e "${green}Matched by mount point:${green}"
                    echo -e "${blue}${original_pvc_name}${reset} -> ${blue}${new_pvc_name}${reset}"
                    echo -e "${blue}${original_mountpath}${reset} = ${blue}${new_mountpath}${reset}"
                    echo

                    # Update the original PVC to mark it as completed
                    update_json_file "$original_pvc_info_file" \
                                     ".pvc_name == \"$original_pvc_name\"" \
                                     ".matched = true"

                    # Update the new PVC to mark it as completed
                    update_json_file "$new_pvc_info_file" \
                                     ".pvc_name == \"$new_pvc_name\"" \
                                     ".matched = true"
                    # Break out of the inner loop as we found a match
                    break
                else
                    echo -e "${red}Error: Failed to rename ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$new_pvc_parent_path/${new_volume}${reset}"
                    failed=1
                fi
            fi
        done  < <(echo "$new_pvcs")
    done < <(echo "$original_pvcs")

    return $failed
}


match_remaining_single_pvc_pair() {
    local original_app_pvc_info="$1"
    local new_app_pvc_info="$2"

    # Fetch the remaining unmatched PVC from each file
    local original_pvc=$(jq -c '.[] | select(.matched == false)' "$original_app_pvc_info")
    local new_pvc=$(jq -c '.[] | select(.matched == false)' "$new_app_pvc_info")

    local original_pvc_name=$(echo "$original_pvc" | jq -r '.pvc_name')
    local new_pvc_name=$(echo "$new_pvc" | jq -r '.pvc_name')
    local new_volume=$(echo "$new_pvc" | jq -r '.pvc_volume_name')
    local new_pvc_parent_path=$(echo "$new_pvc" | jq -r '.pvc_parent_path')

    if zfs rename "$migration_path/${original_pvc_name}" "$new_pvc_parent_path/${new_volume}"; then
        echo -e "${green}Renamed ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$new_pvc_parent_path/${new_volume}${reset}"
        echo -e "${green}Single pair left:${green}"
        echo -e "${blue}${original_pvc_name}${reset} -> ${blue}${new_pvc_name}${reset}"
        echo

        # Update the JSON file to mark the original and new PVCs as completed
        update_json_file "$original_app_pvc_info" \
                         ".pvc_name == \"$original_pvc_name\"" \
                         ".matched = true"

        update_json_file "$new_app_pvc_info" \
                         ".pvc_name == \"$new_pvc_name\"" \
                         ".matched = true"

    else
        echo -e "${red}Error: Failed to rename ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$new_pvc_parent_path/${new_volume}${reset}"
        return 1
    fi

    return 0
}


# Matches PVC names by name similarity, such as "pgadmin-config" == "pgadmin-config"
find_most_similar_pvc() {
    local source_pvc_name=$1
    local new_pvcs=$2  # Pass new PVCs as a string of JSON objects

    local max_similarity=0
    local most_similar_pvc=""
    local most_similar_volume=""

    while IFS= read -r target_pvc; do
        target_pvc_name=$(echo "$target_pvc" | jq -r '.pvc_name')
        target_volume_name=$(echo "$target_pvc" | jq -r '.pvc_volume_name')

        local len1=${#source_pvc_name}
        local len2=${#target_pvc_name}
        local maxlen=$(( len1 > len2 ? len1 : len2 ))
        dist=$(python pvc/levenshtein.py "$source_pvc_name" "$target_pvc_name")
        local similarity=$(( 100 * ( maxlen - dist ) / maxlen ))

        if [ "$similarity" -gt "$max_similarity" ]; then
            max_similarity=$similarity
            most_similar_pvc=$target_pvc_name
            most_similar_volume=$target_volume_name
        fi
    done < <(echo "$new_pvcs")

    # Output both the most similar volume and PVC name
    echo "$most_similar_volume $most_similar_pvc"
}


match_remaining_pvcs_by_name() {
    local original_app_pvc_info="$1"
    local new_app_pvc_info="$2"

    # Fetch the remaining unmatched PVCs from each file
    local original_pvcs=$(jq -c '.[] | select(.matched == false)' "$original_app_pvc_info")
    local new_pvcs=$(jq -c '.[] | select(.matched == false)' "$new_app_pvc_info")

    echo "$original_pvcs" | while IFS= read -r original_pvc; do
        local original_pvc_name=$(echo "$original_pvc" | jq -r '.pvc_name')
        
        # Call to find the most similar PVC and volume name from the new PVCs
        read -r most_similar_volume most_similar_pvc <<< "$(find_most_similar_pvc "$original_pvc_name" "$new_pvcs")"
        
        if [ -z "$most_similar_volume" ]; then
            echo -e "${yellow}No similar PVC found for ${blue}$original_pvc_name${reset}"
            continue
        fi

        new_pvc_parent_path=$(jq -r --arg vol "$most_similar_volume" '.[] | select(.pvc_volume_name == $vol) | .pvc_parent_path' "$new_app_pvc_info")

        if zfs rename "$migration_path/${original_pvc_name}" "$new_pvc_parent_path/${most_similar_volume}"; then
            echo -e "${green}Renamed ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$new_pvc_parent_path/${most_similar_volume}${reset}"
            echo -e "${green}Matched by name similarity: ${blue}${original_pvc_name}${reset} -> ${blue}${most_similar_pvc}${reset}"
            echo

            # Update the JSON file to mark the original and new PVCs as completed
            update_json_file "$original_app_pvc_info" \
                             ".pvc_name == \"$original_pvc_name\"" \
                             ".matched = true"

            update_json_file "$new_app_pvc_info" \
                             ".pvc_name == \"$most_similar_pvc\"" \
                             ".matched = true"

        else
            echo -e "${red}Error: Failed to rename ${blue}$migration_path/${original_pvc_name}${reset} to ${blue}$new_pvc_parent_path/${most_similar_volume}${reset}"
            return 1
        fi
    done

    return 0
}