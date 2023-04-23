#!/bin/bash

find_apps_pool() {
    echo -e "${bold}Finding apps pool...${reset}"
    ix_apps_pool=$(cli -c 'app kubernetes config' | 
                       grep -E "pool\s\|" | 
                       awk -F '|' '{print $3}' | 
                       sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Check if the apps pool exists
    if [ -z "${ix_apps_pool}" ]; then
        return 1
    fi
    echo -e "${green}Found: ${blue}${ix_apps_pool}${reset}\n"
    return 0
}