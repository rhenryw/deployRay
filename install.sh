#!/bin/bash
# Usage: curl -fsSL https://raw.githubusercontent.com/rhenryw/deployRay/main/install.sh | bash -s yourdomain.tld [-c] [--port 8080]

set -e

cat <<'BANNER'
  _____             _             _____             
 |  __ \           | |           |  __ \            
 | |  | | ___ _ __ | | ___  _   _| |__) |__ _ _   _ 
 | |  | |/ _ \ '_ \| |/ _ \| | | |  _  // _` | | | |
 | |__| |  __/ |_) | | (_) | |_| | | \ \ (_| | |_| |
 |_____/ \___| .__/|_|\___/ \__, |_|  \_\__,_|\__, |
             | |             __/ |             __/ |
             |_|            |___/             |___/  v 1.65
                                          
 by: RHW
BANNER


SSL_ENABLED=false
DOMAIN=""
LISTEN_PORT=10000
WS_PATH="/ray"
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)


while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c) SSL_ENABLED=true ;;
        --port|-p) LISTEN_PORT="$2"; shift ;;
        *) if [[ -z "$DOMAIN" ]]; then DOMAIN=$1; fi ;;
    esac
    shift
done

if [ -z "$DOMAIN" ]; then
    echo "Error: Domain not provided."
    echo "Usage: bash install.sh yourdomain.tld [-c] [--port 8080]"
    exit 1
fi


echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y curl git nginx openssl jq unzip nodejs npm
sudo npm install -g pm2


echo "Setting up Xray-core..."
mkdir -p ~/xray && cd ~/xray
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/${latest_version}/Xray-linux-64.zip"
unzip -o xray.zip && chmod +x xray


cat <<EOF > config.json
{
  "inbounds": [{
    "port": $LISTEN_PORT,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$UUID"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": { "path": "$WS_PATH" }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF


pm2 start ./xray --name "deployRay" -- run -c config.json
pm2 save


sudo mkdir -p /var/www/deployray
sudo tee /var/www/deployray/index.html > /dev/null <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>deployRay</title>
    <style>
        body { background: #0a0a0a; color: #00ff41; font-family: monospace; display: flex; 
               align-items: center; justify-content: center; height: 100vh; margin: 0; }
        .container { border: 1px solid #00ff41; padding: 2rem; box-shadow: 0 0 15px #00ff41; }
        h1 { border-bottom: 1px solid #00ff41; padding-bottom: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>ACCESS GRANTED</h1>
        <p>This deployment is powered by <b>deployRay</b> and <b>XTLS</b>.</p>
        <p>Status: <span style="color:white">CLINICAL_OPERATIONAL</span></p>
    </div>
</body>
</html>
EOF

# nginx my love
sudo tee /etc/nginx/sites-available/deployray.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Xray WebSocket Proxy
    location $WS_PATH {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:$LISTEN_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    # Default Landing Page
    location / {
        root /var/www/deployray;
        index index.html;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/deployray.conf /etc/nginx/sites-enabled/
sudo systemctl restart nginx

# SSL Setup
if [ "$SSL_ENABLED" = true ]; then
    sudo apt-get install -y certbot python3-certbot-nginx
    sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m me@rhw.one --redirect
    sudo systemctl reload nginx
fi

echo "✅ deployRay v0.1.60 active at https://$DOMAIN"
echo "Proxy Endpoint: wss://$DOMAIN$WS_PATH"
echo "Internal Port: $LISTEN_PORT"
echo "UUID: $UUID"
