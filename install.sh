#!/bin/bash
# Usage: curl -fsSL https://raw.githubusercontent.com/rhenryw/deployRay/main/install.sh | bash -s yourdomain.tld [-c] [--port 10000]

set -e

cat <<'BANNER'
  _____             _             _____              
 |  __ \           | |           |  __ \             
 | |  | | ___ _ __ | | ___  _   _| |__) |__ _ _   _ 
 | |  | |/ _ \ '_ \| |/ _ \| | | |  _  // _` | | | |
 | |__| |  __/ |_) | | (_) | |_| | | \ \ (_| | |_| |
 |_____/ \___| .__/|_|\___/ \__, |_|  \_\__,_|\__, |
             | |             __/ |             __/ |
             |_|            |___/             |___/  v1.78
                                          
 by: RHW.one
BANNER

SSL_ENABLED=false
DOMAIN=""
XRAY_PORT=10000
SOCKS_PORT=10001
WISP_PORT=8080
WS_PATH="/ray"
WISP_PATH="/wisp"
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)
REPO="https://github.com/rhenryw/deployRay.git"

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
sudo apt-get update -q
sudo apt-get install -y curl git nginx openssl jq unzip build-essential

if ! command -v bun >/dev/null; then
    echo "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
fi

# Ensure bun is on PATH even if already installed
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PATH="$BUN_INSTALL/bin:$PATH"

if ! command -v pm2 >/dev/null; then
    echo "Installing PM2..."
    bun install -g pm2
fi

echo "Clearing old installations..."
pm2 delete deployRay wisp-gate > /dev/null 2>&1 || true
rm -rf ~/xray ~/wisp-gate

echo "Setting up Xray-core..."
mkdir -p ~/xray && cd ~/xray
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/${latest_version}/Xray-linux-64.zip"
unzip -o xray.zip && chmod +x xray

# Two inbounds:
#   1. VLESS/WS  :XRAY_PORT  → direct Xray clients via /ray
#   2. SOCKS5    :SOCKS_PORT → internal use by wisp-gate
cat <<EOF > config.json
{
  "inbounds": [
    {
      "tag": "vless-ws",
      "port": $XRAY_PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH" }
      }
    },
    {
      "tag": "socks-internal",
      "port": $SOCKS_PORT,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": false
      }
    }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom" }
  ]
}
EOF

echo "Cloning deployRay repo..."
git clone "$REPO" ~/wisp-gate
cd ~/wisp-gate

echo "Installing wisp-gate dependencies..."
bun install

echo "Starting services with PM2..."

cd ~/xray
pm2 start ./xray --name "deployRay" -- run -c config.json

cd ~/wisp-gate
pm2 start index.ts \
    --name "wisp-gate" \
    --interpreter "$(command -v bun)" \
    --env WISP_PORT=$WISP_PORT

pm2 save

echo "Creating web root..."
sudo mkdir -p /var/www/deployray

sudo tee /var/www/deployray/index.html > /dev/null <<EOF
<!DOCTYPE html>
<html data-theme="dark" lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>deployRay — Xray Gate</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/rhenryw/one.css@main/dist/one.light.min.css" />
  <style>
    body {
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: 2rem;
    }
    pre {
      text-align: left;
      font-size: 0.7rem;
      line-height: 1.2;
      overflow-x: auto;
    }
    footer {
      margin-top: 3rem;
      font-size: 0.85rem;
      opacity: 0.6;
    }
    footer a { opacity: 1; }
  </style>
</head>
<body>
  <pre aria-hidden="true">
  _____             _            _____
 |  __ \           | |          |  __ \
 | |  | | ___ _ __ | | ___  _   _| |__) |__ _ _   _
 | |  | |/ _ \ '_ \| |/ _ \| | | |  _  // _\` | | | |
 | |__| |  __/ |_) | | (_) | |_| | | \ \ (_| | |_| |
 |_____/ \___| .__/|_|\___/ \__, |_|  \_\__,_|\__, |
             | |             __/ |             __/ |
             |_|            |___/             |___/
  </pre>

  <h1>Xray Gate</h1>
  <p>This node is active and operational.</p>
  <hr />
  <p>
    Powered by <a href="https://github.com/rhenryw/deployRay" target="_blank" rel="noopener">deployRay</a>
    and <a href="https://github.com/XTLS" target="_blank" rel="noopener">XTLS</a>.
  </p>

  <footer>
    <small>$DOMAIN &mdash; deployRay v1.78 by <a href="https://rhw.one" target="_blank" rel="noopener">RHW.one</a></small>
  </footer>
</body>
</html>
EOF

echo "Configuring Nginx..."
sudo tee /etc/nginx/sites-available/deployray.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Xray VLESS — direct clients
    location $WS_PATH {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:$XRAY_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    # Wisp Bridge — routed through Xray SOCKS5 internally
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
sudo nginx -t && sudo systemctl restart nginx

if [ "$SSL_ENABLED" = true ]; then
    sudo apt-get install -y certbot python3-certbot-nginx
    sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m me@rhw.one --redirect
    sudo systemctl reload nginx
fi

echo "--------------------------------------------------"
echo "✅ deployRay v1.78 Operational"
echo "--------------------------------------------------"
echo "Xray Endpoint:  wss://$DOMAIN$WS_PATH   (VLESS direct)"
echo "Wisp Endpoint:  wss://$DOMAIN$WISP_PATH  (Wisp → Xray)"
echo "UUID:           $UUID"
echo "--------------------------------------------------"
