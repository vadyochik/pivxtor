#!/bin/sh

set -o nounset

usage() { local RC="${1:-0}"
    echo "Script for backing up PIVX wallet.dat and other important files.

Usage: ${0##*/} [COMMAND]

The following commands are available:
    help        This help
    shell       Run /bin/sh instead of this backup script
    all         Sets the following files to be included in the archive:
                wallet.dat backups/ pivx.conf masternode.conf
    wallet      Sets only wallet.dat file to be included in the archive
    backups     Sets only backups/ folder to be included in the archive
    config      Sets only pivx.conf file to be included in the archive
    masternode  Sets only masternode.conf file to be included in the archive

If no COMMAND provided, "help" command is assumed
" >&2
    exit $RC
}

COMMAND="${1:-help}"

case "$COMMAND" in 
    all) IMPORTANT_DATA="wallet.dat backups pivx.conf masternode.conf" ;;
    wallet) IMPORTANT_DATA="wallet.dat" ;;
    backups) IMPORTANT_DATA="backups" ;;
    config) IMPORTANT_DATA="pivx.conf" ;;
    masternode) IMPORTANT_DATA="masternode.conf" ;;
    shell) exec /bin/sh ;;
    help) usage ;;
    *) echo "Unknown command: $COMMAND"; echo; usage 1 ;;
esac

if [ ! -d /pivxdata ]; then
    echo "ERROR: /pivxdata folder cannot be found.."
    echo
    echo "Please make sure you mounted PIVX data volume as /pivxdata when running a container from this image"
    exit 1
fi

if [ ! -d /pivxbackup ]; then
    echo "ERROR: /pivxbackup folder cannot be found.."
    echo
    echo "Please make sure you mounted your backup folder as /pivxbackup when running a container from this image"
    exit 1
fi

if [ -e /pivxdata/${IMPORTANT_DATA// */} ]; then
    echo "Creating backups of ${IMPORTANT_DATA}"
    tar -C /pivxdata -cvzf /pivxbackup/pivx_${COMMAND}_backup-$(date +%Y%m%d_%H%M%S).tar.gz ${IMPORTANT_DATA}
else
    echo "No ${IMPORTANT_DATA// */} found under /pivxdata folder.. There seems nothing to backup yet.."
fi

