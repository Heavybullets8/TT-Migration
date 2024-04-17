#!/bin/bash


get_pvc_info() {
    local pvc_data workloads_data pvc
    pvc_data=$(k3s kubectl get pvc -n "$namespace" -o json)
    workloads_data=$(k3s kubectl get deployments,statefulsets,daemonsets -n "$namespace" -o json)

    while IFS= read -r pvc; do
        # Check for CNPG related annotations or labels
        if echo "$pvc" | jq -e '.metadata.labels | to_entries[] | select(.key | startswith("cnpg.io/"))' >/dev/null; then
            # This is a CNPG PVC, skip it
            continue
        fi

        local pvc_name volume mount_path
        pvc_name=$(echo "$pvc" | jq -r '.metadata.name')
        volume=$(echo "$pvc" | jq -r '.spec.volumeName')
        mount_path=$(echo "$workloads_data" | jq --arg pvc_name "$pvc_name" -r '.items[].spec.template.spec | .volumes[] as $volume | select($volume.persistentVolumeClaim.claimName == $pvc_name) | .containers[].volumeMounts[] | select(.name == $volume.name) | .mountPath')

        if [ "$mount_path" == "null" ]; then
            mount_path=""
        fi

        pvc_info+=("$pvc_name $volume $mount_path")
    done < <(echo "$pvc_data" | jq -c '.items[]')
}


check_pvc_info_empty() {
    if [ ${#pvc_info[@]} -eq 0 ]; then
        migrate_pvs=false
    else
        migrate_pvs=true
    fi
}

get_pvc_parent_path() {
    local volume_name
    volume_name=$(echo "$pvc_info" | awk '{print $2}' | head -n 1)

    pvc_path=$(k3s kubectl describe pv "$volume_name" | grep "poolname=" | awk -F '=' '{print $2}')


    if [ -z "${pvc_path}" ]; then
        echo -e "${red}PVC not found${reset}"
        exit 1
    fi

    pvc_parent_path="$pvc_path"
    update_or_append_variable pvc_parent_path "$pvc_parent_path"
}