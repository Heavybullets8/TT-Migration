#!/bin/bash

find_apps_pool() {
    echo -e "${bold}Finding apps pool...${reset}"
    ix_apps_pool=$(cli -c 'app kubernetes config' | 
                       grep -E "pool\s\|" | 
                       awk -F '|' '{print $3}' | 
                       sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Check if the apps pool exists
    if [ -z "${ix_apps_pool}" ]; then
        echo -e "${red}No apps pool found!${reset}"
        return 1
    fi
    echo -e "${green}Found: ${blue}${ix_apps_pool}${reset}\n"
    return 0
}

find_latest_heavy_script_dir() {
    # Define an array to hold potential home directories
    homes=("$HOME" "$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)")

    # Use associative array to track directories and their modification times
    declare -A script_paths

    # Check each home directory heavy_script directory
    for home in "${homes[@]}"; do
        script_dir="$home/heavy_script"
        if [[ -d "$script_dir" ]]; then
            # Get last modification time of the directory
            mod_time=$(stat -c "%Y" "$script_dir")
            script_paths["$mod_time"]="$script_dir"
        fi
    done

    # Print latest version if multiple versions exist
    if [[ ${#script_paths[@]} -gt 0 ]]; then
        latest=$(printf "%s\n" "${!script_paths[@]}" | sort -nr | head -n1)
        echo "${script_paths[$latest]}"
    else
        # Print an error message to stderr and exit with a non-zero status code
        echo ""
    fi
}

