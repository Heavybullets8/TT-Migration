#!/bin/bash

update_json_file() {
    local file_path=$1        # Path to the JSON file
    local jq_filter=$2        # jq filter to select the right elements
    local jq_update=$3        # jq update expression
    local temp_json=$(mktemp)

    # Ensure the file exists
    if [ ! -f "$file_path" ]; then
        echo -e "${red}Error: JSON file does not exist at $file_path${reset}"
        return 1
    fi

    # Construct the full jq command from filter and update parameters
    local full_jq_command="map(if $jq_filter then $jq_update else . end)"

    # Read, filter, update, and write back to a temporary file
    if ! jq "$full_jq_command" "$file_path" > "$temp_json"; then 
        echo -e "${red}Failed to update JSON file at $file_path${reset}"
        rm "$temp_json"  # Clean up temporary file on failure
        return 1
    fi
    
    # Move the updated file back
    if ! mv "$temp_json" "$file_path"; then
        echo -e "${red}Failed to move updated JSON file back to original location: $file_path${reset}"
        return 1
    fi

    echo -e "${green}Successfully updated JSON file at $file_path${reset}"
    return 0
}

cleanup_datasets() {
    local base_path="${ix_apps_pool}/migration"
    local app_dataset="${migration_path}"

    # Remove the app dataset
    echo -e "${bold}Cleaning up app dataset...${reset}"
    if zfs destroy "${app_dataset}"; then
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