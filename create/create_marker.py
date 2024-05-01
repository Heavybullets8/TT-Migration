import hashlib
import sys
import os
import time
import json

def calculate_hash(file_path):
    try:
        with open(file_path, 'rb') as file:
            file_data = file.read()
        hash_object = hashlib.sha256(file_data)
        return hash_object.hexdigest()
    except FileNotFoundError:
        return None

def read_log(log_file_path):
    if os.path.exists(log_file_path):
        with open(log_file_path, 'r') as file:
            try:
                return json.load(file)
            except json.JSONDecodeError:
                return []
    else:
        return []

def write_log(log_file_path, data):
    with open(log_file_path, 'w') as file:
        json.dump(data, file, indent=4)

def check_and_update_log(file_path, log_path, variable_name, value):
    log_file_path = os.path.join(log_path, ".variables.log")
    logs = read_log(log_file_path)
    current_hash = calculate_hash(file_path)
    
    if logs:
        last_entry = logs[-1]
        last_hash = last_entry['hash']
        status = "Not Tampered" if last_hash == current_hash else "Tampered"
    else:
        status = "Not Tampered"  # No previous entries means it's the initial state

    new_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()),
        "file": file_path,
        "log_path": log_path,
        "variable_name": variable_name,
        "value": value,
        "hash": current_hash,
        "status": status
    }
    logs.append(new_entry)
    write_log(log_file_path, logs)

if __name__ == "__main__":
    _, action, file_path, log_path, variable_name, value = sys.argv
    check_and_update_log(file_path, log_path, variable_name, value, action)
