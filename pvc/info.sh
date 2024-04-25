#!/bin/bash

get_pvc_info() {
    local version=$1
    local pvc_backup_file="${backup_path}/pvcs_${version}.json"
    local pvc_data workloads_data pvc_name volume mount_path pvc_parent_path

    # Ensure backup directory exists
    mkdir -p "$backup_path"

    # Fetch all PVCs and workload data in JSON format
    pvc_data=$(k3s kubectl get pvc -n "$namespace" -o json)
    workloads_data=$(k3s kubectl get deployments,statefulsets,daemonsets -n "$namespace" -o json)

    echo '[' > "$pvc_backup_file"

    local first_entry=true
    while IFS= read -r pvc; do
        pvc_name=$(echo "$pvc" | jq -r '.metadata.name')
        volume=$(echo "$pvc" | jq -r '.spec.volumeName')
        mount_path=$(echo "$workloads_data" | jq --arg pvc_name "$pvc_name" -r '.items[].spec.template.spec | .volumes[] as $volume | select($volume.persistentVolumeClaim.claimName == $pvc_name) | .containers[].volumeMounts[] | select(.name == $volume.name) | .mountPath' | head -n 1)
        pvc_parent_path=$(k3s kubectl describe pv "$volume" | grep "poolname=" | awk -F '=' '{print $2}')

        # Format entry as JSON object and append to file, handling commas for valid JSON
        if [ "$first_entry" = true ]; then
            first_entry=false
        else
            echo ',' >> "$pvc_backup_file"
        fi

        jq -n \
        --arg pvc_name "$pvc_name" \
        --arg volume "$volume" \
        --arg mount_path "$mount_path" \
        --arg pvc_parent_path "$pvc_parent_path" \
        --arg original_rename_complete "false" \
        --arg matched "false" \
        --arg destroyed "false" \
        '{ 
            pvc_name: $pvc_name, 
            pvc_volume_name: $volume, 
            mount_path: $mount_path, 
            pvc_parent_path: $pvc_parent_path, 
            original_rename_complete: $original_rename_complete, 
            matched: $matched,
            destroyed: $destroyed
        }' >> "$pvc_backup_file"



    done < <(echo "$pvc_data" | jq -c '.items[]')

    echo ']' >> "$pvc_backup_file"
}


update_pvc_migration_status() {
    local pvc_backup_file="${backup_path}/pvcs_original.json"

    # Calculate the number of original PVCs
    original_pvs_count=$(jq '. | length' "$pvc_backup_file")
    
    # Determine if migration should occur based on count
    if [ "$original_pvs_count" -eq 0 ]; then
        migrate_pvs=false
    else
        migrate_pvs=true
    fi
}

