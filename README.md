# Migration Script for TrueNAS SCALE
This script is designed to migrate most applications on TrueNAS SCALE. Occasionally, breaking changes occur which make updates impossible. This script may help overcome such issues by facilitating safe and effective migration of applications. Works with PVC's, CNPG Databases, both, or neither. 

<br>

## Usage

```bash
bash migration.sh
```

<br>

### Options

| Option        | Short Form | Description                                                  |
|---------------|------------|--------------------------------------------------------------|
| --skip        | -s         | Continue with a previously started migration                 |
| --no-update   | -n         | Do not check for script updates                              |
| --force       |            | Force migration without checking for db pods                 |

---

<br>

## Failures

> Make sure to retry with the `--skip` option

Failed applications will be added to this list if any are confirmed. 

| Application        |
|--------------------|

---

<br>

## Guide

### Run The Script

![Run Script](https://github.com/Heavybullets8/TT-Migration/assets/20793231/94e382fe-208f-4a00-a384-f0572b28ad25)

<br>

### Finding App Dataset

![Find Dataset](https://github.com/Heavybullets8/TT-Migration/assets/20793231/70a05b36-8b14-4e03-a4f2-dc9e97872aa2)

<details>
<summary>App Dataset Not Found?</summary>

Make sure you have a pool selected at: `TrueNAS GUI > Apps`.

</details>

<br>

### System Train Check

![System Train](https://github.com/Heavybullets8/TT-Migration/assets/20793231/d36d3cf2-16f0-4162-bdc8-c949579b3e53)

<details>
<summary>Application is on the system train?</summary>

![image](https://github.com/Heavybullets8/TT-Migration/assets/20793231/745cfa60-4d79-44b8-ab04-dcdea8165e3d)


Unless specifically told to, you should not migrate these applications, but you can if you use the `--force` flag.

</details>

<br>

### Database Check

> Only used to check for CNPG databases

![Database Check](https://github.com/Heavybullets8/TT-Migration/assets/20793231/371a7e27-69a0-4aa8-9139-b8ed6756d079)

<details>
<summary>Database Found?</summary>

<br>

**Prompt to Attempt Restore**

![Prompt Restore](https://github.com/Heavybullets8/TT-Migration/assets/20793231/c15ec76c-1164-4713-9bc9-04d01a598ead)

This means a CNPG database was found, and the script can attempt to backup and restore the database, but there is no guarantee that it will work. The script has been very solid in my experience when it comes to handling databases.

<br>

**Prompt to Provide Your Own Database**

![Provide DB](https://github.com/Heavybullets8/TT-Migration/assets/20793231/57e1dc5e-a543-4a26-9505-3dd655218ceb)

If you chose yes for the first prompt, you will then be prompted to choose to use the automatic restore or provide your own restore.

<br>

- If you choose yes, the script will exit and ask that you copy a file to the specified directory.
  
  ![Exit Script](https://github.com/Heavybullets8/TT-Migration/assets/20793231/18fd4bcb-e70b-4ff4-8975-f660f605f797)

<br>

- If you choose no, the script will create a new dump.

  ![Create Dump](https://github.com/Heavybullets8/TT-Migration/assets/20793231/30b5441c-a427-47ff-bd6b-206a2c31fa23)

</details>

<br>

### Creating App Dataset

![Create Dataset](https://github.com/Heavybullets8/TT-Migration/assets/20793231/f4a93a0c-8d9d-416b-880b-9b9d96abd6e9)

This created a dataset that will be used throughout the migration for backup information.

<br>

### Renaming the App's PVCs

![Rename PVCs](https://github.com/Heavybullets8/TT-Migration/assets/20793231/bfe4b241-c1c0-4232-9ceb-f79ba5caf0ec)

This moves the original applications PVCs to the backup directory.

<br>

### Deleting the Original App

![Delete App](https://github.com/Heavybullets8/TT-Migration/assets/20793231/3e404112-88ce-40fb-9575-ffe72345bb63)

<details>
<summary>Failure?</summary>

Occasionally failures can happen, the script will attempt to work through them, but if the script exits here, you will need to delete the application manually prior to continuing. This includes deleting any PVs and datasets for the application that are NOT under the migration dataset.

</details>

<br>

### Renaming The Application

![Rename App](https://github.com/Heavybullets8/TT-Migration/assets/20793231/d96bc17d-be60-4565-b5a4-51e8a69e7253)

If you choose to, you can rename the new application differently from the original.

<br>

### Creating the Application

![Create App](https://github.com/Heavybullets8/TT-Migration/assets/20793231/adf4e709-5282-46f4-8ac0-886b6ff24d74)


This creates the application with all the same settings from the original install.

<br>

### Destroying the New App's PVCs

![Destroy PVCs](https://github.com/Heavybullets8/TT-Migration/assets/20793231/43227621-0fae-4c4d-b9b2-1f6424c992c9)

This will destroy the new applications PVCs so that they can be replaced by the original.

<br>

### Renaming the Migration PVCs to the New App's PVC Names

![Rename Migration PVCs](https://github.com/Heavybullets8/TT-Migration/assets/20793231/f7d5d80d-ca1e-4068-9410-3929c04b134a)

This matches the applications PVCs, then renames and moves the originals.

