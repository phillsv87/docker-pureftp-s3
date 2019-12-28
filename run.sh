#!/bin/bash

# Based on - https://raw.githubusercontent.com/stilliard/docker-pure-ftpd/hardened/run.sh

# Check for S3 vars

if [ -z "$S3_BUCKET_NAME" ]; then
    echo 'S3_BUCKET_NAME enviornment variable required'
    exit 1
fi
if [ ! -f "$S3_PASSWD_FILE" ]; then
    echo "S3_PASSWD_FILE does not exist - path = $S3_PASSWD_FILE"
    exit 1
fi
# end

# S3 mount
s3passdir='/4ffe9907-6607-458a-8d90-4d57fce59299'
mkdir "$s3passdir"
s3passfile="$s3passdir/9b1bde7a-b1cc-4f84-841c-6e7a1417bf85"
cp "$S3_PASSWD_FILE"  "$s3passfile"
chmod 600 "$s3passfile"

echo 'Starting s3fs'
if [ ! -d "$S3_MOUNT_PATH" ]; then
    echo "Create mount point path - $S3_MOUNT_PATH"
    mkdir -p "$S3_MOUNT_PATH"
fi
echo "Mount bucket '$S3_BUCKET_NAME' at '$S3_MOUNT_PATH'"
s3fs "$S3_BUCKET_NAME" "$S3_MOUNT_PATH" -o passwd_file="$s3passfile" -o nonempty -o allow_other
if [ "$?" != "0" ]; then
    rm -rf "$s3passdir"
    echo "Mount bucket '$S3_BUCKET_NAME' at '$S3_MOUNT_PATH' failed"
    exit 1
fi

if [ ! -f "$PURE_PASSWDFILE" ]; then
    echo "Touch $PURE_PASSWDFILE"
    mkdir -p "$(dirname $PURE_PASSWDFILE)"
    touch "$PURE_PASSWDFILE"
fi

rm -rf "$s3passdir"
# end

# build up flags passed to this file on run + env flag for additional flags
# e.g. -e "ADDED_FLAGS=--tls=2"
PURE_FTPD_FLAGS=" $@ $ADDED_FLAGS "

# start rsyslog
if [[ "$PURE_FTPD_FLAGS" == *" -d "* ]] || [[ "$PURE_FTPD_FLAGS" == *"--verboselog"* ]]
then
    echo "Log enabled, see /var/log/messages"
    rsyslogd
fi

PASSWD_FILE="$PURE_PASSWDFILE"

# Load in any existing db from volume store
if [ -e "$PURE_PASSWDFILE" ]
then
    pure-pw mkdb /etc/pure-ftpd/pureftpd.pdb -f "$PASSWD_FILE"
fi

# detect if using TLS (from volumed in file) but no flag set, set one
if [ -e /etc/ssl/private/pure-ftpd.pem ] && [[ "$PURE_FTPD_FLAGS" != *"--tls"* ]]
then
    echo "TLS Enabled"
    PURE_FTPD_FLAGS="$PURE_FTPD_FLAGS --tls=1 "
fi

