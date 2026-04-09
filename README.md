# docker-odoo-arm

Docker setup untuk menjalankan Odoo 18 Enterprise + custom modules Creativin.

---

## Struktur

```
erp-odoo-docker/
├── Dockerfile                      # extend official odoo:18.0
├── docker-compose.yml              # web + db + nginx + certbot services
├── .env.example                    # template konfigurasi path & credential
├── init-letsencrypt.sh             # SSL certificate bootstrap script
├── conf/
│   └── odoo.conf                   # addons path, port, logging
└── nginx/
    ├── odoo-http.conf              # nginx HTTP-only reverse proxy config
    ├── odoo-ssl.conf.template      # nginx HTTPS config template
    └── entrypoint.sh               # selects HTTP or SSL config
```

---

## Arsitektur

```
Internet → [ Nginx :80/:443 ] → [ Odoo web :8069 ] → [ PostgreSQL :5432 ]
                    ↕
              [ Certbot ]
```

Nginx bertindak sebagai reverse proxy — Odoo tidak lagi di-expose langsung ke publik. Certbot menangani pembaruan sertifikat SSL secara otomatis.

---

## Setup

### 1. Clone repo yang dibutuhkan

```bash
git clone https://github.com/billylvn/docker-odoo-arm.git
git clone <erp-odoo-arm-url>   # custom modules
```

### 2. Siapkan `.env`

```bash
cd docker-odoo-arm
cp .env.example .env
nano .env
```

Isi sesuai environment:

```env
ADDONS_PATH=/path/to/erp-odoo-arm
ENTERPRISE_PATH=/path/to/odoo/enterprise
DB_USER=odoo
DB_PASSWORD=odoo
ODOO_ADMIN_PASSWD=adminpassword
ODOO_WORKERS=4

# Untuk SSL (opsional — kosongkan jika tidak pakai domain)
DOMAIN_NAME=erp.yourdomain.com
CERTBOT_EMAIL=you@yourdomain.com
```

### 3. Build & jalankan

```bash
docker compose build
docker compose up -d
```

Buka `http://localhost`

---

## SSL Setup

Untuk mengaktifkan HTTPS dengan Let's Encrypt:

### 1. Pastikan `DOMAIN_NAME` dan `CERTBOT_EMAIL` sudah diisi di `.env`

```env
DOMAIN_NAME=erp.yourdomain.com
CERTBOT_EMAIL=you@yourdomain.com
```

### 2. Jalankan script bootstrap SSL

```bash
./init-letsencrypt.sh
```

Script ini akan:
- Membuat sertifikat dummy sementara agar Nginx bisa start
- Meminta sertifikat asli dari Let's Encrypt via Certbot
- Me-reload Nginx secara otomatis

### 3. Akses via HTTPS

```
https://erp.yourdomain.com
```

> Sertifikat akan diperbarui otomatis oleh Certbot.

---

## Addons Path

Urutan di `odoo.conf` (custom → enterprise → community):

| Mount | Isi |
|-------|-----|
| `/mnt/extra-addons` | Custom modules (`erp-odoo-arm`) |
| `/mnt/enterprise-addons` | Odoo Enterprise |
| `/usr/lib/python3/dist-packages/odoo/addons` | Odoo Community (dalam image) |

> Urutan penting — module kiri akan override module kanan jika namanya sama.

---

## Commands

```bash
docker compose up -d                  # start
docker compose down                   # stop
docker compose restart web            # restart Odoo (setelah edit module)
docker compose restart nginx          # restart Nginx
docker compose logs -f web            # live logs Odoo
docker compose logs -f nginx          # live logs Nginx
docker compose build                  # rebuild image (setelah edit odoo.conf)
```

### Upgrade module (setelah ada perubahan model)

```bash
docker compose exec web odoo \
  -c /etc/odoo/odoo.conf \
  -d <nama_database> \
  -u <nama_module> \
  --stop-after-init
```

---

## Deploy ke Server Baru

```bash
git clone https://github.com/billylvn/docker-odoo-arm.git
git clone <erp-odoo-arm-url>

cd docker-odoo-arm
cp .env.example .env
nano .env   # sesuaikan path

docker compose build
docker compose up -d
```

Untuk SSL, jalankan setelah container up:

```bash
./init-letsencrypt.sh
```

### Update module di server

```bash
cd erp-odoo-arm && git pull
cd ../docker-odoo-arm && docker compose restart web
```

---

## Catatan

- File `.env` di-gitignore — jangan di-commit, berisi credential
- Enterprise modules di-mount read-only, tidak masuk ke image
- Nginx sebagai reverse proxy — Odoo tidak lagi expose port langsung ke publik (port 8069 hanya accessible secara internal antar container)
- Tanpa domain, setup tetap bisa digunakan via HTTP di port 80 — cukup kosongkan `DOMAIN_NAME` dan `CERTBOT_EMAIL` di `.env`
- Untuk colima (macOS tanpa Docker Desktop): jalankan `colima start` sebelum `docker compose up`
