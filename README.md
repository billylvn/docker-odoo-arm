# docker-odoo-arm

Docker setup untuk menjalankan Odoo 18 Enterprise + custom modules Creativin.

---

## Struktur

```
erp-odoo-docker/
├── Dockerfile          # extend official odoo:18.0
├── docker-compose.yml  # web + db services
├── .env.example        # template konfigurasi path & credential
└── conf/
    └── odoo.conf       # addons path, port, logging
```

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
```

### 3. Build & jalankan

```bash
docker compose build
docker compose up -d
```

Buka `http://localhost:8069`

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
docker compose logs -f web            # live logs
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

### Update module di server

```bash
cd erp-odoo-arm && git pull
cd ../docker-odoo-arm && docker compose restart web
```

---

## Catatan

- File `.env` di-gitignore — jangan di-commit, berisi credential
- Enterprise modules di-mount read-only, tidak masuk ke image
- Untuk colima (macOS tanpa Docker Desktop): jalankan `colima start` sebelum `docker compose up`
