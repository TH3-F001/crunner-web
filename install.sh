#!/bin/bash

#region Ensure Client Certificate Was Provided
TRUSTED_CLIENT_CERT="$1"
if [ -z "$TRUSTED_CLIENT_CERT" ]; then
    echo "crunner-web requires a trusted client certificate in order to install."
    exit 1
fi
#endregion

#region Define Functions
export_json_vars() {
    local json_file=$1
    if [[ ! -f "$json_file" ]]; then
        echo "JSON file not found: $json_file"
        return 1
    fi

    while IFS="=" read -r key value; do
        export "$key=$value"
    done < <(jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]" "$json_file")
}

log() {
    local cmd=("$@")
    if [ ${#cmd[@]} -eq 0 ]; then
        echo "run requires command argument"
        return 1
    fi

    # Join array elements into a string separated by space, handling quotes properly
    local cmd_str="${cmd[@]}"
    printf -v joined_cmd '%q ' "${cmd[@]}"

    echo -e "\t\$log> $joined_cmd" | tee -a "$DEPLOYMENT_LOG" > /dev/null
    eval "$cmd_str" 2>&1 | tee -a "$DEPLOYMENT_LOG" || echo "[No_Output]" | tee -a "$DEPLOYMENT_LOG" > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "\tFailed" | tee -a "$DEPLOYMENT_LOG" > /dev/null
    else 
        echo -e "\tSuccess" | tee -a "$DEPLOYMENT_LOG" > /dev/null
    fi

}

is_valid_ip() {
    local ip=$1

    if ping -c 1 -W 1 "$ip" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

get_public_ip() {
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me"
        "https://ipinfo.io/ip"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
    )
    local pub_ip=""
    for service in "${services[@]}"; do
        pub_ip=$(curl -s $service)
        if [[ -n "$pub_ip" ]] && is_valid_ip "$pub_ip"; then
            break
        fi
    done
    echo "$pub_ip"
}

get_private_ip() {
    local interface=$1
    ip addr show $interface | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
}

replace_string_in_file() {
    local filepath=$1
    local old_string=$2
    local new_string=$3

    if [[ ! -f "$filepath" ]]; then
        echo "File not found: $filepath"
        return 1
    fi

    sudo sed -i "s/$old_string/$new_string/g" "$filepath"
}

#endregion

#region Initialize Log File
DEPLOYMENT_LOG=/var/log/crunner-deploy.log
sudo echo -e "\t\t[ Installing Crunner-Web Server... ]" | sudo tee $DEPLOYMENT_LOG
sudo chmod 777 $DEPLOYMENT_LOG
#endregion

#region Get Current Directories
echo -e "\nGetting Current Directories..." | tee -a "$DEPLOYMENT_LOG"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LIB_SCRIPT_DIR="$SCRIPT_DIR/libraries"
CRUNNER_SCRIPT_DIR="$SCRIPT_DIR/crunner"
APACHE_SCRIPT_DIR="$SCRIPT_DIR/apache"
#endregion

#region Get Public IP address
echo "Getting public IP address..." | tee -a $DEPLOYMENT_LOG
PUB_IP=$(get_public_ip)
echo "Public IP address is $PUB_IP." | tee -a $DEPLOYMENT_LOG
#endregion

#region Export from paths.json
echo -e "\nExporting Path Variables From paths.json..." | tee -a "$DEPLOYMENT_LOG"
export_json_vars "$CRUNNER_SCRIPT_DIR/instance/config/paths.json"
jq -r 'to_entries[] | "\(.key): \(.value)"' "$CRUNNER_SCRIPT_DIR/instance/config/paths.json" | while IFS=":" read -r key value; do
    echo "$key: $value" | tee -a "$DEPLOYMENT_LOG"
done
#endregion

#region Install Dependencies
echo -e "\nInstalling Dependencies..." | tee -a "$DEPLOYMENT_LOG"
source "$LIB_SCRIPT_DIR/deps.lib"
log sudo dnf install dnf-plugins-core -y
log sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
log sudo dnf update -y
for pkg in "${DEPENDENCIES[@]}"; do
    log sudo dnf install "$pkg" -y
done
#endregion

#region Create Flask User
#ToDo Lock down permissions more?
echo -e "\nCreating Flask User..." | tee -a "$DEPLOYMENT_LOG"
log sudo groupadd flask 
log sudo useradd -m -d "$CRUNNER_ROOT_DIR" -g flask flask
sudo chown -R flask:apache "$CRUNNER_ROOT_DIR"
sudo chmod -R 755 "$CRUNNER_ROOT_DIR"
log sudo chmod g+s "$CRUNNER_ROOT_DIR"
sudo rm -rf "$CRUNNER_ROOT_DIR/*"
#endregion

#region Put Files into their proper places
echo -e "\nCopying Project Files..." | tee -a "$DEPLOYMENT_LOG"

# Move uninstall.sh to /usr/local/bin
echo "Installing crunner-uninstall..." | tee -a "$DEPLOYMENT_LOG"
log sudo cp -v "$SCRIPT_DIR/uninstall.sh" /usr/local/bin/crunner-uninstall
log sudo chmod 751 /usr/local/bin/crunner-uninstall

# Move libraries to /usr/local/lib/crunner/
echo "Copying Library Files to /usr/local/lib/crunner..." | tee -a "$DEPLOYMENT_LOG"
if [ ! -z "$CRUNNER_LIB_DIR" ]; then
    log sudo mkdir -p "$CRUNNER_LIB_DIR"
    log sudo cp -v -r "$LIB_SCRIPT_DIR"/* "$CRUNNER_LIB_DIR"
    log sudo chown -R :flask "$CRUNNER_LIB_DIR"/*
    log sudo chmod -R 644 "$CRUNNER_LIB_DIR"/*
else
    echo "$CRUNNER_LIB_DIR doesnt exist!"
    read -p "paused" poop
    echo "$poop"
fi

# Move Apache configs to their proper places
echo "Adding Apache configuration files" | tee -a "$DEPLOYMENT_LOG"

# /etc/httpd/conf.d/ssl.conf
log sudo cp -v /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.bak
log sudo cp -v "$APACHE_SCRIPT_DIR/ssl.conf" /etc/httpd/conf.d/ssl.conf

# /etc/httpd/conf/httpd.conf
log sudo cp -v /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.bak
log sudo cp -v "$APACHE_SCRIPT_DIR/httpd.conf" /etc/httpd/conf/httpd.conf

# replace <SERVER_IP> placeholder in config files with actual IP

####################### DEVELOPMENT/DEBUG ONLY #######################
## Comment For Production
priv_ip=$(get_private_ip enp0s3)
replace_string_in_file /etc/httpd/conf.d/ssl.conf "<SERVER_IP>" "$priv_ip"
replace_string_in_file /etc/httpd/conf/httpd.conf "<SERVER_IP>" "$priv_ip"
######################################################################

# Uncomment for production
# replace_string_in_file /etc/httpd/conf.d/ssl.conf "<SERVER_IP>" "$PUB_IP"
# replace_string_in_file /etc/httpd/conf/httpd.conf "<SERVER_IP>" "$PUB_IP"

####################### DEVELOPMENT/DEBUG ONLY #######################
## Comment For Production
log sudo cp -v "$APACHE_SCRIPT_DIR/index.html" /var/www/html/
######################################################################

# Give apache ownership and rights to the web root directory
sudo chown -R apache:apache /var/www/html
sudo chmod -R 755 /var/www/
sudo restorecon -Rv /var/www/


# Move crunner files to /var/www/crunner
echo "Building server directory..." | tee -a "$DEPLOYMENT_LOG"
log sudo cp -v -r "$CRUNNER_SCRIPT_DIR"/* "$CRUNNER_ROOT_DIR"
log sudo chmod -R 750 "$CRUNNER_ROOT_DIR"
log sudo chown -R flask:flask "$CRUNNER_ROOT_DIR"

# Create /etc/crunner
echo "Creating /etc/crunner..." | tee -a "$DEPLOYMENT_LOG"
log sudo mkdir -p /etc/crunner
log sudo chown -R flask:flask /etc/crunner
log sudo chmod 700 /etc/crunner

#endregion

#ToDo OpenSSL Policies??
#region Set up PKI
echo -e "\nSetting Up PKI Files..." | tee -a $DEPLOYMENT_LOG

# Copy the trusted client certificate to /var/www/crunner/instance as a single line cert
echo "Placing trusted client certificate into $CLT_TRUSTED_CERT_FILE..." | tee -a $DEPLOYMENT_LOG
cat "$TRUSTED_CLIENT_CERT" | tr -d '\n' | sudo tee "$CLT_TRUSTED_CERT_FILE"
# log sudo cp -v "$TRUSTED_CLIENT_CERT" "$CLT_TRUSTED_CERT_FILE"
# Generate Web Server PKI

# Generate Private Key and certificate
echo "Generating Apache certificate and private key..." | tee -a "$DEPLOYMENT_LOG"

# [ DEVELOPMENT/DEBUG ONLY ] 
SRV_IP=$priv_ip

# [ Uncomment for production ]
# SRV_IP=$PUB_IP

sudo openssl req -x509 -newkey rsa:4096 -keyout "$SRV_HTTPS_PRIV_KEY_FILE" \
    -out "$SRV_HTTPS_CERT_FILE" -days 365 -nodes -extensions v3_req \
    -subj "/C=US/O=Cloud-Runner/CN=$SRV_IP" 
if [ $? -ne 0 ]; then
    echo "Error while generating Apache Cert/Key" | tee -a "$DEPLOYMENT_LOG"
fi


# Give proper ownership of cert and priv key
echo "Giving proper ownership of web PKI files..." | tee -a "$DEPLOYMENT_LOG"
log sudo chown apache:apache "$SRV_HTTPS_PRIV_KEY_FILE"
log sudo chown apache:apache "$SRV_HTTPS_CERT_FILE"
log sudo chown flask:flask "$CLT_TRUSTED_CERT_FILE"

# Restrict permissions of cert and priv key
echo "Restricting permissions for web PKI files" | tee -a "$DEPLOYMENT_LOG"
log sudo chmod 600 "$SRV_HTTPS_PRIV_KEY_FILE"
log sudo chmod 644 "$SRV_HTTPS_CERT_FILE"
log sudo chmod 600 "$CLT_TRUSTED_CERT_FILE"
#endregion

#region Generate Web-Access Encryption Key
echo -e "\nGenerating Web-Access Encryption Key..." | tee -a "$DEPLOYMENT_LOG"
openssl rand -base64 47 | sudo tee "$WEB_PASS_KEY_FILE" >/dev/null
log sudo chown flask:flask "$WEB_PASS_KEY_FILE"
log sudo chmod 400 "$WEB_PASS_KEY_FILE"
#endregion

#region Configure Firewall
echo -e "\nConfiguring Firewall and SELinux Rules..."

# Enable firewalld
echo  "Enabling Firwalld..." | tee -a "$DEPLOYMENT_LOG"
log sudo systemctl start firewalld
log sudo systemctl enable firewalld
sudo firewall-cmd --zone=public --change-interface=enp0s3 --permanent

#region Open Server Ports
echo "Opening Server Ports..." | tee -a "$DEPLOYMENT_LOG"

# Allow HTTP connections in SELinux
echo -e "Allowing inbound HTTP in SELinux..." | tee -a "$DEPLOYMENT_LOG"
sudo setsebool -P httpd_can_network_connect 1

####################### DEVELOPMENT/DEBUG ONLY #######################
echo -e "Opening inbound requests to port 5000 (Flask Development Server)..." | tee -a "$DEPLOYMENT_LOG"
log sudo firewall-cmd --zone=public --add-port=5000/tcp --permanent
sudo firewall-cmd --reload
######################################################################

# Open Apache HTTP server on port 80 (redirects to 443)
echo -e "Opening inbound requests to port 80 (Apache HTTP Server)..." | tee -a "$DEPLOYMENT_LOG"
log sudo firewall-cmd --zone=public --add-service=http --permanent
sudo firewall-cmd --reload

# Open Apache HTTPS server on port 443
echo -e "Opening inbound requests to port 443 (Apache HTTPS Server)..." | tee -a "$DEPLOYMENT_LOG"
log sudo firewall-cmd --zone=public --add-service=https --permanent
sudo firewall-cmd --reload

# Open SSH server on port 22
echo -e "Opening inbound requests to port 22 (OpenSSH Server)..." | tee -a "$DEPLOYMENT_LOG"
log sudo firewall-cmd --zone=public --add-service=ssh --permanent
sudo firewall-cmd --reload
log sudo setsebool -P sshd_port_t 1
#endregion

# Reload Firewall 
echo -e "Reloading Firewall..." | tee -a "$DEPLOYMENT_LOG"
log sudo firewall-cmd --reload
#endregion

#region create a virtual environment for flask and install python dependencies
echo -e "\nCreating Virtual Environment..." | tee -a "$DEPLOYMENT_LOG"
log sudo -u flask python3 -m venv "$CRUNNER_ROOT_DIR"/venv
log sudo -u flask "$CRUNNER_ROOT_DIR"/venv/bin/python3 -m pip install --upgrade pip
log sudo -u flask "$CRUNNER_ROOT_DIR"/venv/bin/pip install Flask
log sudo -u flask "$CRUNNER_ROOT_DIR"/venv/bin/pip install mod_wsgi
log sudo -u flask "$CRUNNER_ROOT_DIR"/venv/bin/pip install flask-login

# Give apache and flask the proper permissions to the virtual environment
echo -e "Giving the virtual environment the proper permissions..." | tee -a "$DEPLOYMENT_LOG"
sudo setfacl -R -m u:apache:rX /var/www/crunner
sudo setfacl -R -m u:flask:rwX /var/www/crunner
sudo chcon -R -t httpd_sys_script_exec_t /var/www/crunner

#endregion

#region Ensure time and date is synced
echo -e "\nSyncing time and date..." | tee -a "$DEPLOYMENT_LOG"
sudo systemctl enable --now systemd-timesyncd
sudo timedatectl set-ntp true
#endregion

#region Enable Web Services
echo -e "\nEnabling Web Services..." | tee -a "$DEPLOYMENT_LOG"

# Enable Apache web server
echo -e "\nEnabling Apache web server..." | tee -a "$DEPLOYMENT_LOG"
log sudo systemctl enable httpd
log sudo systemctl start httpd
#endregion

#region Enable SSH Server
echo -e "\nEnabling SSH ..." | tee -a "$DEPLOYMENT_LOG"
log sudo systemctl enable sshd
log sudo systemctl restart sshd
log sudo systemctl start sshd
#endregion

#region Lock Deployment Log
echo -e "Locking Deployment Log..." | tee -a "$DEPLOYMENT_LOG"
sudo chmod 644 $DEPLOYMENT_LOG
#endregion

# crunner/install.sh crunner/test_assets/trusted_test.crt