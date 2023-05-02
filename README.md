# Migration Script for PVCs

This script is designed to assist with the migration of Persistent Volume Claims (PVCs) between TrueCharts latest common refactor

It follows the steps outlined in this guide: https://docs.dasnipe.com/docs/truenas/Fast-Reinstall

## Guide
https://docs.dasnipe.com/docs/truenas/HeavyBullet-Migration

## Caution
Please be aware that the following actions are not supported:
- Creating replication tasks on PVCs within the ix-applications dataset, with the destination directory also located in the ix-applications dataset
- Modifying or performing unusual actions within the ix-applications dataset; kindly avoid making changes to this dataset to prevent issues with the script
- Starting a manual migration and expecting this script to complete the process; this script is intended to manage the entire migration from beginning to end
- Capturing snapshots of the ix-applications dataset at any point during the migration of an application, from start to finish


## Usage

```bash
bash migration.sh
```

### Options

| Option        | Short Form | Description                                                  |
|---------------|------------|--------------------------------------------------------------|
| --skip        | -s         | Continue with a previously started migration                 |
| --no-update   | -n         | Do not check for script updates                              |


### Note

If an application fails to stop the NEW application, and throws any errors, you can attempt to run the script again with:

```bash
bash migrate.sh -s
```

This command will skip to the step immediately after deleting the old application.

## What it doesn't work on

Applications with databases such as MariaDB, PostgreSQL, etc.

The script will check to see if these databases exist prior to accepting them for migration, but a list is provided below for verification.

## Tested on

| Application        | Status  |
|--------------------|---------|
| adguard-home       | Success |
| audiobookshelf     | Success |
| autoscan           | Success |
| bazarr             | Success |
| calibre            | Success |
| code-server        | Success |
| `Custom-app` Apps  | Success |
| deluge             | Success |
| emulatorjs         | Success |
| fileflows          | Success |
| filebrowser        | Success |
| flaresolverr       | Success |
| freshrss           | Success |
| heimdall           | Success |
| homarr             | Success |
| homepage           | Success |
| jellyfin           | Success |
| jellyseerr         | Success |
| Komga              | Success |
| mkvcleaver         | Success |
| mymediaforalexa    | Success |
| mysql-workbench    | Success |
| Netdata            | Success |
| organizr           | Success |
| omada-controller   | Success |
| overseerr          | Success |
| phpldapadmin       | Success |
| plex               | Success |
| podgrab            | Success |
| Prometheus         | Failed  |
| prowlarr           | Success |
| qBittorrent        | Success |
| radarr             | Success |
| readarr            | Success |
| recyclarr          | Success |
| sabnzb             | Success |
| scrutiny           | Success |
| sonarr             | Success |
| syncthing          | Success |
| tautulli           | Success |
| transmission       | Success |
| unifi              | Success |
| unpackerr          | Success |
| uptime-kuma        | Success |


