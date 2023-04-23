#!/bin/bash

prompt_app_name() {
    while true
    do
        # Prompt the user for the app name
        read -r -p "Enter the application name: " appname
        namespace="ix-${appname}"

        # Check if the app exists
        if app_exists "${appname}"; then
            echo "Found: ${appname}"
            break
        else
            echo "Error: App not found."
        fi
    done
}

prompt_create_backup() {
    echo
    echo "Please copy the app's config manually from the GUI (Edit app) and save it in a safe place."
    echo "Take Screenshots or whatever you want."
    echo "I personally open two tabs, one tab with the old config open, and another tab with the new config open."
    while true; do
        read -n1 -s -rp "Press 'x' to continue..." key
        if [[ $key == "x" ]]; then
            echo -e "\nContinuing..."
            break
        else
            echo -e "\nInvalid key. Please press 'x' to continue."
        fi
    done
}

prompt_rename() {
    while true; do
        read -n1 -s -rp "Do you want to rename the app? [y/N] " key
        if [[ $key == "y" ]]; then
            echo -e "\nRenaming..."
            rename_app
            break
        elif [[ $key == "N" || $key == "" ]]; then
            echo -e "\nSkipping..."
            break
        else
            echo -e "\nInvalid key. Please press 'y' to rename the app or 'N' to skip."
        fi
    done
}

rename_app() {
    # Prompt the user for the new app name
    read -r -p "Enter the new application name: " new_appname

    appname="${new_appname}"
    namespace="ix-${appname}"
}