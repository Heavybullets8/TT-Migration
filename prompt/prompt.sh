#!/bin/bash

prompt_app_name() {
    while true
    do
        # Prompt the user for the app name
        read -r -p "Enter the application name: " appname

        # Check if the appname fits within the regex
        if [[ "${appname}" =~ ^[a-zA-Z]([-a-zA-Z0-9]*[a-zA-Z0-9])?$ ]]; then
            # Convert the appname to lowercase
            appname_lowercase=$(echo "${appname}" | tr '[:upper:]' '[:lower:]')
            appname="${appname_lowercase}"
            namespace="ix-${appname}"

            # Check if the app exists
            if check_if_app_exists "${appname}"; then
                echo -e "${green}Found: ${blue}${appname}${reset}"
                echo
                break
            else
                echo -e "${yellow}Error: App not found.${reset}"
            fi
        else
            echo -e "${yellow}\"${appname}\" is not valid. Please enter a valid name.${reset}"
        fi
    done
}

prompt_create_backup() {
    echo "Please copy the app's config manually from the GUI:"
    echo "    Apps > Installed Applications > ${appname} > 3 dots on top right of app card > Edit"
    echo "I personally open two tabs, one tab with the old config open, and another tab with the new config open."
    echo "The next steps involve deleting the app, so please ensure you have screenshots or a tab open with the old config."
    while true; do
        read -n1 -s -rp "Press 'x' to continue..." key
        if [[ $key == "x" ]]; then
            echo -e "\nContinuing..."
            echo
            break
        else
            echo -e "${yellow}\nInvalid key. Please press 'x' to continue.${reset}"
        fi
    done
}

prompt_rename() {
    while true; do
        read -n1 -s -rp "Do you want to rename the app? [y/n] " key
        if [[ $key == "y" ]]; then
            echo
            rename_app
            rename=true
            break
        elif [[ $key == "n" || $key == "N" || $key == "" ]]; then
            echo
            break
        else
            echo -e "${yellow}\nInvalid key. Please press 'y' to rename the app or 'n' to skip.${reset}"
        fi
    done
    echo
}

rename_app() {
    while true; do
        # Prompt the user for the new app name
        read -r -p "Enter the new application name: " new_appname

        # Check if the new_appname fits within the regex
        if [[ "${new_appname}" =~ ^[a-zA-Z]([-a-zA-Z0-9]*[a-zA-Z0-9])?$ ]]; then
            # Convert the new_appname to lowercase
            new_appname_lowercase=$(echo "${new_appname}" | tr '[:upper:]' '[:lower:]')

            appname="${new_appname_lowercase}"
            namespace="ix-${appname}"
            break
        else
            echo -e "${yellow}\"${new_appname}\" is not valid. Please enter a valid name.${reset}"
        fi
    done
}

prompt_migration_path() {
    # Create a list of datasets within migration
    app_list=$(zfs list -H -o name -r "$ix_apps_pool/migration" | grep -E "$ix_apps_pool/migration/.*" | awk -F/ '{print $3}' | sort | uniq)

    # Check if there are any datasets and exit if there are none
    if [ -z "${app_list}" ]; then
        echo "No datasets found within migration."
        exit 1
    fi

    # Present the list of datasets to the user with number options
    echo "Select your original app name:"
    apps_array=()
    i=1
    for app in $app_list; do
        echo "${i}) ${app}"
        apps_array+=("${app}")
        i=$((i+1))
    done

    # Loop until the user makes a valid choice
    while true; do
        read -r -p "Enter the number associated with the app: " choice
        if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${#apps_array[@]}" ]; then
            migration_path="$ix_apps_pool/migration/${apps_array[$((choice-1))]}"
            echo "You have chosen ${migration_path}"
            break
        else
            echo "Invalid choice. Please enter a valid number."
        fi
    done
}