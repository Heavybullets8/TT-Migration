#!/bin/bash

check_privileges() {
# Check user's permissions
if [[ $(id -u) != 0 ]]; then
    echo -e "${red}This script must be run as root.${reset}" >&2
    echo -e "${red}Please run the following command:${reset}" >&2
    echo -e "${red}sudo bash migrate.sh${reset}" >&2
    echo -e "${red}or run the script as the ${blue}root${reset} user${reset}" >&2
    echo -e "${red}su root${reset}" >&2

    # Prompt the user to retry with sudo
    echo -e "${yellow}Would you like to run the script with sudo? (y/n)${reset}"
    read -r answer
    if [[ $answer =~ ^[Yy]$ ]]; then
        exec sudo bash "$script_path/$script_name" "${args[@]}"
    else
        return 1
    fi
fi
}

check_if_app_exists() {
    local appname=$1
    echo -e "${bold}Checking if app exists...${reset}"
    cli -m csv -c 'app chart_release query name' | tr -d " \t\r" | grep -qE "^${appname}$" 
}

check_sql_dump_exists() {
    local heavy_path=$(find_latest_heavy_script_dir)
    echo -e "${bold}Checking if SQL dump exists...${reset}"

    if [[ $heavy_path ]]; then
        local dump_path="$heavy_path/database_dumps/$appname"
        if [[ -d $dump_path && $(ls -A $dump_path) ]]; then
            echo -e "${green}SQL dumps found for ${appname} at ${dump_path}\n"${reset}
            echo -e "${yellow}Please review the backup you would like to restore."${reset}
            echo -e "${yellow}Replace the file name with the backup of your choice and copy using the command below:\n"${reset}
            echo -e "${blue}cp ${dump_path}/${appname}_YYYY_MM_DD_HH_mm_ss.sql.gz ${backup_path}/ \n"${reset}
            echo -e "${yellow}After copying the database file re-run the script with the ${blue}--skip${yellow} flag, then select the manual option again."${reset}
            return 0
        else
            echo -e "${red}No SQL dumps found for ${appname}\n"${reset}
            echo -e "${yellow}If you have a database file that we did not find, provide the database file in the backup folder ${blue}$backup_path${yellow} and re-run the script with the ${blue}--skip${yellow} flag, then select the manual option again."${reset}
            return 1
        fi  
    else
        echo -e "${red}No SQL dumps found for ${appname}\n"${reset}
        echo -e "${yellow}If you have a database file that we did not find, provide the database file in the backup folder ${blue}$backup_path${yellow} and re-run the script with the ${blue}--skip${yellow} flag, then select the manual option again."${reset}
        return 1
    fi
}

