#!/bin/bash

pull_replicas() {
    local app_name
    app_name="$1"

    # First Check
    if ! replica_info=$(midclt call chart.release.get_instance "$app_name" | jq '.config.workload.main.replicas // .config.controller.replicas // empty'); then
        return 1
    fi

    # Second Check if First Check returns null or 0
    if [[ -z "$replica_info"  || "$replica_info" == "0" ]]; then
        replica_info=$(k3s kubectl get deployments -n "ix-$app_name" --selector=app.kubernetes.io/instance="$app_name" -o=jsonpath='{.items[*].spec.replicas}{"\n"}')
        # Replace 0 with 1
        replica_info=$(echo "$replica_info" | awk '{if ($1 == 0) $1 = 1; print $1}')
    fi

    # Output the replica info or "null" if neither command returned a result
    if [[ -z "$replica_info" || "$replica_info" == *" "* ]]; then
        echo "null"
    else
        echo "$replica_info"
    fi
}

start_app(){
    local app_name=$1

    # Check if app is a cnpg instance, or an operator instance
    output=$(check_filtered_apps "$app_name")


    if [[ $output == *"${app_name},stopAll-"* ]]; then

        if ! latest_version=$(midclt call chart.release.get_instance "$app_name" | jq -r ".chart_metadata.version // empty"); then
            return 1
        fi

        if [[ -z "$latest_version" ]]; then
            return 1
        fi

        # Disable stopAll and isStopped
        if ! helm upgrade -n "ix-$app_name" "$app_name" \
            "/mnt/$ix_apps_pool/ix-applications/releases/$app_name/charts/$latest_version" \
            --kubeconfig "/etc/rancher/k3s/k3s.yaml" \
            --reuse-values \
            --set global.stopAll=false \
            --set global.ixChartContext.isStopped=false > /dev/null 2>&1; then 
            return 1
        fi

    else
        replicas=$(pull_replicas "$app_name")
        if [[ -z "$replicas" || "$replicas" == "null" ]]; then
            return 1
        fi
        
        if ! cli -c 'app chart_release scale release_name='\""$app_name"\"\ 'scale_options={"replica_count": '"$replicas}" > /dev/null 2>&1; then
            return 1
        fi
    fi
    return 0
}
