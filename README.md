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

The script will check to see if these databases exist prior to accepting them for migration, but I include a list down below anyway, for verification.

## Tested on

| Application        | Status  |
|--------------------|---------|
| adguard-home       | Success |
| audiobookshelf     | Success |
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
| mkvcleaver         | Success |
| mymediaforalexa    | Success |
| mysql-workbench    | Success |
| organizr           | Success |
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

