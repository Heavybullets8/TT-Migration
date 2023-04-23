#!/bin/bash

stop_app_if_needed() {
    # Stop application if not stopped
    status=$(cli -m csv -c 'app chart_release query name,status' | 
                grep "^$appname," | 
                awk -F ',' '{print $2}'| 
                sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [[ "$status" != "STOPPED" ]]; then
        echo -e "\nStopping ${blue}$appname${reset}"
        stop_app "$appname"
        result=$(handle_stop_code "$?")
        if [[ $? -eq 1 ]]; then
            echo -e "${red}${result}${reset}"
            exit 1
        else
            echo -e "${green}${result}${reset}"
        fi
    fi
    echo
}

delete_original_app() {
    echo -e "${bold}Deleting the original app...${reset}"
    if cli -c "app chart_release delete release_name=\"${appname}\""; then
        echo -e "${green}Success${reset}"
        echo
    else
        echo -e "${red}Error: Failed to delete the old version of the app.${reset}"
        exit 1
    fi
}