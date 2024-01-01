#!/bin/bash

# This script is really just meant for development purposes

# Get the current directory and script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LIB_SCRIPT_DIR="$SCRIPT_DIR/libraries"


# Remove Flask User
sudo userdel -r flask
sudo groupdel flask
sudo rm -rf /srv/flask
sudo rm -rf /root/.crunner/

# Uninstall Dependencies


declare -a DEPENDENCIES=("httpd" "fail2ban" "openssl" "docker-ce" \
                         "docker-ce-cli" "containerd.io" "docker-buildx-plugin" "docker-compose-plugin")

for pkg in "${DEPENDENCIES[@]}"; do
    sudo dnf remove -y "$pkg"
done