#!/bin/bash

get_pvc_info() {
    # Grab the app's PVC names and volume names
    pvc_info=$(k3s kubectl get pvc -n "${namespace}" -o custom-columns="NAME:.metadata.name,VOLUME:.spec.volumeName" --no-headers)
}

rename_original_pvcs() {
    # Rename the app's PVCs
    echo "Renaming the app's PVCs..."
    echo "${pvc_info}" | while read -r line; do
        pvc_name=$(echo "${line}" | awk '{print $1}')
        volume_name=$(echo "${line}" | awk '{print $2}')
        old_pvc_name="$pvc_parent_path/${volume_name}"
        new_pvc_name="${ix_apps_pool}/migration/${pvc_name}"
        if zfs rename "${old_pvc_name}" "${new_pvc_name}"; then 
            echo "Renamed ${old_pvc_name} to ${new_pvc_name}"
        else
            echo "Error: Failed to rename ${old_pvc_name} to ${new_pvc_name}"
            exit 1
        fi
    done
}

verify_rename() {
    # Verify the rename was successful
    echo "Verifying the rename was successful..."
    if zfs list -r "${ix_apps_pool}/migration" | grep "${appname}" > /dev/null; then
        echo "Rename successful."
    else
        echo "Rename failed."
        exit 1
    fi
}

rename_migration_pvcs() {
    echo "Renaming the migration PVCs to the new app's PVC names..."

    # Create an array to store the migration PVCs
    migration_pvcs=()

    # Get the list of migration PVCs
    migration_pvcs_info=$(zfs list -r "${ix_apps_pool}/migration" | grep "${appname}" | awk '{print $1}')

    # Read the migration_pvcs_info line by line and store the migration PVCs in the migration_pvcs array
    while read -r line; do
        pvc_name=$(basename "${line}")
        migration_pvcs+=("${pvc_name}")
    done < <(echo "${migration_pvcs_info}")

    if [ ${#migration_pvcs[@]} -eq 0 ]; then
        echo "Error: No migration PVCs found."
        exit 1
    fi

    for old_pvc in "${migration_pvcs[@]}"; do
        most_similar_pvc=$(find_most_similar_pvc "$old_pvc")
        if zfs rename "${ix_apps_pool}/migration/${old_pvc}" "$pvc_parent_path/${most_similar_pvc}"; then
            echo "Renamed ${ix_apps_pool}/migration/${old_pvc} to $pvc_parent_path/${most_similar_pvc}"
        else
            echo "Error: Failed to rename ${ix_apps_pool}/migration/${old_pvc} to $pvc_parent_path/${most_similar_pvc}"
            exit 1
        fi
    done

    echo
}

destroy_new_apps_pvcs() {
    echo "Destroying the new app's PVCs..."

    # Create an array to store the new PVCs
    new_pvcs=()
    
    # Read the PVC info line by line and store the new PVCs in the new_pvcs array
    while read -r line; do
        pvc_and_volume=$(echo "${line}" | awk '{print $1 "," $2}')
        new_pvcs+=("${pvc_and_volume}")
    done < <(echo "${pvc_info}")

    if [ ${#new_pvcs[@]} -eq 0 ]; then
        echo "Error: No new PVCs found."
        exit 1
    fi

    for new_pvc in "${new_pvcs[@]}"; do
        IFS=',' read -ra pvc_and_volume_arr <<< "$new_pvc"
        volume_name="${pvc_and_volume_arr[1]}"
        to_delete="$pvc_parent_path/${volume_name}"

        success=false
        attempt_count=0
        max_attempts=2

        while ! $success && [ $attempt_count -lt $max_attempts ]; do
            if output=$(zfs destroy "${to_delete}"); then
                echo "Destroyed ${to_delete}"
                success=true
            else
                if echo "$output" | grep -q "dataset is busy" && [ $attempt_count -eq 0 ]; then
                    echo "Dataset is busy, restarting middlewared and retrying..."
                    systemctl restart middlewared
                    sleep 5
                    stop_app_if_needed "$appname"
                    sleep 5
                else
                    echo "Error: Failed to destroy ${to_delete}"
                    echo "Error message: $output"
                    exit 1
                fi
            fi
            attempt_count=$((attempt_count + 1))
        done
    done
    echo
}

get_pvc_parent_path() {
    local volume_name
    volume_name=$(echo "$pvc_info" | awk '{print $2}' | head -n 1)

    pvc_path=$(zfs list -r "${ix_apps_pool}/ix-applications" -o name -H | grep "${volume_name}")

    if [ -z "${pvc_path}" ]; then
        echo "PVC not found"
        exit 1
    fi

    pvc_parent_path=$(dirname "${pvc_path}")
}

find_most_similar_pvc() {
    local source_pvc=$1
    local max_similarity=0
    local most_similar_pvc=""
    local most_similar_volume=""

    for target_pvc_info in "${new_pvcs[@]}"; do
        IFS=',' read -ra pvc_and_volume_arr <<< "$target_pvc_info"
        target_pvc_name="${pvc_and_volume_arr[0]}"
        target_volume_name="${pvc_and_volume_arr[1]}"

        local len1=${#source_pvc}
        local len2=${#target_pvc_name}
        local maxlen=$(( len1 > len2 ? len1 : len2 ))
        local dist
        dist=$(python pvc/levenshtein.py "$source_pvc" "$target_pvc_name")
        local similarity=$(( 100 * ( maxlen - dist ) / maxlen ))

        if [ "$similarity" -gt "$max_similarity" ]; then
            max_similarity=$similarity
            most_similar_pvc=$target_pvc_name
            most_similar_volume=$target_volume_name
        fi
    done
    echo "$most_similar_volume"
}