# If TLS flag is set and no certificate exists, generate it
if [ ! -e /etc/ssl/private/pure-ftpd.pem ] && [[ "$PURE_FTPD_FLAGS" == *"--tls"* ]] && [ ! -z "$TLS_CN" ] && [ ! -z "$TLS_ORG" ] && [ ! -z "$TLS_C" ]
then
    echo "Generating self-signed certificate"
    mkdir -p /etc/ssl/private
    if [[ "$TLS_USE_DSAPRAM" == "true" ]]; then
        openssl dhparam -dsaparam -out /etc/ssl/private/pure-ftpd-dhparams.pem 2048
    else
        openssl dhparam -out /etc/ssl/private/pure-ftpd-dhparams.pem 2048
    fi
    openssl req -subj "/CN=${TLS_CN}/O=${TLS_ORG}/C=${TLS_C}" -days 1826 \
        -x509 -nodes -newkey rsa:2048 -sha256 -keyout \
        /etc/ssl/private/pure-ftpd.pem \
        -out /etc/ssl/private/pure-ftpd.pem
    chmod 600 /etc/ssl/private/*.pem
fi

# Add user
if [ ! -z "$FTP_USER_NAME" ] && [ ! -z "$FTP_USER_PASS" ] && [ ! -z "$FTP_USER_HOME" ]
then
    echo "Creating user..."

    # make sure the home folder exists
    mkdir -p "$FTP_USER_HOME"

    # Generate the file that will be used to inject in the password prompt stdin
    PWD_FILE="$(mktemp)"
    echo "$FTP_USER_PASS
$FTP_USER_PASS" > "$PWD_FILE"
    
    # Set uid/gid
    PURE_PW_ADD_FLAGS=""
    if [ ! -z "$FTP_USER_UID" ]
    then
        PURE_PW_ADD_FLAGS="$PURE_PW_ADD_FLAGS -u $FTP_USER_UID"
    else
        PURE_PW_ADD_FLAGS="$PURE_PW_ADD_FLAGS -u ftpuser"
    fi
    if [ ! -z "$FTP_USER_GID" ]
    then
        PURE_PW_ADD_FLAGS="$PURE_PW_ADD_FLAGS -g $FTP_USER_GID"
    fi

    pure-pw useradd "$FTP_USER_NAME" -f "$PASSWD_FILE" -m -d "$FTP_USER_HOME" $PURE_PW_ADD_FLAGS < "$PWD_FILE"

    if [ ! -z "$FTP_USER_HOME_PERMISSION" ]
    then
        chmod "$FTP_USER_HOME_PERMISSION" "$FTP_USER_HOME"
        echo " root user give $FTP_USER_NAME ftp user at $FTP_USER_HOME directory has $FTP_USER_HOME_PERMISSION permission"
    fi

    if [ ! -z "$FTP_USER_UID" ]
    then
        if ! [[ $(ls -ldn $FTP_USER_HOME | awk '{print $3}') = $FTP_USER_UID ]]
        then
            chown $FTP_USER_UID "$FTP_USER_HOME"
            echo " root user give $FTP_USER_HOME directory $FTP_USER_UID owner"
        fi
    else
        if ! [[ $(ls -ld $FTP_USER_HOME | awk '{print $3}') = 'ftpuser' ]]
        then
            chown ftpuser "$FTP_USER_HOME"
            echo " root user give $FTP_USER_HOME directory ftpuser owner"
        fi
    fi

    rm "$PWD_FILE"
fi

# Set a default value to the env var FTP_PASSIVE_PORTS
if [ -z "$FTP_PASSIVE_PORTS" ]
then
    FTP_PASSIVE_PORTS=30000:30009
fi

# Set passive port range in pure-ftpd options if not already existent
if [[ $PURE_FTPD_FLAGS != *" -p "* ]]
then
    echo "Setting default port range to: $FTP_PASSIVE_PORTS"
    PURE_FTPD_FLAGS="$PURE_FTPD_FLAGS -p $FTP_PASSIVE_PORTS"
fi

# Set a default value to the env var FTP_MAX_CLIENTS
if [ -z "$FTP_MAX_CLIENTS" ]
then
    FTP_MAX_CLIENTS=5
fi

# Set max clients in pure-ftpd options if not already existent
if [[ $PURE_FTPD_FLAGS != *" -c "* ]]
then
    echo "Setting default max clients to: $FTP_MAX_CLIENTS"
    PURE_FTPD_FLAGS="$PURE_FTPD_FLAGS -c $FTP_MAX_CLIENTS"
fi

# Set a default value to the env var FTP_MAX_CONNECTIONS
if [ -z "$FTP_MAX_CONNECTIONS" ]
then
    FTP_MAX_CONNECTIONS=5
fi

# Set max connections per ip in pure-ftpd options if not already existent
if [[ $PURE_FTPD_FLAGS != *" -C "* ]]
then
    echo "Setting default max connections per ip to: $FTP_MAX_CONNECTIONS"
    PURE_FTPD_FLAGS="$PURE_FTPD_FLAGS -C $FTP_MAX_CONNECTIONS"
fi


# let users know what flags we've ended with (useful for debug)
echo "Starting Pure-FTPd:"
echo "  pure-ftpd $PURE_FTPD_FLAGS"

# start pureftpd with requested flags
exec /usr/sbin/pure-ftpd $PURE_FTPD_FLAGS
