#!/bin/bash

update_or_append_variable() {
    local variable_name="$1"
    local value="$2"
    local file="/mnt/$migration_path/variables.txt"

    # Check if the value contains spaces or special characters that require quoting
    if [[ "$value" =~ [[:space:]] ]]; then
        value="\"$value\""
    fi

    if [ ! -f "$file" ]; then
        echo "${variable_name}=${value}" > "$file"
        return
    fi

    if grep -q "^${variable_name}=" "$file" 2>/dev/null; then
        # Using a different delimiter ('|') to avoid issues with paths that contain '/'
        sed -i "s|^${variable_name}=.*|${variable_name}=${value}|" "$file"
    else
        echo "${variable_name}=${value}" >> "$file"
    fi
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
    local temp_json="$(mktemp)"

    # Ensure the file exists
    if [ ! -f "$file_path" ]; then
        echo -e "${red}Error: JSON file does not exist at $file_path${reset}"
        return 1
    fi

    # Read, filter, update, and write back to a temporary file
    if ! jq "$jq_filter | $jq_update" "$file_path" > "$temp_json" ;then 
        echo -e "${red}Failed to update JSON file at $file_path${reset}"
        return 1
    fi
    
    if mv "$temp_json" "$file_path"; then
        echo -e "${red}Failed to update JSON file at $file_path${reset}"
        return 1
    fi

    echo -e "${green}Successfully updated JSON file at $file_path${reset}"
    return 0
}
