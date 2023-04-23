#!/bin/bash


create_migration_dataset() {
    local path=${ix_apps_pool}/migration

    # Check if the migration dataset exists, and create it if it doesn't
    if ! zfs list "${ix_apps_pool}/migration" >/dev/null 2>&1; then
        echo "Creating migration dataset..."
        if zfs create "${ix_apps_pool}/migration"; then
            echo "Dataset created: ${ix_apps_pool}/migration"
            echo
        else
            echo "Error: Failed to create migration dataset."
            exit 1
        fi
    fi
}

create_app_dataset() {
    local path=${ix_apps_pool}/migration/${appname}
    export migration_path

    # Check if the app dataset exists, and create it if it doesn't
    if ! zfs list "$path" >/dev/null 2>&1; then
        echo "Creating app dataset..."
        if zfs create "$path"; then
            migration_path=$path
            echo "Dataset created: $path"
            echo
        else
            echo "Error: Failed to create app dataset."
            exit 1
        fi
    fi
}