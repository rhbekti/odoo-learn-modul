# Bab 2: Install & Konfigurasi Odoo 18

## Konfigurasi docker-compose.yml

```yaml
version: '3.8'

services:
  odoo:
    image: odoo:18.0
    container_name: odoo18_dev
    depends_on:
      db:
        condition: service_healthy
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo
      - PORT=5432
      - LOG_LEVEL=debug
    ports:
      - "8069:8069"
    volumes:
      - ./addons:/mnt/extra-addons
      - ./odoo-data:/var/lib/odoo
      - ./config/odoo.conf:/etc/odoo/odoo.conf
    restart: unless-stopped

  db:
    image: postgres:16
    container_name: odoo18_db
    environment:
      - POSTGRES_DB=odoo
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo"]
      interval: 5s
      timeout: 5s
      retries: 10
    restart: unless-stopped
```

## odoo.conf (konfigurasi utama)

```ini
[options]
admin_passwd = admin123
db_host = db
db_port = 5432
db_user = odoo
db_password = odoo
db_name = odoo
addons_path = /mnt/extra-addons

; Development options
dev_mode = all
log_level = debug
systray = True

; Server settings
limit_time_cpu = 60
limit_time_real = 120
max_cron_threads = 2

; Workers
workers = 0
```

## Environment Variables Penting

| Variable | Fungsi |
|----------|--------|
| `admin_passwd` | Master password untuk create/delete DB |
| `db_host/db_user/db_password` | Koneksi PostgreSQL |
| `addons_path` | Path ke custom modules |
| `dev_mode` | Enable dev mode (all = semua fitur on) |
| `log_level` | Level logging |
| `workers` | Number of workers (0 = no multi-thread) |

## Dev Mode Features

Dengan `dev_mode = all`, aktif:
- **Reload Python** otomatis pas save
- **QWeb template** reload otomatis
- **Disable assets bundle caching**
- **Show debug info** di UI

## Akses Database Langsung

```bash
# Login ke PostgreSQL container
docker compose exec db psql -U odoo -d odoo

# Contoh query
SELECT name, state FROM ir_module_module WHERE name = 'base';

# Exit
\q
```

## Reset Database

```bash
# Hapus data
docker compose down -v

# Hapus folder data
rm -rf postgres-data odoo-data

# Start ulang
docker compose up -d
```

## Perintah Cli Berguna

```bash
# Shell Odoo
docker compose exec odoo odoo shell -d odoo --db_host db

# Import module
docker compose exec odoo odoo -d odoo -i module_name

# Update module
docker compose exec odoo odoo -d odoo -u module_name

# Backup
docker compose exec db pg_dump -U odoo odoo > backup.sql

# Restore
cat backup.sql | docker compose exec -T db psql -U odoo -d odoo
```

## Troubleshooting

**Container tidak start:**
```bash
docker compose logs odoo
```

**DB connection error:**
```bash
docker compose exec db pg_isready -U odoo
```

**Odoo stuck di maintenance:**
- Hapus cookies browser
- Login ulang dengan password admin yang baru