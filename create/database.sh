#!/bin/bash

restore_database() {
    app="$1"
    dump_file=$(find "${backup_path}" -type f -name '*.sql' -print -quit)

    if [[ -z $dump_file ]]; then
        echo -e "${red}No database dump file found in ${blue}${backup_path}${reset}"
        return 1
    fi

    echo -e "${bold}Restoring database${reset}..."

    app_status=$(cli -m csv -c 'app chart_release query name,status' | grep "^$appname," | awk -F ',' '{print $2}' | tr -d " \t\r" )
    if [[ $app_status == "STOPPED" ]]; then
        start_app "$app"
    fi

    if ! wait_for_postgres_pod "$app"; then
        echo -e "${red}Postgres pod failed to start.${reset}"
        return 1
    fi

    # Get the primary database pod
    cnpg_pod=$(k3s kubectl get pods -n "ix-$app" --no-headers -o custom-columns=":metadata.name" -l role=primary | head -n 1)

    if [[ -z $cnpg_pod ]]; then
        echo -e "${red}Failed to get cnpg pod for $app.${reset}"
        return 1
    fi


    if ! db_name=$(k3s kubectl get secrets -n "ix-${app}" -o json | jq -r '.items[] | select(.metadata.name | endswith("-cnpg-main-urls")) | select(.data.host and .data.std) | .data.std // empty' | base64 --decode | awk -F '/' '{print $NF}'); then
        echo -e "${red}Failed to get database name for $app.${reset}"
        return 1
    fi

    if [[ -z $db_name ]]; then
        echo -e "${red}Failed to get database name for $app.${reset}"
        return 1
    fi

    # get database role
    if ! db_role=$(k3s kubectl get secrets -n "ix-${app}" -o json | jq -r '.items[] | select(.metadata.name | endswith("-cnpg-main-user")) | select(.data.username and .data.password) | .data.username // empty' | base64 --decode); then
        db_role=$db_name
    fi

    # Restore
    if [[ $chart_name == "immich" ]]; then
        echo "Preparing to process the PostgreSQL dump file..."
        echo "Dump file to be processed: $dump_file"
        echo "First few lines of the dump file before filter:"
        head "$dump_file" 
        echo
        # Replace the search path setting in the SQL dump
        sed -i "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" "$dump_file"
        
        echo "First few lines of the dump file after filter:"
        # Show the first 10 lines of the dump file to confirm its content
        head "$dump_file" 
        echo
        
        echo "Starting PostgreSQL import..."
        # Execute psql and log output with high verbosity
        if k3s kubectl exec -n "ix-$app" -c "postgres" "${cnpg_pod}" -- psql -e -a < "$dump_file"; then
            echo -e "${green}Success\n${reset}"
            echo "PostgreSQL import completed successfully."
            return 0
        else
            echo -e "${red}Failed to execute psql command\n${reset}"
            return 1
        fi
    else 
        if k3s kubectl exec -n "ix-$app" -i -c postgres "$cnpg_pod" -- pg_restore --role="$db_role" -d "$db_name" --clean --if-exists --no-owner --no-privileges -1 < "$dump_file"; then
            echo -e "${green}Success\n${reset}"
            return 0
        else
            echo -e "${red}Failed to restore database.\n${reset}"
            return 1
        fi
    fi
}

dump_database() {
    app="$1"
    output_dir="$2"
    output_file="${output_dir}/${app}.sql"

    cnpg_pod=$(k3s kubectl get pods -n "ix-$app" --no-headers -o custom-columns=":metadata.name" -l role=primary | head -n 1)

    if [[ -z $cnpg_pod ]]; then
        echo -e "${red}Failed to get cnpg pod for $app.${reset}"
        return 1
    fi

    # Grab the database name from the app's configmap
    if ! db_name=$(k3s kubectl get secrets -n "ix-${app}" -o json | jq -r '.items[] | select(.metadata.name | endswith("-cnpg-main-urls")) | select(.data.host and .data.std) | .data.std // empty' | base64 --decode | awk -F '/' '{print $NF}'); then
        echo -e "${red}Failed to get database name for $app.${reset}"
        return 1
    fi

    if [[ -z $db_name ]]; then
        echo -e "${red}Failed to get database name for $app.${reset}"
        return 1
    fi

    # Create the output directory if it doesn't exist
    mkdir -p "${output_dir}" || return 1


    # Backup
    if [[ $chart_name == "immich" ]]; then
        if k3s kubectl exec -n "ix-$app" -c "postgres" "$cnpg_pod" -- pg_dumpall --clean --if-exists > "$output_file"; then
            sed -i "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" "$output_file"
            return 0
        else
            rm -f "$output_file" &> /dev/null
            return 1
        fi
    else
        # Perform pg_dump and save output to a file
        if k3s kubectl exec -n "ix-$app" -c "postgres" "${cnpg_pod}" -- bash -c "pg_dump -Fc -d $db_name" > "$output_file"; then
            return 0
        else
            rm -f "$output_file" &> /dev/null
            return 1
        fi
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
    app_status=$(cli -m csv -c 'app chart_release query name,status' | grep "^$appname," | awk -F ',' '{print $2}' | tr -d " \t\r" )

    echo -e "${bold}Dumping database...${reset}"

    # Start the app if it is stopped
    if [[ $app_status == "STOPPED" ]]; then
        start_app "$appname"
        wait_for_postgres_pod "$appname"
    fi
                                        
    # Dump the database
    if dump_database "$appname" "$dump_folder"; then
        echo -e "${green}Success${reset}\n"
    else
        echo -e "${red}Failed to back up ${blue}$appname${red}'s database.${reset}"
        return 1
    fi

    # Stop the app if it was stopped
    if [[ $app_status == "STOPPED" ]]; then
        stop_app "direct" "$appname"
    fi
    return 0
}

check_for_db() {
    echo -e "${bold}Checking for databases...${reset}"

    if k3s kubectl get cluster -A --ignore-not-found | grep -E '^(ix-.*\s).*-cnpg-main-' | awk '{gsub(/^ix-/, "", $1); print $1}' | grep -q "^$appname$"; then
    echo -e "${yellow}A cnpg database for the application has been detected. The script can attempt a database restoration as part of the migration process. Please note that while the restoration process aims for accuracy, it might not always be successful. In the event of a restoration failure, the database SQL file will remain in the migration backup path for manual intervention.${reset}\n"

        prompt_continue_for_db
        migrate_db=true
    else
        echo -e "${green}No databases found.${reset}\n"
    fi
    return 0
}

search_for_database_file() {
    local search_directory="$1"
    local database_path

    # Find any .sql or .sql.gz file
    database_path=$(find "$search_directory" -maxdepth 1 -type f \( -name "*.sql" -o -name "*.sql.gz" \) -print -quit)

    if [[ -z "$database_path" ]]; then
        return 1  # No database file found
    fi

    # Handle compressed files
    if [[ "$database_path" =~ \.gz$ ]]; then
        echo -e "${yellow}Found compressed database file. Decompressing...${reset}"
        if ! gunzip -c "$database_path" > "${search_directory}/${appname}.sql"; then
            echo -e "${red}Error decompressing database file.${reset}"
            return 1
        fi
        database_path="${search_directory}/${appname}.sql"  # Update path after decompression
    fi

    # Rename the file to appname.sql
    if [[ "$database_path" != "${search_directory}/${appname}.sql" ]]; then
        mv "$database_path" "${search_directory}/${appname}.sql" || return 1
    fi

    return 0 
}