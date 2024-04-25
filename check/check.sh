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

check_health() {
    local chart_name catalog catalog_train output train_exists
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

    # Check for the existence of the app in the current train
    train_exists=$(echo "$available_trains" | grep -c "^$catalog_train$")

    if [[ "$train_exists" -eq 0 ]]; then
        # Print available trains and suggest the first available one as the new train
        new_train=$(echo "$available_trains" | head -n 1)
        echo -e "${red}The chart: ${blue}$chart_name${red} is not in the current train: ${blue}$catalog_train${reset}."
        echo -e "${red}You need to migrate this chart to a new train. Suggested new train: ${blue}$new_train${reset}"
        echo -e "Please visit ${blue}https://truecharts.org/news/train-renames/${reset} for information on how to migrate to a new train."
        echo -e "After updating the train, you can attempt the migration again."
        echo -e "If you want to force the migration, you can run the script with the ${blue}--force${reset} flag."
        echo -e "${red}Do not open a support ticket if you force the migration.${reset}"
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
        "\nconfiguration for various services and applications."\
        "\nIf you are 100% sure you want to migrate this application,"\
        "\nyou can do so by running the script with the ${blue}--force${reset} flag."
        return 1
    else
        echo -e "${green}Not system train${reset}\n"
    fi


    #############################################
    ############# Empty edit ####################
    #############################################

    # Perform the empty edit to check the application health
    if output=$(cli -c "app chart_release update chart_release=\"$appname\" values={}" 2>&1); then
        # If the command succeeded, print nothing
        echo -e "${green}Passed empty edit${reset}\n"
    else
        # If the command failed, print the error output and advice
        echo -e "${red}Failed${reset}"
        echo "Output:"
        echo "$output"
        echo -e "${red}This was the result of performing an empty edit, you probably need to make changes in the chart edit configuration in the GUI.${reset}"
        echo -e "${red}Please resolve the issues above prior to running the migration.${reset}"
        echo -e "${red}Make sure to check Truecharts #announcements for migrations you may have missed.${reset}"
        echo -e "${red}If you want to force the migration, you can run the script with the ${blue}--force${reset} flag.${reset}"
        echo -e "${red}Do not open a support ticket if you force the migration.${reset}"
        return 1
    fi


    #############################################
    ############# Check same pool ###############
    #############################################
    local openebs_pool
    openebs_pool=$(k3s kubectl get storageclass -o=json | jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true") | .parameters.poolname | split("/")[0]')

    if [[ "$ix_apps_pool" != "$openebs_pool" ]]; then
        echo -e "${red}OpenEBS dataset location: ${blue}$openebs_pool${red} does not match the location of the ix-applications pool: ${red}$ix_apps_pool${reset}"
        echo -e "${red}You need to change the dataset of the ${blue}$openebs_pool${red} to a dataset in the ${blue}$ix_apps_pool${red}.${reset}"
        return 1
    else
        echo -e "${green}Correct pool${reset}"
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
