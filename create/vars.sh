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
