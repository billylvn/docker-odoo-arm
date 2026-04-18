#!/bin/bash
set -e

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

if [ -z "$DOMAIN_NAME" ]; then
  echo "Error: DOMAIN_NAME is not set in .env"
  exit 1
fi

if [ -z "$CERTBOT_EMAIL" ]; then
  echo "Error: CERTBOT_EMAIL is not set in .env"
  exit 1
fi

DATA_PATH="./data/certbot"
RSA_KEY_SIZE=4096

echo "==> Domain: $DOMAIN_NAME"
echo "==> Email : $CERTBOT_EMAIL"
echo

echo "==> Cleaning old broken renewal/config lineage ..."
docker compose run --rm --entrypoint sh certbot -c "\
  rm -f /etc/letsencrypt/renewal/${DOMAIN_NAME}.conf && \
  rm -rf /etc/letsencrypt/live/${DOMAIN_NAME} && \
  rm -rf /etc/letsencrypt/archive/${DOMAIN_NAME} \
"
echo

echo "==> Creating dummy certificate for bootstrap ..."
docker compose run --rm --entrypoint sh certbot -c "\
  mkdir -p /etc/letsencrypt/live/${DOMAIN_NAME} && \
  openssl req -x509 -nodes -newkey rsa:${RSA_KEY_SIZE} -days 1 \
    -keyout /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem \
    -out /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem \
    -subj '/CN=localhost' \
"
echo

echo "==> Starting nginx ..."
docker compose up -d nginx
echo

echo "==> Waiting nginx to become ready ..."
sleep 5
docker compose ps nginx
echo

echo "==> Removing dummy certificate ..."
docker compose run --rm --entrypoint sh certbot -c "\
  rm -rf /etc/letsencrypt/live/${DOMAIN_NAME} && \
  rm -rf /etc/letsencrypt/archive/${DOMAIN_NAME} && \
  rm -f /etc/letsencrypt/renewal/${DOMAIN_NAME}.conf \
"
echo

echo "==> Requesting Let's Encrypt certificate ..."
docker compose run --rm --entrypoint sh certbot -c "\
  certbot certonly --webroot \
    -w /var/www/certbot \
    --cert-name ${DOMAIN_NAME} \
    -d ${DOMAIN_NAME} \
    --email ${CERTBOT_EMAIL} \
    --rsa-key-size ${RSA_KEY_SIZE} \
    --agree-tos \
    --no-eff-email \
    --force-renewal \
"
echo

echo "==> Checking resulting live directory ..."
docker compose run --rm --entrypoint sh certbot -c "ls -l /etc/letsencrypt/live"
echo

echo "==> Recreating nginx so it reads the real certificate ..."
docker compose up -d --force-recreate nginx
echo

echo "==> Done."
echo "Test:"
echo "  curl -I http://${DOMAIN_NAME}"
echo "  curl -k -I https://${DOMAIN_NAME}"