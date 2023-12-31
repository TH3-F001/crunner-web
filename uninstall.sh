#!/bin/bash

# This script is really just meant for development purposes

# region User Removal

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