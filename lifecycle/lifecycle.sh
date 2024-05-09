#!/bin/bash

stop_app_if_needed() {
    # Stop application if not stopped
    status=$(cli -m csv -c 'app chart_release query name,status' | 
                grep "^$appname," | 
                awk -F ',' '{print $2}'| 
                sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [[ "$status" != "STOPPED" ]]; then
        echo -e "${bold}Stopping the app...${reset}"
        stop_app "direct" "$appname"
        result=$(handle_stop_code "$?")
        if [[ $? -eq 1 ]]; then
            echo -e "${red}${result}${reset}"
            return 1
        else
            echo -e "${green}${result}${reset}"
        fi
    fi
    echo
    return 0
}

delete_original_app() {
    local namespace="ix-$appname"
    local dataset="${ix_apps_pool}/ix-applications/releases/${appname}"

    echo -e "\n${bold}Beginning deletion of the app please wait...${reset}"

    sleep 10
    stop_app_if_needed || return 1
    sleep 10


    echo -e "${bold}Checking for lingering resources...${reset}"
    local total_objects
    total_objects=$(k3s kubectl get all -n "$namespace" --no-headers)

    # if [[ -n "$total_objects" ]]; then
    #     echo -e "${bold}Deleting all resources gracefully...${reset}"
    #     timeout 120s k3s kubectl delete all --all -n "$namespace" --grace-period=10 > /dev/null 2>&1 
    # fi

    total_objects=$(k3s kubectl get all -n "$namespace" --no-headers)

    if [[ -n "$total_objects" ]]; then
        echo -e "${bold}Deleting all resources forcefully...${reset}"
        k3s kubectl delete all --all -n "$namespace" --grace-period=0 --force > /dev/null 2>&1
    fi


    # echo -e "${bold}Handling finalizers...${reset}"
    # k3s kubectl get zv -o name -n openebs | xargs -I {} k3s kubectl patch {} -p '{"metadata":{"finalizers":[]}}' --type=merge -n openebs

    echo -e "${bold}Calling ix API to delete the app...${reset}"
    if ! output=$(cli -c "app chart_release delete release_name=\"${appname}\"" 2>&1); then
        echo -e "${red}Error: Failed to delete the app.${reset}"
        echo -e "${bold}Command error output:${reset}"
        echo -e "${output}"

        if [[ "$output" == *"dataset is busy"* ]]; then
            echo -e "\n${red}The dataset ${blue}'${dataset}'${red} is busy. This usually means resources are still in use.${reset}"
            echo -e "${red}Please check and ensure all resources using the dataset are terminated. You may need to manually destroy the dataset using the command:${reset}"
            echo -e "${blue}/usr/sbin/zfs destroy -r \"${dataset}\"${reset}"
            echo -e "After confirming that the namespace and ALL related datasets (except migrated PVs, if any) are destroyed, you can retry the operation using the ${blue}--skip${reset} flag."
        else
            echo -e "\nPlease ensure all pods are terminated and no resources are in use before trying again."
            echo -e "Rerun the script with ${blue}--skip${reset} after you are certain everything is deleted."
        fi
        echo -e "\n${bold}What to do if your dataset is reporting busy:${reset}"
        echo -e "Try the following in these EXACT steps, deviation of any kind can result in data loss:"
        echo -e "1. Try to delete the dataset using the command ${blue}/usr/sbin/zfs destroy -r \"${dataset}\"${reset}"
        echo -e "2. If Step 1 fails, note the name of the failed app(s) and continue migrating ALL remaining apps."
        echo -e "3. After all apps are migrated, unset the apps pool: TrueNAS SCALE GUI -> Applications -> Settings -> Unset Pool"
        echo -e "4. Go through your list of failed apps and delete them one by one example: ${blue}/usr/sbin/zfs destroy -r \"${dataset}\"${reset}"
        echo -e "5. After all failed apps datasets are deleted, set the apps pool: TrueNAS SCALE GUI -> Applications -> Settings -> Set Pool"
        echo -e "6. Re-run the script with ${blue}--skip${reset} flag for all failed apps."
        echo -e "\nIt is very important to attempt all migrations until unsetting the applications pool, unsetting the applications pool, or restarting with applicaitons mid-migration can result in data loss."
        return 1
    else
        echo -e "${green}Success${reset}\n"
    fi
    return 0
}


check_filtered_apps() {
    # Define a function to process each app name
    process_app_name() {
        local app_name=$1

        midclt call chart.release.get_instance "$app_name" | jq -r '
            if .chart_metadata.name == "prometheus" then
                .name + ",operator"
            elif .config.operator.enabled == true then
                .name + ",operator"
            elif .catalog_train == "operators" then
                .name + ",operator"
            else
                empty
            end,
            if .catalog == "TRUENAS" then
                .name + ",official"
            else
                empty
            end,
            if .config.cnpg.main.enabled == true then
                .name + ",cnpg"
            else
                empty
            end,
            if .config.global.stopAll == true then
                .name + ",stopAll-on"
            elif .config.global.stopAll == false then
                .name + ",stopAll-off"
            else
                empty
            end,
            if .config.global.ixChartContext.isStopped == true then
                .name + ",isStopped-on"
            elif .config.global.ixChartContext.isStopped == false then
                .name + ",isStopped-off"
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
    for app_name in "${app_names[@]}"; do
        wait_for_slot
        process_app_name "$app_name" &
    done

    # Wait for any remaining jobs to finish
    wait
}
