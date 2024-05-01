import os
import secrets
import base64
import hashlib
import time
import json

def create_marker(username, backup_path, **kwargs):
    timestamp = time.time()
    states = json.dumps(kwargs)
    encoded_states = base64.b64encode(states.encode()).decode()

    secret_string = secrets.token_urlsafe(16)
    encoded_string = base64.b64encode(secret_string.encode())[::-1]
    combined_content = f"{timestamp}:{username}:{encoded_string}:{encoded_states}"
    hash_of_content = hashlib.sha256(combined_content.encode()).hexdigest() 
    marker_content = f"{hash_of_content}:{combined_content}"
    marker_filename = f".marker_{hash_of_content[:8]}"
    marker_path = os.path.join(backup_path, marker_filename)

    with open(marker_path, "w") as f:
        f.write(marker_content)

if __name__ == "__main__":
    import sys
    if len(sys.argv) < 6:
        print("Usage: python create_marker.py <username> <backup_path> <force> <outdated> <deploying>")
        sys.exit(1)

    username = sys.argv[1]
    backup_path = sys.argv[2]
    force = sys.argv[3]
    outdated = sys.argv[4]
    deploying = sys.argv[5]
    
    create_marker(username, backup_path, force=force, outdated=outdated, deploying=deploying)
