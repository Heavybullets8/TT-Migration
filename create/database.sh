#!/bin/bash

dump_database() {
    app="$1"
    output_dir="$2/${app}"
    output_file="${output_dir}/${app}_${timestamp}.sql"

    cnpg_pod=$(k3s kubectl get pods -n "ix-$app" --no-headers -o custom-columns=":metadata.name" -l role=primary | head -n 1)

    if [[ -z $cnpg_pod ]]; then
        echo "Failed to get cnpg pod for $app."
        return 1
    fi

    # Grab the database name from the app's configmap
    db_name=$(midclt call chart.release.get_instance "$app" | jq .config.cnpg.main.database)

    if [[ -z $db_name ]]; then
        echo "Failed to get database name for $app."
        return 1
    fi

    # Create the output directory if it doesn't exist
    mkdir -p "${output_dir}"

    # Perform pg_dump and save output to a file
    if k3s kubectl exec -n "ix-$app" -c "postgres" "${cnpg_pod}" -- bash -c "pg_dump -Fc -d $db_name" > "$output_file"; then
        return 0
    else
        return 1
    fi
}

wait_for_postgres_pod() {
    appname=$1

    # shellcheck disable=SC2034
    for i in {1..30}; do
        pod_status=$(k3s kubectl get pods "${appname}-cnpg-main-1" -n "ix-${appname}" -o jsonpath="{.status.phase}" 2>/dev/null)

        if [[ "$pod_status" == "Running" ]]; then
            return 0
        else
            sleep 5
        fi
    done
    return 1
}

backup_cnpg_databases() {
    local appname=$1
    local dump_folder=$2

    echo -e "${bold}checking for databases...${reset}"

    if k3s kubectl get cluster -A | grep -E '^(ix-.*\s).*-cnpg-main-' | awk '{gsub(/^ix-/, "", $1); print $1}' | sort -u | grep -q "$appname"; then
        # If this block is executed, it means the app name was found
        echo -e "${green}Found: ${blue}backing up databases...${reset}"
    else
        # If this block is executed, it means the app name was not found
        echo -e "${blue}No databases found.${reset}"
        return 0
    fi

    for app in "${app_status_lines[@]}"; do
        app_status=$(cli -m csv -c 'app chart_release query name,status' | grep "^$app," | awk -F ',' '{print $2}')

        # Start the app if it is stopped
        if [[ $app_status == "STOPPED" ]]; then
            start_app "$appname"
            wait_for_postgres_pod "$appname"
        fi
                                         
        # Dump the database
        if ! dump_database "$appname" "$dump_folder"; then
            echo -e "${red}Failed to back up ${blue}$appname${red}'s database.${reset}"
            return 1
        fi

        # Stop the app if it was stopped
        if [[ $app_status == "STOPPED" ]]; then
            stop_app "direct" "$appname"
        fi


    done

}