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

    echo "\$log> $joined_cmd" | sudo tee -a "$DEPLOYMENT_LOG" > /dev/null
    eval "$cmd_str" 2>&1 | sudo tee -a "$DEPLOYMENT_LOG" || echo "[No_Output]" | sudo tee -a "$DEPLOYMENT_LOG" > /dev/null
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
#endregion

#region Initialize Log File
DEPLOYMENT_LOG=/var/log/crunner-deploy.log
sudo echo -e "\t\t[ Installing Crunner-Web Server... ]" | sudo tee $DEPLOYMENT_LOG

#endregion

#region Get Current Directories
echo -e "\nGetting Current Directories..." | sudo tee -a "$DEPLOYMENT_LOG"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LIB_SCRIPT_DIR="$SCRIPT_DIR/libraries"
CRUNNER_SCRIPT_DIR="$SCRIPT_DIR/crunner"
#endregion

#region Export from paths.json
echo -e "\nExporting Path Variables From paths.json..." | sudo tee -a "$DEPLOYMENT_LOG"
log export_json_vars "$CRUNNER_SCRIPT_DIR/instance/config/paths.json"
#endregion

#region Install Dependencies
echo -e "\nInstalling Dependencies..." | sudo tee -a "$DEPLOYMENT_LOG"
source "$LIB_SCRIPT_DIR/deps.lib"
log sudo dnf install dnf-plugins-core -y
log sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
log sudo dnf update -y
for pkg in "${DEPENDENCIES[@]}"; do
    log sudo dnf install "$pkg" -y
done
#endregion

#region Create Flask User
echo -e "\nCreating Flask User..." | sudo tee -a "$DEPLOYMENT_LOG"
log sudo groupadd flask 
log sudo useradd -m -d "$CRUNNER_ROOT_DIR" -g flask flask
log sudo chown flask:flask "$CRUNNER_ROOT_DIR"
log sudo chmod 750 "$CRUNNER_ROOT_DIR" 
log sudo chmod g+s "$CRUNNER_ROOT_DIR"
#endregion

#region Put Files to their proper places
echo -e "\nCopying Project Files..." | sudo tee -a "$DEPLOYMENT_LOG"

# Move uninstall.sh to /usr/local/bin
echo "Installing crunner-uninstall..." | sudo tee -a "$DEPLOYMENT_LOG"
log sudo cp "$SCRIPT_DIR/uninstall.sh" /usr/local/bin/crunner-uninstall
log sudo chmod 751 /usr/local/bin/crunner-uninstall

# Move libraries to /usr/local/lib/crunner/
echo "Copying Library Files to /usr/local/lib/crunner..." | sudo tee -a "$DEPLOYMENT_LOG"
if [ ! -z "$CRUNNER_LIB_DIR" ]; then
    log sudo mkdir -p "$CRUNNER_LIB_DIR"
    log sudo cp -r "$LIB_SCRIPT_DIR"/* "$CRUNNER_LIB_DIR"
    log sudo chown -R :flask "$CRUNNER_LIB_DIR"/*
    log sudo chmod -R 644 "$CRUNNER_LIB_DIR"/*
else
    echo "$CRUNNER_LIB_DIR doesnt exist!"
    read -p "paused" poop
    echo "$poop"
fi


# Move crunner files to /var/www/crunner
echo "Building Server Directory..." | sudo tee -a "$DEPLOYMENT_LOG"
log sudo cp -r "$CRUNNER_SCRIPT_DIR"/* "$CRUNNER_ROOT_DIR"
log sudo chmod -R 750 "$CRUNNER_ROOT_DIR"/*
log sudo chown -R flask:flask "$CRUNNER_ROOT_DIR"/*

# Create /etc/crunner
echo "Creating /etc/crunner..." | sudo tee -a "$DEPLOYMENT_LOG"
log sudo mkdir -p /etc/crunner
log sudo chown -R flask:flask /etc/crunner
log sudo chmod 700 /etc/crunner
#endregion

#region Set up PKI
echo -e "\nSetting Up PKI Files..." | sudo tee -a $DEPLOYMENT_LOG

# Copy the trusted client certificate to /var/www/crunner/instance
echo "Placing trusted client certificate into $TRUSTED_CLIENT_CERT_FILE..." | sudo tee -a $DEPLOYMENT_LOG
echo "$TRUSTED_CLIENT_CERT" | sudo tee "$TRUSTED_CLIENT_CERT_FILE" >/dev/null

# Get Public IP address
echo "Getting public IP address..." | sudo tee -a $DEPLOYMENT_LOG
PUB_IP=$(get_public_ip)
echo "Public IP address is $PUB_IP." | sudo tee -a $DEPLOYMENT_LOG

# Generate Web Server PKI
    # Generate Private Key
echo "Generating web server key..." | sudo tee -a "$DEPLOYMENT_LOG"
sudo openssl ecparam -genkey -name secp521r1 -out "$SRV_HTTPS_PRIV_KEY_FILE" 2>>"$DEPLOYMENT_LOG"
if [ $? -ne 0 ]; then
    echo "Error generating private key" | sudo tee -a "$DEPLOYMENT_LOG"
fi

    # Generate Certificate
echo "Generating web server certificate..." | sudo tee -a "$DEPLOYMENT_LOG"
sudo openssl req -new -x509 -sha512 -key "$SRV_HTTPS_PRIV_KEY_FILE" -out "$SRV_HTTPS_CERT_FILE" -days 365 \
    -subj "/C=US/O=Cloud-Runner/CN=$PUB_IP" 2>>"$DEPLOYMENT_LOG"
if [ $? -ne 0 ]; then
    echo "Error generating certificate" | sudo tee -a "$DEPLOYMENT_LOG"
fi

# Give flask ownership of cert and priv key
echo "Giving flask ownership of web PKI files..." | sudo tee -a "$DEPLOYMENT_LOG"
log sudo chown flask:flask "$SRV_HTTPS_PRIV_KEY_FILE"
log sudo chown flask:flask "$SRV_HTTPS_CERT_FILE"
log sudo chown flask:flask "$TRUSTED_CLIENT_CERT_FILE"

# Restrict permissions of cert and priv key
echo "Restricting permissions for web PKI files" | sudo tee -a "$DEPLOYMENT_LOG"
log sudo chmod 600 "$SRV_HTTPS_PRIV_KEY_FILE"
log sudo chmod 644 "$SRV_HTTPS_CERT_FILE"
log sudo chmod 600 "$TRUSTED_CLIENT_CERT_FILE"
#endregion

#region Generate Web-Access Encryption Key
echo -e "\nGenerating Web-Access Encryption Key..." | sudo tee -a "$DEPLOYMENT_LOG"
openssl rand -base64 47 | sudo tee "$WEB_PASS_KEY_FILE"
log sudo chown flask:flask "$WEB_PASS_KEY_FILE"
log sudo chmod 400 "$WEB_PASS_KEY_FILE"
#endregion
