#!/bin/bash

username=$1
userdir="$S3_USERS_DIR/$username"

if ! [[ $username =~ ^[0-9a-zA-Z_-]+$ ]]; then
    echo 'Invalid username. Only 0-9a-zA-Z_- characters are allowed'
    exit 1
fi

if [ -d "$userdir" ]; then
    echo "User $username already exists"
    exit 1
fi


mkdir -p $userdir
chown -R ftpuser:ftpgroup $userdir
pure-pw useradd $username -u ftpuser -d $userdir
pure-pw mkdb