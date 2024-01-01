#!/bin/bash
# <UDF name="WEB_PASS" label="Web Access Password" example="Enter the web page password" />


#region Setup Initial Requirments

# Generate Dummy Password if not running as a stackscript (testing)
if [ -z "$WEB_PASS" ]; then
    WEB_PASS="$(echo dummypass | sha256sum | cut -d ' ' -f1)"
fi

# Initialize Log
DEPLOYMENT_LOG=/var/log/crunner-deploy.log
sudo echo "" | sudo tee $DEPLOYMENT_LOG > /dev/null


#region Environment Variables

#Initialize /etc/profile.d/crunnervars.sh
VAR_PROFILE=/etc/profile.d/crunnervars.sh
echo "" | sudo tee $VAR_PROFILE
sudo chmod 755 $VAR_PROFILE

# Create environment variables
declare -A ENV_VARS=(
    ["ROOT_DIR"]="/root/.crunner"
    ["VINCE"]="/root/.crunner/vince.txt"
    ["ZOOL"]="/root/.crunner/zool.txt"
    ["FLASK_ROOT"]="/srv/flask"
    ["HTTPS_PRIV_KEY"]="/etc/pki/tls/private/crunner.key"
    ["HTTPS_CERT"]="/etc/pki/tls/certs/crunner.crt"
    ["CRUNNER_ROOT"]="/var/www/crunner"
)

# Save Environment Variables to $VAR_PROFILE
for var in "${!ENV_VARS[@]}"; do
    if ! grep -Fxq "export $var=${ENV_VARS[$var]}" "$VAR_PROFILE"; then
        echo "export $var=${ENV_VARS[$var]}" | sudo tee -a "$VAR_PROFILE" > /dev/null
        export "$var"="${ENV_VARS[$var]}"
    fi
done


# Append "source $VAR_PROFILE to .bashrc and profile if it isnt already there"
if ! grep -Fxq "source $VAR_PROFILE" /home/"$(whoami)"/.bashrc; then
    echo "source $VAR_PROFILE" >> /home/"$(whoami)"/.bashrc
fi

# Append "source $VAR_PROFILE to /etc/profile if it isnt already there"
if ! grep -Fxq "source $VAR_PROFILE" /etc/profile; then
    echo "source $VAR_PROFILE" >> /etc/profile
fi
#endregion


#region Install Dependencies
sudo dnf install dnf-plugins-core -y
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf update -y

declare -a DEPENDENCIES=("httpd" "mod_ssl" "python3-mod_wsgi" "fail2ban" "openssl" "docker-ce" \
    "mod_wsgi" "docker-ce-cli" "containerd.io" "docker-buildx-plugin" "docker-compose-plugin" \
    "python3-pip"
)

for pkg in "${DEPENDENCIES[@]}"; do
    sudo dnf install -y "$pkg"
done
#endregion


#region Script Functions
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
#encregion

#endregion

#endregion


#region User Setup

# Create Flask User
# ToDo: configure the flask systemd service to run using the flask user 
echo -e "Creating the Flask User..." | sudo tee -a $DEPLOYMENT_LOG  
log sudo groupadd flask 
log sudo useradd -m -d /srv/flask -g flask flask
log sudo chown flask:flask /srv/flask
log sudo chmod 750 /srv/flask 
log sudo chmod g+s /srv/flask
#endregion


#region Encrypt User Supplied Password


# Create required directories
log sudo mkdir -p "$FLASK_ROOT"/secure
log sudo mkdir -p "$ROOT_DIR"
log openssl rand -base64 32 | sudo tee $VINCE > /dev/null
log sudo chmod 650 $VINCE
log sudo chown :flask $VINCE

# Encrypt user supplied password hash
echo "$WEB_PASS" | sudo openssl enc -aes-256-cbc -salt -pbkdf2 -iter 10000 -pass file:"$VINCE" -out "$ZOOL"
log sudo chmod 650 $ZOOL
log sudo chown :flask $ZOOL
#endregion


#region Set Up Web App



#region Generate TLS key and self-signed certificate
PUB_IP=$(get_public_ip)
sudo openssl ecparam -genkey -name secp384r1 -out "$HTTPS_PRIV_KEY"
sudo openssl req -new -x509 -sha256 -key "$HTTPS_PRIV_KEY" -out "$HTTPS_CERT" -days 365\
    -subj "/C=US/O=Cloud-Runner/CN=$PUB_IP"
sudo chmod 600 "$HTTPS_PRIV_KEY"
sudo chmod 644 "$HTTPS_CERT"
#endregion

#region Set up Flask
mkdir -p "$CRUNNER_ROOT"
pip3 install Flask


# Open Web Server ports in firewall and SELinux
sudo fire
#endregion

 
