#!/bin/bash

auto_update_script() {
    git -C "$script_path" config pull.rebase true
    git -C "$script_path" fetch > /dev/null 2>&1

    if ! git -C "$script_path" diff --quiet origin/"$current_version"; then
        echo -e "${yellow}Updating the script to the latest version...${reset}"
        
        if git -C "$script_path" pull > /dev/null 2>&1; then
            echo -e "${green}Script updated successfully! Rerunning the script with the update.${reset}"
            exec bash "$script_path/$script_name" "${args[@]}"
        else
            echo -e "${red}Error: Failed to update the script. Please check your repository or try again later.${reset}"
        fi
        echo
    fi
}