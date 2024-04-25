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

            # Check if the app is already in the migration pool
            if zfs list "${ix_apps_pool}/migration/${appname}" &> /dev/null; then
                echo -e "${red}Error: ${blue}${appname}${red} is already in the migration pool: ${ix_apps_pool}/migration/${appname}${reset}"
                echo -e "\nIf the application has failed, and you want to complete from a previous step:"
                echo -e "     use the ${blue}--skip${reset} flag and select ${blue}${appname}${reset}"
                echo -e "\nIf its an old migration, you can remove the dataset with:"
                echo -e "     ${blue}zfs destroy -r \"${ix_apps_pool}/migration/${appname}\"${reset}"
                echo -e "Please only do this if you are certain the application migration dataset listed is not from a recently failed migration.${reset}"
                return 1
            fi

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

prompt_continue_for_db() {
    while true; do
        read -n1 -s -rp "Would you like the script to attempt the restore? [y/n] " key
        if [[ $key == "y" ]]; then
            echo
            echo -e "${green}Attempting a restore...${reset}\n"
            break
        elif [[ $key == "n" || $key == "N" || $key == "" ]]; then
            echo
            return 1
        else
            echo -e "${yellow}\nInvalid key. Please press 'y' to rename the app or 'n' to skip.${reset}"
        fi
    done
    echo
}

prompt_continue() {
    while true; do
        read -n1 -s -rp "Would you like to continue? [y/n] " key
        if [[ $key == "y" ]]; then
            echo
            break
        elif [[ $key == "n" || $key == "N" || $key == "" ]]; then
            echo
            return 1
        else
            echo -e "${yellow}\nInvalid key. Please press 'y' to continue or 'n' to exit.${reset}"
        fi
    done
    echo
}

prompt_dump_type() {
    while true; do 
        echo
        echo -e "${yellow}Since a CNPG pod was found, the script can attempt to automatically create a database dump. Note that this requires the CNPG pod to have the ability to run successfully. If you have a recent CNPG database dump from another source (e.g., HeavyScript), you can provide that instead.${reset}"
        echo -e "${yellow}The default action is to have the script attempt to create a database dump, and should always be used unless your CNPG pod is problematic.${reset}"
        echo 
        read -n1 -s -rp "Would you like to provide your own database dump file? [y/N] " key

        if [[ $key == "y" || $key == "Y" ]]; then 
            echo
            return 1 # Manual
        elif [[ $key == "n" || $key == "N" || $key == "" ]]; then 
            echo
            return 0 # Automatic
        else
            echo -e "${yellow}\nInvalid key. Please press 'y' for manual database handling or 'n' (or Enter) for automatic.${reset}"
        fi
    done 
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
    update_or_append_variable "appname" "${appname}"
    update_or_append_variable "namespace" "${namespace}"
}

prompt_migration_path() {
    # Create a list of datasets within migration
    app_list=$(zfs list -H -o name -r "$ix_apps_pool/migration" | grep -E "$ix_apps_pool/migration/.*" | awk -F/ '{print $3}' | sort | uniq)

    # Check if there are any datasets and exit if there are none
    if [ -z "${app_list}" ]; then
        echo "No datasets found within migration."
        return 1
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

            # Define the backup path based on migration path
            local backup_path="/mnt/${migration_path}/backup"
            
            # Check for critical migration files
            if [[ ! -f "${backup_path}/pvcs_new.json" ]] || [[ ! -f "${backup_path}/pvcs_original.json" ]]; then
                echo -e "${red}Error: It looks like this migration is from an earlier version of the script.${reset}"
                echo -e "To continue with this specific migration, please switch to the legacy branch:"
                echo -e "${blue}git fetch --all${reset}"
                echo -e "${blue}git checkout legacy${reset}"
                echo -e "Dont forget to switch back to main after youre done with your older migrations:"
                echo -e "${blue}git checkout main${reset}"
                return 1
            fi
            break
        else
            echo "Invalid choice. Please enter a valid number."
        fi
    done
    return 0
}

