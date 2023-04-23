#!/bin/bash


create_migration_dataset() {
    local path=${ix_apps_pool}/migration

    # Check if the migration dataset exists, and create it if it doesn't
    if ! zfs list "${ix_apps_pool}/migration" >/dev/null 2>&1; then
        echo -e "${bold}Creating migration dataset...${reset}"
        if zfs create "${ix_apps_pool}/migration"; then
            echo -e "${green}Dataset created: ${blue}${ix_apps_pool}/migration${reset}"
            echo
        else
            echo -e "${red}Error: Failed to create migration dataset.${reset}"
            exit 1
        fi
    fi
}

create_app_dataset() {
    local path=${ix_apps_pool}/migration/${appname}
    export migration_path

    # Check if the app dataset exists, and create it if it doesn't
    if ! zfs list "$path" >/dev/null 2>&1; then
        echo -e "${bold}Creating app dataset...${reset}"
        if zfs create "$path"; then
            migration_path=$path
            echo -e "${green}Dataset created: ${blue}$path${reset}"
            echo
        else
            echo "${red}Error: Failed to create app dataset.${reset}"
            exit 1
        fi
    fi
}