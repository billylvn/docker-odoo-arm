#!/bin/bash
set -e

# ── Load .env ─────────────────────────────────────────────────────────────────
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

if [ -z "$DOMAIN_NAME" ]; then
    echo "Error: DOMAIN_NAME is not set in .env"
    echo "Set DOMAIN_NAME to your domain (e.g. erp.example.com) and re-run."
    exit 1
fi

if [ -z "$CERTBOT_EMAIL" ]; then
    echo "Error: CERTBOT_EMAIL is not set in .env"
    echo "Set CERTBOT_EMAIL to your email for Let's Encrypt notifications."
    exit 1
fi

# ── Step 1: Create dummy certificate ─────────────────────────────────────────
echo "==> Creating dummy certificate for $DOMAIN_NAME ..."
docker compose run --rm --entrypoint "\
    mkdir -p /etc/letsencrypt/live/$DOMAIN_NAME" certbot
docker compose run --rm --entrypoint "\
    openssl req -x509 -nodes -newkey rsa:4096 -days 1 \
    -keyout '/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem' \
    -out '/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem' \
    -subj '/CN=localhost'" certbot
echo

# ── Step 2: Start nginx ──────────────────────────────────────────────────────
echo "==> Starting nginx ..."
docker compose up -d nginx
echo

# ── Step 3: Delete dummy certificate ─────────────────────────────────────────
echo "==> Deleting dummy certificate ..."
docker compose run --rm --entrypoint "\
    rm -rf /etc/letsencrypt/live/$DOMAIN_NAME && \
    rm -rf /etc/letsencrypt/archive/$DOMAIN_NAME && \
    rm -rf /etc/letsencrypt/renewal/$DOMAIN_NAME.conf" certbot
echo

# ── Step 4: Request real certificate ─────────────────────────────────────────
echo "==> Requesting Let's Encrypt certificate for $DOMAIN_NAME ..."
docker compose run --rm --entrypoint "\
    certbot certonly --webroot -w /var/www/certbot \
    --email $CERTBOT_EMAIL \
    -d $DOMAIN_NAME \
    --rsa-key-size 4096 \
    --agree-tos \
    --no-eff-email \
    --force-renewal" certbot
echo

# ── Step 5: Reload nginx ─────────────────────────────────────────────────────
echo "==> Reloading nginx ..."
docker compose exec nginx nginx -s reload
echo

echo "==> Done! SSL certificate installed for $DOMAIN_NAME"
echo "    Your Odoo instance should now be available at https://$DOMAIN_NAME"
