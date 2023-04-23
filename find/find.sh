#!/bin/bash

find_apps_pool() {
    echo "Finding apps pool..."
    ix_apps_pool=$(cli -c 'app kubernetes config' | 
                       grep -E "pool\s\|" | 
                       awk -F '|' '{print $3}' | 
                       sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Check if the apps pool exists
    if [ -z "${ix_apps_pool}" ]; then
        echo "Error: Apps pool not found."
        exit 1
    else
        echo "Found: ${ix_apps_pool}"
    fi
}