#!/bin/sh
set -e

CONF_DIR="/etc/nginx/conf.d"

# Remove any default config
rm -f "$CONF_DIR/default.conf"

if [ -n "$DOMAIN_NAME" ]; then
    echo "==> DOMAIN_NAME is set to '$DOMAIN_NAME' — using SSL config"
    # Process template: substitute DOMAIN_NAME, but preserve nginx variables ($host, etc.)
    envsubst '${DOMAIN_NAME}' < /etc/nginx/templates/odoo-ssl.conf.template > "$CONF_DIR/odoo.conf"
else
    echo "==> DOMAIN_NAME is not set — using HTTP-only config"
    cp /etc/nginx/templates/odoo-http.conf "$CONF_DIR/odoo.conf"
fi

echo "==> Starting nginx..."
exec nginx -g "daemon off;"
