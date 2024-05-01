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

def write_log(log_file_path, logs):
    with open(log_file_path, 'w') as file:
        json.dump(logs, file, indent=4)

def check_integrity(file_path, log_path):
    log_file_path = os.path.join(log_path, ".variables.log")
    current_hash = calculate_hash(file_path)
    logs = read_log(log_file_path)
    tampered_detected = False

    if logs:
        last_entry = logs[-1]
        last_hash = last_entry['hash']
        if last_hash != current_hash:
            tampered_detected = True
            last_entry['status'] = "Tampered"
            write_log(log_file_path, logs)
            print("\033[93m\nStatus: Tampered\n\033[0m")

    return tampered_detected

def log_update(file_path, log_path, variable_name, value):
    log_file_path = os.path.join(log_path, ".variables.log")
    logs = read_log(log_file_path)
    new_hash = calculate_hash(file_path)
    tampered_status = "Tampered" if any(entry['status'] == "Tampered" for entry in logs) else "Not Tampered"

    variable_entry = f"{variable_name}={value}"

    new_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()),
        "file": file_path,
        "variable_entry": variable_entry,
        "hash": new_hash,
        "status": tampered_status
    }
    logs.append(new_entry)
    write_log(log_file_path, logs)

if __name__ == "__main__":
    action = sys.argv[1]
    if action == "check_integrity":
        _, _, file_path, log_path = sys.argv
        check_integrity(file_path, log_path)
    elif action == "log_update":
        _, _, file_path, log_path, variable_name, value = sys.argv
        log_update(file_path, log_path, variable_name, value)
