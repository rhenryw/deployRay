#!/bin/bash
# Usage: curl -fsSL https://raw.githubusercontent.com/rhenryw/deployRay/main/install.sh | bash -s yourdomain.tld [-c] [--port 10000]

set -e

cat <<'BANNER'
  _____             _            _____              
 |  __ \           | |          |  __ \             
 | |  | | ___ _ __ | | ___  _   _| |__) |__ _ _   _ 
 | |  | |/ _ \ '_ \| |/ _ \| | | |  _  // _` | | | |
 | |__| |  __/ |_) | | (_) | |_| | | \ \ (_| | |_| |
 |_____/ \___| .__/|_|\___/ \__, |_|  \_\__,_|\__, |
             | |             __/ |             __/ |
             |_|            |___/             |___/  v1.72
                                          
 by: RHW.one
BANNER


SSL_ENABLED=false
DOMAIN=""
XRAY_PORT=10000
WISP_PORT=8080
WS_PATH="/ray"
WISP_PATH="/wisp"
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c) SSL_ENABLED=true ;;
        --port|-p) XRAY_PORT="$2"; shift ;;
        *) if [[ -z "$DOMAIN" ]]; then DOMAIN=$1; fi ;;
    esac
    shift
done

if [ -z "$DOMAIN" ]; then
    echo "Error: Domain not provided."
    exit 1
fi

echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y curl git nginx openssl jq unzip build-essential

if ! command -v npm >/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

if ! command -v pm2 >/dev/null; then
    sudo npm install -g pm2
fi

echo "Clearing old installations..."
pm2 delete deployRay wisp-gate > /dev/null 2>&1 || true
rm -rf ~/xray ~/wisp-gate

echo "Setting up Xray-core..."
mkdir -p ~/xray && cd ~/xray
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/${latest_version}/Xray-linux-64.zip"
unzip -o xray.zip && chmod +x xray

cat <<EOF > config.json
{
  "inbounds": [{
    "port": $XRAY_PORT,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": { "clients": [{"id": "$UUID"}], "decryption": "none" },
    "streamSettings": { "network": "ws", "wsSettings": { "path": "$WS_PATH" } }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

# 4. Setup Wisp-Gate (Bridge)
echo "Setting up Wisp-to-Xray Bridge..."
mkdir -p ~/wisp-gate && cd ~/wisp-gate
npm init -y > /dev/null
npm install @mercuryworkshop/wisp-js > /dev/null

cat <<EOF > index.js
const { server: wisp } = require("@mercuryworkshop/wisp-js/server");
const http = require("node:http");

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("Wisp-to-Xray Bridge Active");
});

server.on("upgrade", (req, socket, head) => {
  wisp.routeRequest(req, socket, head);
});

server.listen($WISP_PORT, "127.0.0.1");
EOF

# 5. Start Services
echo "Starting services with PM2..."
cd ~/xray && pm2 start ./xray --name "deployRay" -- run -c config.json
cd ~/wisp-gate && pm2 start index.js --name "wisp-gate"
pm2 save

# 6. Nginx Config
echo "Configuring Nginx..."
sudo tee /etc/nginx/sites-available/deployray.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Xray VLESS (Stealth)
    location $WS_PATH {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:$XRAY_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    # Wisp Bridge (For SPLASH)
    location $WISP_PATH {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:$WISP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    location / {
        root /var/www/deployray;
        index index.html;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/deployray.conf /etc/nginx/sites-enabled/
sudo systemctl restart nginx

# 7. SSL (Optional)
if [ "$SSL_ENABLED" = true ]; then
    sudo apt-get install -y certbot python3-certbot-nginx
    sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m me@rhw.one --redirect
    sudo systemctl reload nginx
fi

echo "--------------------------------------------------"
echo "✅ deployRay v1.72 Operational"
echo "--------------------------------------------------"
echo "Xray Endpoint: wss://$DOMAIN$WS_PATH"
echo "Wisp Endpoint: wss://$DOMAIN$WISP_PATH"
echo "UUID: $UUID"
echo "--------------------------------------------------"
