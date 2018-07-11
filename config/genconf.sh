#!/bin/sh

set -o nounset

usage() { local RC="${1:-0}"
    echo "Script for generating PIVX and TOR configuration files based on environment variables.

Usage: ${0##*/} [COMMAND]

The following commands are available:
    help        This help
    shell       Run /bin/sh instead of this script
    generate    Generate PIVX and TOR configuration files
    check       Check PIVX and TOR current configuration files

If no COMMAND provided, "help" command is assumed
" >&2
    exit $RC
}

check_configuration() {
    echo '>>> Checking configuration files..'
    if [ -s /tordata/torrc ]; then
        echo '** Current torrc file:'
        cat /tordata/torrc
    else
        echo '** No valid torrc file found!'
        echo 'Please run config service first:'
        echo
        echo '    docker-compose -f docker-compose.yml -f docker-compose.admin.yml run config generate'
        echo
        exit 1
    fi
    if [ -s /pivxdata/pivx.conf ]; then
        echo '** Current pivx.conf file:'
        cat /pivxdata/pivx.conf
    else
        echo '** No valid pivx.conf file found!'
        echo 'Please run config service first:'
        echo
        echo '    docker-compose -f docker-compose.yml -f docker-compose.admin.yml run config generate'
        echo
        exit 1
    fi
    if [ "${PIVX_ONION_HIDDEN_SERVICE:-NO}" = "YES" ]; then
        echo -n '** Current hidden service hostname: '
        cat /tordata/hidden_service/hostname
    fi
    echo '** Verify the configuration file is valid: '
    su tor -s /bin/sh -c "tor --verify-config -f /tordata/torrc"
    exit $?
}

generate_torrc() {
    echo '>>> Generating torrc file..'
    if [ "$PIVX_ONLYNET" = "tor" ]; then
        echo "SOCKSPort $TOR_ISOLATED_IP:9050 OnionTrafficOnly" | tee /tordata/torrc
    else
        echo "SOCKSPort $TOR_ISOLATED_IP:9050" | tee /tordata/torrc
    fi
    echo "Log ${TOR_LOG_LEVEL:-notice} stderr" | tee -a /tordata/torrc
    echo "DataDirectory /var/lib/tor" | tee -a /tordata/torrc
    if [ "${PIVX_ONION_HIDDEN_SERVICE:-NO}" = "YES" ]; then
        #TOR_CONTROL_PASSWORD="$(tr -dc a-zA-Z0-9 < /dev/urandom | head -c44)"
        #TOR_CONTROL_PASSWORD_HASHED="$(tor --hash-password $TOR_CONTROL_PASSWORD | tail -n 1)"
        #echo "ControlPort $TOR_ISOLATED_IP:9051" | tee -a /tordata/torrc
        #echo "HashedControlPassword $TOR_CONTROL_PASSWORD_HASHED" | tee -a /tordata/torrc
        echo "HiddenServiceDir /var/lib/tor/hidden_service/" | tee -a /tordata/torrc
        echo "HiddenServicePort 51472 $PIVX_ISOLATED_IP:51472" | tee -a /tordata/torrc
    fi
}

generate_pivxconf() {
    echo '>>> Generating pivx.conf file..'
    echo "proxy=$TOR_ISOLATED_IP:9050" | tee /pivxdata/pivx.conf
    echo "dns=0" | tee -a /pivxdata/pivx.conf
    if [ -n "$PIVX_ONLYNET" ]; then
        for net in $PIVX_ONLYNET; do
            echo "onlynet=$net" | tee -a /pivxdata/pivx.conf
        done
        if [ "$PIVX_ONLYNET" = "tor" ]; then
            echo "dnsseed=0" | tee -a /pivxdata/pivx.conf
        fi
    fi
    if [ "${PIVX_ONION_HIDDEN_SERVICE:-NO}" = "YES" ]; then
        echo "listenonion=0" | tee -a /pivxdata/pivx.conf
        echo "listen=1" | tee -a /pivxdata/pivx.conf
        echo "externalip=$(cat /tordata/hidden_service/hostname)" | tee -a /pivxdata/pivx.conf
    fi
    if [ "${PIVX_ZPIV_AUTOMINT:-NO}" = "YES" ]; then
        echo "enablezeromint=1" | tee -a /pivxdata/pivx.conf
    else
        echo "enablezeromint=0" | tee -a /pivxdata/pivx.conf
    fi
    if [ -n "${PIVX_DEBUG:-}" ]; then
        echo "debug=$PIVX_DEBUG" | tee -a /pivxdata/pivx.conf
    fi
}

set_perms_tor() {
    echo '>>> Resetting permissions for TOR..'
    chmod -v 0700 /tordata
    chown -v tor:root /tordata
}

set_perms_pivx() {
    echo '>>> Resetting permissions for PIVX..'
    chmod -v 0700 /pivxdata
    chown -v $PIVX_UID:root /pivxdata
}

generate_hidden_service_private_key() {
    echo '>>> Generating hidden service private_key'
    echo -n '** Previous hidden service hostname: '
    if [ -f /tordata/hidden_service/hostname ]; then
        cat /tordata/hidden_service/hostname
    else
        echo "NOT AVAILABLE"
    fi
    su tor -s /bin/sh -c "/usr/bin/tor --RunAsDaemon 1 --DisableNetwork 1 --DataDirectory /var/lib/tor --HiddenServiceDir /tordata/hidden_service/ --HiddenServicePort 51472"
    sleep 3
    killall tor
    echo -n '** Current hidden service hostname: '
    cat /tordata/hidden_service/hostname
}

COMMAND="${1:-help}"

case "$COMMAND" in 
    shell) exec /bin/sh ;;
    help) usage ;;
    generate) echo "==> Trying to run config generation routines now.." ;;
    check) echo "==> Running in check-only mode.."; check_configuration ;;
    *) echo "Unknown command: $COMMAND"; echo; usage 1 ;;