check_health() {
    local catalog catalog_train output train_exists
    echo -e "${bold}Checking app health...${reset}"


    #############################################
    ########### Check train #####################
    #############################################


    # Check the current train label and catalog of the namespace
    if ! output=$(midclt call chart.release.get_instance "$appname" | jq '.'); then
        echo -e "${red}Failed to get the app details.${reset}"
        echo "$output"
        return 1
    fi

    # Extract values with jq, outputting raw strings
    catalog_train=$(echo "$output" | jq -r '.catalog_train // empty')
    catalog=$(echo "$output" | jq -r '.catalog // empty')
    chart_name=$(echo "$output" | jq -r '.chart_metadata.name // empty')
    version=$(echo "$output" | jq -r '.chart_metadata.version // empty')

    # Check if necessary details are available
    if [[ -z "$catalog_train" || -z "$catalog" || -z "$chart_name" ]]; then
        echo -e "${red}Failed to get either the catalog_train, catalog, or chart_metadata.name.${reset}"
        return 1
    fi

    # Fetch available trains for the app within the catalog
    if ! available_trains=$(midclt call app.available '[["name", "=", "'"$chart_name"'"], ["catalog", "=", "'"$catalog"'"]]' '{}' | jq -r '.[] | .train'); then
        echo -e "${red}Failed to fetch available trains${reset}"
        echo "$available_trains"
        return 1
    fi

    if [[ -z "$available_trains" ]]; then
        echo -e "${red}This chart doesnt appear anywhere in the catalog${reset}"
        echo -e "${red}A migration would fail to install the application, since there is nowhere to install the application from.${reset}"
        echo -e "${red}Please check the chart name and catalog and try again.${reset}"
        echo -e "Chart name: ${blue}$chart_name${reset}"
        echo -e "Catalog: ${blue}$catalog${reset}"
        echo -e "Catalog train: ${blue}$catalog_train${reset}"
        return 1
    fi

    # Check for the existence of the app in the current train
    train_exists=$(echo "$available_trains" | grep -c "^$catalog_train$")

    if [[ "$train_exists" -eq 0 ]]; then
        # Print available trains and suggest the first available one as the new train
        new_train=$(echo "$available_trains" | head -n 1)
        echo -e "${red}The chart: ${blue}$chart_name${red} is not in the current train: ${blue}$catalog_train${reset}."
        echo -e "${red}You need to migrate this chart to a new train. Suggested new train: ${blue}$new_train${reset}"
        echo -e "Please visit ${blue}https://truecharts.org/news/train-renames/${reset} for information on how to migrate to a new train."
        echo -e "After updating the train, you can attempt the migration again."
        return 1
    else
        echo -e "${green}Valid train${reset}"
    fi


    #############################################
    ############ Check system train #############
    #############################################

    if [[ "$catalog_train" == "system" ]]; then
    echo -e "${red}App is in the system train.${reset}"\
        "\nSystem train applications are rarely deleted,"\
        "\nlet alone migrated. Unless you are absolutely"\
        "\nsure, it is recommended to skip this application."\
        "\nDoing so can result in permanent loss of data and"\
        "\nconfiguration for various services and applications."
        return 1
    else
        echo -e "${green}Not system train${reset}"
    fi

    #############################################
    ############## Check app update #############
    #############################################
    local update_info
    if ! update_info=$(cli -m csv -c 'app chart_release query name,update_available,status' | tr -d " \t\r" | grep -E "^${appname},"); then
        echo -e "${red}Failed to get the app update status.${reset}"
        echo "$output"
        return 1
    fi

    #############################################
    ####### Ensure App Exists in Catalog ########
    #############################################

    if echo "$update_info" | grep -q ",true$"; then

        if [[ -z "$version" ]]; then
            echo -e "${red}Failed to get the version.${reset}"
            return 1
        fi
        outdated=true
        catalog_location=$(midclt call "catalog.query" | jq -r ".[] | select(.label == \"$catalog\" or .id == \"$catalog\") | .location")
        catalog_location=$catalog_location/$catalog_train/$chart_name

        release_location=/mnt/$ix_apps_pool/ix-applications/releases/$appname/charts/$version

        # Checking if the version exists in the release location
        if [[ -d "$release_location" ]]; then
            # Check if the version exists in the catalog
            if [[ ! -d "$catalog_location/$version" ]]; then
                # Copying the version directory from release to catalog, this will allow the chart to be installed from the catalog
                # Since the ix create function looks inside the catalog dir for the version that is being installed, then copies it to the release location
                cp -r "$release_location" "$catalog_location"
                echo -e "Version ${blue}$version${reset} of the chart ${blue}$chart_name${reset} was not found in the catalog and has been copied from the release location."
            fi
        else
            # The version does not exist in the release location
            echo -e "${red}The version: ${blue}$version${red} of the chart: ${blue}$chart_name${red} is not available in the catalog: ${blue}$catalog${reset}."
            echo -e "${red}You need to update your application to a new version prior to attempting the migration.${reset}"
            echo -e "${red}The script by default reinstalls the chart to the same version, if you would like to install the latest version, please use the ${blue}--latest-version,-l${red} flag.${reset}"
            echo -e "Note: Enabling the ${blue}--latest-version,-l${reset} flag will install the latest version of the chart from the catalog."
            echo -e "However, this will VOID any support for this migration since it's impossible to know if your current configuration is compatible with the new version."
            return 1
        fi
    fi

    #############################################
    ############## Check app status #############
    #############################################

    if echo "$update_info" | grep -q ",DEPLOYING,"; then
        deploying=true
    fi

    #############################################
    ############# Empty edit ####################
    #############################################

    local values  
    if ! values=$(midclt call chart.release.get_instance "$appname" | jq -c '.config'); then
        echo -e "${red}Failed to get the app config.${reset}"
        echo "$output"
        return 1
    fi

    # Perform the empty edit to check the application health
    if output=$(cli -c "app chart_release update chart_release=\"$appname\" values=$values" 2>&1); then
        # If the command succeeded, print nothing
        echo -e "${green}Passed empty edit${reset}"
    else
        # If the command failed, print the error output and advice
        echo -e "${red}Failed${reset}"
        echo "Output:"
        echo "$output"
        echo -e "${red}This was the result of performing an empty edit, you probably need to make changes in the chart edit configuration in the GUI.${reset}"
        echo -e "${red}Please resolve the issues above prior to running the migration.${reset}"
        echo -e "${red}Make sure to check Truecharts #announcements for migrations you may have missed.${reset}"
        return 1
    fi


    #############################################
    ############# Check same pool ###############
    #############################################
    local openebs_pool output_lines

    if ! output=$(k3s kubectl get storageclass -o=json | jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true") | .parameters.poolname'); then
        echo -e "${red}Error: Failed to get default storage class location${reset}"
        return 1
    fi

    if [[ -z "$output" ]]; then
        echo -e "${red}Error: No default storage class found or poolname is empty${reset}"
        return 1
    fi

    output_lines=$(echo "$output" | wc -l)
    if [[ "$output_lines" -gt 1 ]]; then
        echo -e "${red}Error: Multiple default pools found, expecting only one${reset}"
        echo -e "Output:"
        echo -e "$output"
        return 1
    fi

    openebs_pool=$(echo "$output" | awk -F '/' '{print $1}')

    # Compare pools
    if [[ "$ix_apps_pool" != "$openebs_pool" ]]; then
        echo -e "${red}OpenEBS dataset location: ${blue}$openebs_pool${red} does not match the location of the ix-applications pool: ${blue}$ix_apps_pool${red}.${reset}"
        echo -e "${red}You need to change the dataset of the ${blue}$openebs_pool${red} to a dataset in the ${blue}$ix_apps_pool${red}.${reset}"
        return 1
    else
        echo -e "${green}Correct pool${reset}\n"
    fi

    return 0
}

check_filtered_apps() {
    # Define a function to process each app name
    process_app_name() {
        appname=$1

        # Run the command and directly check if the values are true, and include the reason
        midclt call chart.release.get_instance "$appname" | jq -r '
            if .config.operator.enabled == true then
                .name + ",operator"
            else
                empty
            end,
            if .config.cnpg.main.enabled == true then
                .name + ",cnpg"
            else
                empty
            end
            | select(length > 0)
        '
    }

    # Define a function to wait for a free slot in the semaphore
    wait_for_slot() {
        while true; do
            # Count the number of background jobs
            job_count=$(jobs -p | wc -l)

            # Check if there's a free slot
            if [[ $job_count -lt 5 ]]; then
                break
            fi

            # Wait for a short period before checking again
            sleep 0.1
        done
    }

    # Check if an array was passed as an argument
    if [ $# -eq 0 ]; then
        # Define the app names array using the command
        mapfile -t app_names < <(cli -m csv -c 'app chart_release query name' | tail -n +2 | sort | tr -d " \t\r" | awk 'NF')
    else
        # Use the passed array
        app_names=("$@")
    fi

    # Process the app names with a maximum of 5 concurrent processes
    for appname in "${app_names[@]}"; do
        wait_for_slot
        process_app_name "$appname" &
    done

    # Wait for any remaining jobs to finish
    wait
}
