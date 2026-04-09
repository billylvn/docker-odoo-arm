# Nginx Reverse Proxy + SSL Certbot for Odoo 18 Docker

## Context

Current Docker setup exposes Odoo ports (8069/8072) directly to the host with no reverse proxy, no SSL, and development-grade settings (single worker, hardcoded admin password, proxy_mode off). This design adds Nginx as a reverse proxy with Certbot SSL and hardens the configuration for GCP production deployment (8 vCPU / 16GB RAM).

## Architecture

```
Internet ──→ [ Nginx :80/:443 ] ──→ [ Odoo web :8069/:8072 ] ──→ [ PostgreSQL :5432 ]
                    ↕
              [ Certbot ]
            (shared cert volume)
```

- **Nginx** — only container exposing ports to host (80 & 443)
- **Odoo (web)** — accessible only via internal Docker network
- **Certbot** — requests & auto-renews SSL certificates, shares volume with Nginx
- **PostgreSQL (db)** — internal only, unchanged

## Domain Handling

- Domain name is configurable via `DOMAIN_NAME` in `.env`
- If `DOMAIN_NAME` is empty or unset, Nginx runs as HTTP-only reverse proxy on port 80 (no SSL)
- If `DOMAIN_NAME` is set, Nginx serves HTTPS with Let's Encrypt cert and redirects HTTP → HTTPS

## Changes

### 1. `docker-compose.yml`

- **Add** `nginx` service (`nginx:alpine`): expose ports 80/443, depends on `web`
- **Add** `certbot` service (`certbot/certbot`): entrypoint for auto-renewal
- **Remove** port exposure from `web` service (8069/8072 become internal only)
- **Add** volumes: `certbot-conf`, `certbot-www` shared between nginx and certbot
- **Add** `nginx/conf.d/` bind mount for nginx configuration

### 2. New file: `nginx/conf.d/odoo.conf`

Nginx reverse proxy config:
- Upstream blocks for `odoo` (port 8069) and `odoochat` (port 8072)
- HTTP server on port 80:
  - Serves ACME challenge for certbot validation at `/.well-known/acme-challenge/`
  - Redirects all other traffic to HTTPS (when SSL is active)
  - Acts as primary server when no domain/SSL configured
- HTTPS server on port 443 (only when cert exists):
  - SSL termination with Let's Encrypt certificates
  - Proxy pass to `web:8069` for standard requests
  - WebSocket proxy to `web:8072` for `/websocket` endpoint
  - Headers: `X-Forwarded-For`, `X-Forwarded-Proto`, `X-Real-IP`, `Host`
  - Gzip compression for text/css/js/xml/json
  - Client max body size 100MB (for large Odoo uploads)
  - Proxy timeouts 720s (matching Odoo longpolling)

### 3. `conf/odoo.conf` — Updates

| Setting | Old | New |
|---------|-----|-----|
| `proxy_mode` | `False` | `True` |
| `workers` | `0` | `6` |
| `max_cron_threads` | (not set) | `2` |
| `limit_memory_soft` | (not set) | `2147483648` (2GB) |
| `limit_memory_hard` | (not set) | `2684354560` (2.5GB) |
| `limit_time_cpu` | (not set) | `600` |
| `limit_time_real` | (not set) | `1200` |
| `admin_passwd` | `admin` | from env variable |
| `db_user` | `odoo` (hardcoded) | from env variable |
| `db_password` | `odoo` (hardcoded) | from env variable |
| `longpolling_port` | `8072` | removed (Odoo 18 uses `/websocket` on same port) |

Note: Odoo 18 no longer uses a separate longpolling port. Live features use WebSocket on the main port. The `web` service only needs to expose port 8069 internally, but we keep 8072 for gevent worker compatibility.

### 4. `.env.example` — New variables

```env
# Domain & SSL
DOMAIN_NAME=
CERTBOT_EMAIL=

# Odoo
ODOO_WORKERS=6
ODOO_ADMIN_PASSWD=changeme_strong_password_here
```

### 5. New file: `init-letsencrypt.sh`

Bootstrap script for initial SSL setup:
1. Creates dummy self-signed certificate so Nginx can start
2. Starts Nginx container
3. Requests real Let's Encrypt certificate via certbot
4. Replaces dummy cert with real cert
5. Reloads Nginx

This is needed because of the chicken-and-egg problem: Nginx needs certs to start, certbot needs Nginx to validate the domain.

### 6. Dockerfile

No changes needed. The Dockerfile is minimal and correct.

## Security Improvements

- Odoo ports no longer exposed to host
- `admin_passwd` moved to environment variable (no more hardcoded `admin`)
- DB credentials sourced from env in both compose and odoo.conf
- SSL/TLS encryption for all external traffic
- Nginx enforces client body size limits (100MB max)

## Worker Calculation (8 vCPU / 16GB RAM)

- **Workers:** 6 (rule of thumb: `CPU * 2 + 1` capped by RAM, leaving room for cron + system)
- **Cron threads:** 2
- **Memory per worker:** ~150MB (soft limit 2GB for spikes)
- **Total Odoo memory:** ~1.2GB base + headroom
- **Remaining for PostgreSQL, Nginx, OS:** ~14GB
