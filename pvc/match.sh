#!/bin/bash


match_pvcs_with_mountpoints() {
    for original_pvc_line in "${original_pvc_info[@]}"; do
        original_pvc_name=$(echo "${original_pvc_line}" | awk '{print $1}')
        original_mountpath=$(echo "${original_pvc_line}" | awk '{print $3}')

        # Occassionally the mount path is empty, in which case we skip matching by mount point
        # Which will result in matching by name similarity
        if [ -z "$original_mountpath" ]; then
            continue
        fi

        for index in "${!pvc_info[@]}"; do
            new_pvc_info="${pvc_info[index]}"
            new_pvc_name=$(echo "${new_pvc_info}" | awk '{print $1}')
            new_mountpath=$(echo "${new_pvc_info}" | awk '{print $3}')

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
                    return 1
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
    return 0
}

# Matches PVC names by name similarity, such as "pgadmin-config" == "pgadmin-config"
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
            return 1
        fi
    fi
    return 0
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
            return 1
        fi
    done
    return 0
}