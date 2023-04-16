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
| adguard-home       | Success |
| autoscan           | Success |
| bazarr             | Success |
| code-server        | Success |
| Custom-app Apps    | Success |
| emulatorjs         | Success |
| Fileflows          | Sucesss |
| filebrowser        | Success |
| flaresolverr       | Success |
| freshrss           | Success |
| homarr             | Success |
| Homepage           | Success |
| Jellyfin           | Success |
| Jellyseerr         | Success |
| Komga              | Success |
| mysql-workbench    | Success |
| overseerr          | Success |
| phpldapadmin       | Success |
| photoprism         | Failed  |
| Plex               | Success |
| podgrab            | Success |
| Prometheus         | Failed  |
| qBittorrent        | Success |
| Radarr             | Failed  |
| Readarr            | Failed  |
| sabnzb             | Success |
| tautulli           | Success |
| Transmission       | Sucesss |
| unpackerr          | Success |
| uptime-kuma        | Success |

