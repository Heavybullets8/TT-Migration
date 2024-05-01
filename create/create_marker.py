import os
import secrets
import base64
import hashlib
import time
import json
from datetime import datetime

def create_marker(username, app_name, namespace, backup_path, chart_name, **kwargs):
    timestamp = datetime.utcnow().isoformat() 
    states = json.dumps(kwargs)  
    
    encoded_backup_path = base64.urlsafe_b64encode(backup_path.encode()).decode()
    secret_component = secrets.token_urlsafe(16)  # A secret component to add complexity
    components = f"{timestamp}:{username}:{app_name}:{namespace}:{encoded_backup_path}:{chart_name}:{secret_component}"
    
    combined_hash = hashlib.sha256(components.encode()).hexdigest()
    
    marker_content = f"{combined_hash}:{timestamp}:{username}:{app_name}:{namespace}:{encoded_backup_path}:{chart_name}:{states}"
    
    marker_filename = f".marker_{hashlib.sha256(marker_content.encode()).hexdigest()[:8]}"
    marker_path = os.path.join(backup_path, marker_filename)

    with open(marker_path, "w") as f:
        f.write(marker_content)

if __name__ == "__main__":
    import sys
    if len(sys.argv) < 10:
        print("Usage: python create_marker.py <username> <app_name> <namespace> <backup_path> <chart_name> <force> <outdated> <deploying> <migrate_db> <migrate_pvs>")
        sys.exit(1)

    username = sys.argv[1]
    app_name = sys.argv[2]
    namespace = sys.argv[3]
    backup_path = sys.argv[4]
    chart_name = sys.argv[5]
    force = sys.argv[6]
    outdated = sys.argv[7]
    deploying = sys.argv[8]
    migrate_db = sys.argv[9]
    migrate_pvs = sys.argv[10]
    
    create_marker(username, app_name, namespace, backup_path, chart_name, force=force, outdated=outdated, deploying=deploying, migrate_db=migrate_db, migrate_pvs=migrate_pvs)
