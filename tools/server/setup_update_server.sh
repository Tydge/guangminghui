#!/usr/bin/env bash
# Run as root on a dedicated Ubuntu server: bash setup_update_server.sh PUBLIC_IPV4
set -euo pipefail
address="${1:?Pass the server public IPv4 address}"
python3 -c 'import ipaddress,sys; ipaddress.IPv4Address(sys.argv[1])' "$address"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx python3-venv
install -d -m 755 /srv/illuminati/www/.well-known/acme-challenge /srv/illuminati/www/releases
cat > /etc/nginx/sites-available/illuminati-updates <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $address;
    root /srv/illuminati/www;
    location ^~ /.well-known/acme-challenge/ { try_files \$uri =404; }
    location = /health { default_type text/plain; return 200 'illuminati-updates ok\n'; }
    location / { try_files \$uri =404; }
}
EOF
# This script is for a newly provisioned dedicated host, not an existing web server.
rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/illuminati-updates /etc/nginx/sites-enabled/illuminati-updates
nginx -t
systemctl enable --now nginx
systemctl reload nginx
if [ ! -x /opt/illuminati-certbot/bin/certbot ]; then
    python3 -m venv /opt/illuminati-certbot
    /opt/illuminati-certbot/bin/pip -q install 'certbot>=5.4,<6'
fi
/opt/illuminati-certbot/bin/certbot certonly --non-interactive --agree-tos \
    --register-unsafely-without-email --preferred-profile shortlived \
    --webroot --webroot-path /srv/illuminati/www --ip-address "$address" \
    --cert-name illuminati-ip --keep-until-expiring
cat > /etc/nginx/sites-available/illuminati-updates <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $address;
    root /srv/illuminati/www;
    location ^~ /.well-known/acme-challenge/ { try_files \$uri =404; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name $address;
    ssl_certificate /etc/letsencrypt/live/illuminati-ip/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/illuminati-ip/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    server_tokens off;
    root /srv/illuminati/www;
    autoindex off;
    add_header X-Content-Type-Options nosniff always;
    location = /health { default_type text/plain; return 200 'illuminati-updates ok\n'; }
    location ~ /\. { deny all; }
    location ~ \.json$ { add_header Cache-Control 'no-store'; try_files \$uri =404; }
    location /releases/ { add_header Cache-Control 'public, max-age=31536000, immutable'; try_files \$uri =404; }
    location / { try_files \$uri =404; }
}
EOF
nginx -t
systemctl reload nginx
cat > /etc/systemd/system/illuminati-cert-renew.service <<'EOF'
[Unit]
Description=Renew Illuminati IP HTTPS certificate
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/opt/illuminati-certbot/bin/certbot renew --quiet --deploy-hook "/usr/bin/systemctl reload nginx"
EOF
cat > /etc/systemd/system/illuminati-cert-renew.timer <<'EOF'
[Unit]
Description=Check short-lived IP certificate every six hours
[Timer]
OnCalendar=*-*-* 00,06,12,18:00:00
RandomizedDelaySec=300
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now illuminati-cert-renew.timer
curl --fail --silent "https://$address/health"
systemctl list-timers illuminati-cert-renew.timer --no-pager
