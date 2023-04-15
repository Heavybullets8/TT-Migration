#!/bin/bash


get_app_status() {
    local app_name
    app_name="$1"

    cli -m csv -c 'app chart_release query name,status' | \
            grep -- "^$app_name," | \
            awk -F ',' '{print $2}'
}

handle_stop_code() {
    local stop_code
    stop_code="$1"

    case "$stop_code" in
        0)
            echo "Stopped"
            return 0
            ;;
        1)
            echo -e "Failed to stop\nManual intervention may be required"
            return 1
            ;;
        2)
            echo -e "Timeout reached\nManual intervention may be required"
            return 1
            ;;
        3)
            echo "HeavyScript doesn't have the ability to stop Prometheus"
            return 1
            ;;
        4)
            echo "The new application contains a cnpg pod, there is no way to restore to this new application"
            echo "Please restore to a previous snapshot"
            echo "Alternatively, you can try to follow these steps:"
            echo "   1. Delete the new app you just created"
            echo "   2. Install the new app with ${blue}custom-app${reset}, that is available in the catalog"
            echo "   3. Give it the same name as the original app"
            echo "   4. Fill out all of the information for the new app, with the information from the old app"
            echo "   5. Once that application has started, you can run ${blue}bash migrate -s${reset}, this will migrate the data from the old app to the new ${blue}custom-app${reset}"
            echo "   NOTE: If you need an example on how to fill out the information for the new app, you can look here:${blue}https://heavysetup.info/applications/sonarr/installation/${reset}"
            return 1
            ;;
    esac
}

stop_app() {
    # Return 0 if app is stopped
    # Return 1 if cli command outright fails
    # Return 2 if timeout is reached
    # Return 3 if app is a prometheus instance
    # Return 4 if the new app contains a cnpg pod

    local app_name timeout status
    app_name="$1"
    timeout="150"

    # Grab chart info
    chart_info=$(midclt call chart.release.get_instance "$app_name")

    # Check if app has a cnpg pods
    if printf "%s" "$chart_info" | grep -sq -- \"cnpg\":;then
        return 4
    # Check if app is a prometheus instance
    elif printf "%s" "$chart_info" | grep -sq -- \"prometheus\":;then
        return 3
    fi

    status=$(get_app_status "$app_name")
    if [[ "$status" == "STOPPED" ]]; then
        return 0
    fi

    timeout "${timeout}s" cli -c 'app chart_release scale release_name='\""$app_name"\"\ 'scale_options={"replica_count": 0}' &> /dev/null
    timeout_result=$?

    if [[ $timeout_result -eq 0 ]]; then
        return 0
    elif [[ $timeout_result -eq 124 ]]; then
        return 2
    fi

    return 1
}
