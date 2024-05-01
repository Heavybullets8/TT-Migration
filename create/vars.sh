#!/bin/bash

update_or_append_variable() {
    local variable_name="$1"
    local value="$2"
    local file="/mnt/$migration_path/variables.txt"
    local log_path="/mnt/$migration_path"


    # Check if the value contains spaces or special characters that require quoting
    if [[ "$value" =~ [[:space:]] ]]; then
        value="\"$value\""
    fi

    if [ ! -f "$file" ]; then
        echo "${variable_name}=${value}" > "$file"
        return
    fi

    python create/create_marker.py check_integrity "$file" "$log_path"

    if grep -q "^${variable_name}=" "$file" 2>/dev/null; then
        # Using a different delimiter ('|') to avoid issues with paths that contain '/'
        sed -i "s|^${variable_name}=.*|${variable_name}=${value}|" "$file"
    else
        echo "${variable_name}=${value}" >> "$file"
    fi

    python create/create_marker.py log_update "$file" "$log_path" "$variable_name" "$value"
}


import_variables() {
    local file_path="/mnt/$migration_path/variables.txt"

    # Check if the file exists
    if [ -f "$file_path" ]; then
        # Source the file to import variables
        source "$file_path"
        echo "Migration variables imported from $file_path."
    else
        echo "Warning: No variables file found at $file_path."
    fi
}

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
    return 0
}
