# Nginx Reverse Proxy + SSL Certbot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Nginx reverse proxy with Certbot SSL to the Odoo 18 Docker stack, harden production settings, and remove direct port exposure.

**Architecture:** Nginx container is the only service exposing ports (80/443) to the host. Odoo and PostgreSQL communicate only on the internal Docker network. Certbot container shares a volume with Nginx for SSL certificates. A custom Nginx entrypoint selects HTTP-only or SSL config based on the `DOMAIN_NAME` environment variable.

**Tech Stack:** Docker Compose, Nginx (alpine), Certbot (Let's Encrypt), Odoo 18, PostgreSQL 16

---

## File Structure

```
docker-odoo-arm/
├── nginx/
│   ├── odoo-http.conf            # CREATE — HTTP-only reverse proxy config
│   ├── odoo-ssl.conf.template    # CREATE — HTTPS config template (envsubst for DOMAIN_NAME)
│   └── entrypoint.sh             # CREATE — selects HTTP or SSL config, starts nginx
├── conf/
│   └── odoo.conf                 # MODIFY — production settings (workers, proxy_mode, limits)
├── docker-compose.yml            # MODIFY — add nginx + certbot, remove web port exposure
├── .env.example                  # MODIFY — add DOMAIN_NAME, CERTBOT_EMAIL, ODOO_WORKERS, ODOO_ADMIN_PASSWD
├── .gitignore                    # MODIFY — add certbot-conf/, certbot-www/
├── init-letsencrypt.sh           # CREATE — SSL bootstrap script
└── Dockerfile                    # NO CHANGE
```

---

### Task 1: Update `.env.example` with new variables

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: Add domain, SSL, and Odoo production variables to `.env.example`**

Replace the full contents of `.env.example` with:

```env
# Copy this file to .env and adjust for your environment
# .env is gitignored — never commit it

# ── Paths ────────────────────────────────────────────────────────────────────
# Path to erp-odoo-arm (custom modules repo)
ADDONS_PATH=/path/to/your/erp-odoo-arm

# Path to Odoo Enterprise modules
ENTERPRISE_PATH=/path/to/your/odoo18/enterprise

# ── Database ─────────────────────────────────────────────────────────────────
DB_USER=odoo
DB_PASSWORD=odoo

# ── Odoo ─────────────────────────────────────────────────────────────────────
# Master admin password (used for database management page)
ODOO_ADMIN_PASSWD=changeme_strong_password_here

# Number of Odoo workers (0 = disabled, 6 = recommended for 8 vCPU)
ODOO_WORKERS=6

# ── Domain & SSL ─────────────────────────────────────────────────────────────
# Leave DOMAIN_NAME empty to run HTTP-only (no SSL)
# Set it to enable HTTPS with Let's Encrypt (e.g. erp.example.com)
DOMAIN_NAME=

# Email for Let's Encrypt certificate notifications
CERTBOT_EMAIL=
```

- [ ] **Step 2: Commit**

```bash
git add .env.example
git commit -m "chore: add domain, SSL, and worker variables to .env.example"
```

---

### Task 2: Update `conf/odoo.conf` for production

**Files:**
- Modify: `conf/odoo.conf`

- [ ] **Step 1: Replace `conf/odoo.conf` with production-hardened config**

Replace the full contents of `conf/odoo.conf` with:

```ini
[options]
; ── Database ──────────────────────────────────────────────────────────────────
db_host = db
db_port = 5432
db_user = odoo
db_password = odoo
db_name = False

; ── Addons path ───────────────────────────────────────────────────────────────
; Order matters: custom → enterprise → community
addons_path = /mnt/extra-addons,/mnt/enterprise-addons,/usr/lib/python3/dist-packages/odoo/addons

; ── Server ────────────────────────────────────────────────────────────────────
http_interface = 0.0.0.0
http_port = 8069
proxy_mode = True

; ── Workers (8 vCPU / 16 GB RAM) ─────────────────────────────────────────────
; workers = 0 means single-process mode (development only)
workers = 6
max_cron_threads = 2

; ── Resource limits ───────────────────────────────────────────────────────────
limit_memory_soft = 2147483648
limit_memory_hard = 2684354560
limit_time_cpu = 600
limit_time_real = 1200

; ── Logging ───────────────────────────────────────────────────────────────────
log_level = info
log_handler = :INFO

; ── Filestore ─────────────────────────────────────────────────────────────────
data_dir = /var/lib/odoo

; ── Security ──────────────────────────────────────────────────────────────────
admin_passwd = admin
```

Note: `longpolling_port` is removed — Odoo 18 uses the gevent worker automatically on port 8072 when `workers > 0`. The `admin_passwd` will be overridden at runtime by the `ODOO_ADMIN_PASSWD` environment variable via docker-compose (see Task 5).

- [ ] **Step 2: Commit**

```bash
git add conf/odoo.conf
git commit -m "chore: harden odoo.conf for production (workers, proxy_mode, limits)"
```

---

### Task 3: Create Nginx HTTP-only config

**Files:**
- Create: `nginx/odoo-http.conf`

- [ ] **Step 1: Create `nginx/odoo-http.conf`**

This config is used when `DOMAIN_NAME` is not set. It serves as an HTTP-only reverse proxy.

```nginx
upstream odoo {
    server web:8069;
}

upstream odoochat {
    server web:8072;
}

server {
    listen 80;
    server_name _;

    # Logs
    access_log /var/log/nginx/odoo-access.log;
    error_log  /var/log/nginx/odoo-error.log;

    # Max upload size
    client_max_body_size 100m;

    # Gzip
    gzip on;
    gzip_types text/css text/plain text/xml application/xml application/json application/javascript;

    # Proxy timeouts
    proxy_connect_timeout 720s;
    proxy_send_timeout    720s;
    proxy_read_timeout    720s;

    # Proxy headers
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # ACME challenge (for future SSL setup)
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Websocket
    location /websocket {
        proxy_pass http://odoochat;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # All other Odoo requests
    location / {
        proxy_pass http://odoo;
        proxy_redirect off;
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add nginx/odoo-http.conf
git commit -m "feat: add nginx HTTP-only reverse proxy config"
```

---

### Task 4: Create Nginx SSL config template

**Files:**
- Create: `nginx/odoo-ssl.conf.template`

- [ ] **Step 1: Create `nginx/odoo-ssl.conf.template`**

This template is processed by `envsubst` — `${DOMAIN_NAME}` is replaced at container startup.

```nginx
upstream odoo {
    server web:8069;
}

upstream odoochat {
    server web:8072;
}

# HTTP — redirect to HTTPS + serve ACME challenges
server {
    listen 80;
    server_name ${DOMAIN_NAME};

    # ACME challenge for certbot
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS
server {
    listen 443 ssl;
    server_name ${DOMAIN_NAME};

    # SSL certificates (managed by certbot)
    ssl_certificate     /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;

    # SSL settings
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    # Logs
    access_log /var/log/nginx/odoo-access.log;
    error_log  /var/log/nginx/odoo-error.log;

    # Max upload size
    client_max_body_size 100m;

    # Gzip
    gzip on;
    gzip_types text/css text/plain text/xml application/xml application/json application/javascript;

    # Proxy timeouts
    proxy_connect_timeout 720s;
    proxy_send_timeout    720s;
    proxy_read_timeout    720s;

    # Proxy headers
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Websocket
    location /websocket {
        proxy_pass http://odoochat;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # All other Odoo requests
    location / {
        proxy_pass http://odoo;
        proxy_redirect off;
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add nginx/odoo-ssl.conf.template
git commit -m "feat: add nginx SSL reverse proxy config template"
```

---

### Task 5: Create Nginx entrypoint script

**Files:**
- Create: `nginx/entrypoint.sh`

- [ ] **Step 1: Create `nginx/entrypoint.sh`**

This script selects the correct nginx config based on whether `DOMAIN_NAME` is set.

```bash
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
```

- [ ] **Step 2: Make the script executable and commit**

```bash
chmod +x nginx/entrypoint.sh
git add nginx/entrypoint.sh
git commit -m "feat: add nginx entrypoint for HTTP/SSL config selection"
```

---

### Task 6: Update `docker-compose.yml`

**Files:**
- Modify: `docker-compose.yml`

- [ ] **Step 1: Replace `docker-compose.yml` with the updated version**

Replace the full contents of `docker-compose.yml` with:

```yaml
services:

  db:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: ${DB_USER:-odoo}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-odoo}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - odoo-db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-odoo}"]
      interval: 10s
      timeout: 5s
      retries: 5

  web:
    build:
      context: .
      dockerfile: Dockerfile
    image: creativin-odoo18-enterprise:latest
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - ${ADDONS_PATH}:/mnt/extra-addons:ro
      - ${ENTERPRISE_PATH}:/mnt/enterprise-addons:ro
      - odoo-web-data:/var/lib/odoo
    environment:
      HOST: db
      PORT: 5432
      USER: ${DB_USER:-odoo}
      PASSWORD: ${DB_PASSWORD:-odoo}
    command: ["--admin_passwd", "${ODOO_ADMIN_PASSWD:-admin}", "--workers", "${ODOO_WORKERS:-6}"]

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    depends_on:
      - web
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/odoo-http.conf:/etc/nginx/templates/odoo-http.conf:ro
      - ./nginx/odoo-ssl.conf.template:/etc/nginx/templates/odoo-ssl.conf.template:ro
      - ./nginx/entrypoint.sh:/entrypoint.sh:ro
      - certbot-conf:/etc/letsencrypt:ro
      - certbot-www:/var/www/certbot:ro
    environment:
      DOMAIN_NAME: ${DOMAIN_NAME:-}
    entrypoint: /entrypoint.sh

  certbot:
    image: certbot/certbot
    volumes:
      - certbot-conf:/etc/letsencrypt
      - certbot-www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"

volumes:
  odoo-db-data:
  odoo-web-data:
  certbot-conf:
  certbot-www:
```

Key changes:

- `web` service: **removed** `ports` section (no longer exposed to host), **added** `command` to pass `ODOO_ADMIN_PASSWD` and `ODOO_WORKERS` from `.env` (overrides values in `odoo.conf` at runtime)
- `nginx` service: **added** with ports 80/443, custom entrypoint, bind-mounted configs
- `certbot` service: **added** with auto-renewal loop (runs `certbot renew` every 12h)
- New volumes: `certbot-conf` and `certbot-www` shared between nginx and certbot

- [ ] **Step 2: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add nginx reverse proxy and certbot services, remove web port exposure"
```

---

### Task 7: Create `init-letsencrypt.sh`

**Files:**
- Create: `init-letsencrypt.sh`

- [ ] **Step 1: Create `init-letsencrypt.sh`**

This script solves the chicken-and-egg problem: nginx needs certs to start, certbot needs nginx to validate.

```bash
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
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x init-letsencrypt.sh
git add init-letsencrypt.sh
git commit -m "feat: add init-letsencrypt.sh for SSL certificate bootstrap"
```

---

### Task 8: Update `.gitignore`

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add certbot data directories to `.gitignore`**

Append the following lines to `.gitignore`:

```
.env
certbot-conf/
certbot-www/
```

Note: `.env` is already in the file. The result should not have duplicates.

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore certbot data directories"
```

---

### Task 9: Validate the complete setup

- [ ] **Step 1: Run `docker compose config` to validate the compose file**

```bash
docker compose config --quiet
```

Expected: no output (means valid). If there are errors, fix them.

- [ ] **Step 2: Check nginx config syntax by doing a dry run**

```bash
docker compose run --rm --entrypoint "nginx -t" nginx
```

Expected: `nginx: configuration file /etc/nginx/nginx.conf syntax is ok`

Note: This may fail if the `web` service isn't running (upstream can't resolve). That is acceptable — the important thing is no syntax errors in the config files themselves.

- [ ] **Step 3: Final commit with all files verified**

Only if any fixes were needed. Otherwise, skip this step.

---

### Task 10: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README.md to document the new nginx/SSL setup**

Add a section covering:
- How to start without SSL: `docker compose up -d`
- How to set up SSL: configure `DOMAIN_NAME` and `CERTBOT_EMAIL` in `.env`, then run `./init-letsencrypt.sh`
- Updated `.env.example` variables reference
- Architecture diagram

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README with nginx reverse proxy and SSL setup instructions"
```
