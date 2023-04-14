# Migration Script for PVCs

This script is designed to assist with the migration of Persistent Volume Claims (PVCs) between TrueCharts latest common refactor

It follows the steps outlined in this guide: https://docs.dasnipe.com/docs/truenas/Fast-Reinstall

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

### Success
filebrowser

All my custom-app Apps 

Komga 

emulatorjs

homarr

freshrss

mysql-workbench

bazarr

flaresolverr

phpldapadmin

podgrab

sabnzb

uptime-kuma

unpackerr

autoscan

tautulli

overseerr

code-server

Jellyseerr

adguard-home

### Failed

photoprism

Prometheus