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

It also will not work on some of the arrs at the moment, since some of them are migrating to a new database. 

Trucharts may change the way they handle databases for the arr apps in the future, so this script may end up working on those at some point.

> A workaround for the arr apps moving to the new db is to use the `Custom-app` template from trucharts, and migrate to that instead. Which obviously will not end up using the new db. I did this for prowlarr, and it worked fine, just make sure the name is the same as the old app.


## Tested on

| Application        | Status  |
|--------------------|---------|
| adguard-home       | Success |
| autoscan           | Success |
| bazarr             | Success |
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
| mymediaforalexa    | Success |
| mysql-workbench    | Success |
| organizr           | Success |
| overseerr          | Success |
| phpldapadmin       | Success |
| photoprism         | Failed  |
| plex               | Success |
| podgrab            | Success |
| Prometheus         | Failed  |
| prowlarr           | Failed  |
| qBittorrent        | Success |
| radarr             | Failed  |
| readarr            | Failed  |
| sabnzb             | Success |
| sonarr             | Success |
| tautulli           | Success |
| transmission       | Success |
| unpackerr          | Success |
| uptime-kuma        | Success |

