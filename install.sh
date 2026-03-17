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
             |_|            |___/             |___/  v1.71
                                          
 by: RHW.one
BANNER

# --- Defaults ---
SSL_ENABLED=false
DOMAIN=""
LISTEN_PORT=10000
WS_PATH="/ray"
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)

# --- Parse arguments ---
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

echo "Ensuring sudo is installed..."
if ! command -v sudo >/dev/null; then
    apt-get update
    apt-get install -y sudo
fi

# Install core dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y curl git nginx openssl jq unzip

echo "Making sure your CLI is normal..."
sudo apt-get install -y build-essential

# Safely handle Node.js and PM2 setup without breaking apt
if ! command -v npm >/dev/null; then
    echo "Installing Node.js (v22.x)..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

if ! command -v pm2 >/dev/null; then
    echo "Installing PM2..."
    sudo npm install -g pm2
fi

# Clean up previous installations (for updating)
echo "Clearing previous deployRay installations..."
if pm2 describe deployRay > /dev/null 2>&1; then
    pm2 delete deployRay
fi
rm -rf ~/xray
sudo rm -f /etc/nginx/sites-available/deployray.conf
sudo rm -f /etc/nginx/sites-enabled/deployray.conf

# Install Xray-core
echo "Downloading and setting up Xray-core..."
mkdir -p ~/xray && cd ~/xray
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/${latest_version}/Xray-linux-64.zip"
unzip -o xray.zip && chmod +x xray

# Generate Xray Config
echo "Generating Xray configuration..."
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

# Start with PM2 and configure boot
echo "Starting application with PM2..."
pm2 start ./xray --name "deployRay" -- run -c config.json

echo "Configuring PM2 to start on boot..."
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $USER --hp $HOME 2>/dev/null || true
pm2 save

# Create Landing Page
echo "Writing Clinical landing page..."
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

# NGINX Configuration
echo "Writing NGINX configuration for WebSocket proxy..."
sudo tee /etc/nginx/sites-available/deployray.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location $WS_PATH {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:$LISTEN_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location / {
        root /var/www/deployray;
        index index.html;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/deployray.conf /etc/nginx/sites-enabled/

# Start NGINX
echo "Enabling and starting NGINX..."
sudo systemctl enable nginx
sudo systemctl start nginx

echo "Testing NGINX configuration..."
sudo nginx -t

# SSL Setup
if [ "$SSL_ENABLED" = true ]; then
    echo "Installing Certbot..."
    sudo apt-get install -y certbot python3-certbot-nginx

    echo "Obtaining SSL certificate for $DOMAIN..."
    sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m me@rhw.one --redirect

    echo "Enabling automatic certificate renewal..."
    sudo systemctl enable certbot.timer
    sudo systemctl start certbot.timer

    echo "Reloading NGINX with SSL..."
    sudo nginx -t
    sudo systemctl reload nginx
fi

# Restart NGINX
echo "Restarting NGINX..."
sudo service nginx restart

echo
echo "--------------------------------------------------"
if [ "$SSL_ENABLED" = true ]; then
  echo "✅ deployRay v0.1.70 active at: https://$DOMAIN"
  echo "Proxy Endpoint: wss://$DOMAIN$WS_PATH"
else
  echo "✅ deployRay v0.1.70 active at: http://$DOMAIN"
  echo "Proxy Endpoint: ws://$DOMAIN$WS_PATH"
  echo "(Run again with -c to enable SSL via Certbot)"
fi
echo "Internal Port: $LISTEN_PORT"
echo "UUID: $UUID"
echo "--------------------------------------------------"
