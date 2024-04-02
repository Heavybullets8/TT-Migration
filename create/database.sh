#!/bin/bash

restore_database() {
    app="$1"
    dump_file="$2"

    echo -e "${bold}Restoring database${reset}..."

    if ! wait_for_postgres_pod "$app"; then
        echo -e "${red}Postgres pod failed to start.${reset}"
        exit 1
    fi

    # Get the primary database pod
    cnpg_pod=$(k3s kubectl get pods -n "ix-$app" --no-headers -o custom-columns=":metadata.name" -l role=primary | head -n 1)

    if [[ -z $cnpg_pod ]]; then
        echo -e "Failed to get cnpg pod for $app."
        exit 1
    fi

    # Retrieve the database name from the app's configuration
    db_name=$(midclt call chart.release.get_instance "$app" | jq -r .config.cnpg.main.database)

    if [[ -z $db_name ]]; then
        echo -e "Failed to get database name for $app."
        exit 1
    fi

    # Restore the database from the dump file
    if k3s kubectl exec -n "ix-$app" -i -c postgres "$cnpg_pod" -- pg_restore -d "$db_name" -c -1 < "$dump_file"; then
        echo -e "Database restored successfully.\n"
        return 0
    else
        echo -e "Failed to restore database.\n"
        exit 1
    fi
}

dump_database() {
    app="$1"
    output_dir="$2"
    output_file="${output_dir}/${app}.sql"

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

    for ((i = 1; i <= 30; i++)); do
        # Get the name of the primary pod
        primary_pod=$(k3s kubectl get pods -n "ix-$appname" --no-headers -o custom-columns=":metadata.name" -l role=primary | head -n 1 2>/dev/null)
        
        if [[ -z "$primary_pod" ]]; then
            sleep 5
            continue
        fi

        # Get the status of the primary pod
        pod_status=$(k3s kubectl get pod "$primary_pod" -n "ix-$appname" -o jsonpath="{.status.phase}" 2>/dev/null)

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
    app_status=$(cli -m csv -c 'app chart_release query name,status' | grep "^$appname," | awk -F ',' '{print $2}')

    # Start the app if it is stopped
    if [[ $app_status == "STOPPED" ]]; then
        start_app "$appname"
        wait_for_postgres_pod "$appname"
    fi
                                        
    # Dump the database
    if ! dump_database "$appname" "$dump_folder"; then
        echo -e "${red}Failed to back up ${blue}$appname${red}'s database.${reset}"
        exit 1
    fi

    # Stop the app if it was stopped
    if [[ $app_status == "STOPPED" ]]; then
        stop_app "direct" "$appname"
    fi
}

check_for_db() {
    echo -e "${bold}Checking for databases...${reset}"

    if k3s kubectl get cluster -A | grep -E '^(ix-.*\s).*-cnpg-main-' | awk '{gsub(/^ix-/, "", $1); print $1}' | grep -q "$appname"; then
        echo -e "${yellow}Found: Attempting a restore...${reset}\n"
        database_found=true
    else
        echo -e "${green}No databases found.${reset}\n"
    fi
}