# Migration Script for PVCs

This script is designed to assist with the migration of Persistent Volume Claims (PVCs) between TrueCharts latest common refactor

It follows the steps outlined in this guide: https://docs.dasnipe.com/docs/truenas/Fast-Reinstall

## Guide
https://docs.dasnipe.com/docs/truenas/HeavyBullet-Migration


## Usage

```bash
bash migration.sh
```

### Note

If an application fails to stop the NEW application, and throws any errors. You can attempt to run the script again, with:

```bash
bash migrate.sh -s
```

which will skip to the step immediately after deleting the old application.

## What it doesn't work on

Applications with databases such as mariadb, postgresql, etc.

## Tested on

| Application        | Status  |
|--------------------|---------|
| filebrowser        | Success |
| Custom-app Apps    | Success |
| Komga              | Success |
| emulatorjs         | Success |
| homarr             | Success |
| freshrss           | Success |
| mysql-workbench    | Success |
| bazarr             | Success |
| flaresolverr       | Success |
| phpldapadmin       | Success |
| podgrab            | Success |
| sabnzb             | Success |
| uptime-kuma        | Success |
| unpackerr          | Success |
| autoscan           | Success |
| tautulli           | Success |
| overseerr          | Success |
| code-server        | Success |
| Jellyseerr         | Success |
| adguard-home       | Success |
| photoprism         | Failed  |
| Prometheus         | Failed  |
| Readarr            | Failed  |
| Radarr             | Failed  |
| Homepage           | Success |