esac

if [ ! -d /tordata ]; then
    echo "ERROR: /tordata folder cannot be found.."
    echo
    echo "Please make sure you mounted TOR data folder as /tordata when running a container from this image"
    exit 1
fi

if [ ! -d /pivxdata ]; then
    echo "ERROR: /pivxdata folder cannot be found.."
    echo
    echo "Please make sure you mounted PIVX data volume as /pivxdata when running a container from this image"
    exit 1
fi

if [ -s /tordata/torrc ]; then
    echo "File torrc is already existing and has size greater than zero."
    if [ "${TOR_CONFIG_REGENERATE:-NO}" = "YES" ]; then
        echo "But we are going to regenerate it from scratch!"
        generate_torrc
    else
        echo "And we are not going to regenerate it.."
    fi
else
    generate_torrc
fi

set_perms_tor

if [ "${PIVX_ONION_HIDDEN_SERVICE:-NO}" = "YES" ]; then
    if grep -qsF -- '-----BEGIN RSA PRIVATE KEY-----' /tordata/hidden_service/private_key; then
        echo "Hidden service private_key is already there."
        if [ "${PIVX_ONION_HIDDEN_SERVICE_REGENERATE:-NO}" = "YES" ]; then
            echo "But we are going to regenerate it anyway!"
            rm /tordata/hidden_service/private_key
            generate_hidden_service_private_key
        fi
    else
        rm -f /tordata/hidden_service/private_key
        generate_hidden_service_private_key
    fi
fi

if [ -s /pivxdata/pivx.conf ]; then
    echo "File pivx.conf is already existing and has size greater than zero."
    if [ "${PIVX_CONFIG_REGENERATE:-NO}" = "YES" ]; then
        echo "But we are going to regenerate it from scratch!"
        generate_pivxconf
    else
        echo "And we are not going to regenerate it.."
    fi
else
    generate_pivxconf
fi

set_perms_pivx
