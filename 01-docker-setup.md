# Bab 1: Setup Docker untuk Odoo 18

## Persiapan

Install Docker dan Docker Compose dulu di machine kamu.

## docker-compose.yml

```yaml
version: "3.8"

services:
  odoo:
    image: odoo:18.0
    container_name: odoo18_dev
    depends_on:
      - db
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo
      - PORT=5432
    ports:
      - "8069:8069"
    volumes:
      - ./addons:/mnt/extra-addons
      - ./odoo-data:/var/lib/odoo
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
    restart: unless-stopped
```

## Jalankan Container

```bash
# Start services
docker compose up -d

# Cek status
docker compose ps

# Lihat logs
docker compose logs -f

# Stop services
docker compose down
```

## Struktur Direktori

```
project/
├── docker-compose.yml
├── addons/                  # custom modules di sini
│   └── .gitkeep
├── odoo-data/              # filestore Odoo
└── postgres-data/          # data PostgreSQL
```

## Akses Odoo

- URL: http://localhost:8069
- Database: buat baru saat pertama akses
- Email admin: biarkan kosong atau isi sesuka
- Password: pilih password superadmin

## Install Module dari addons Path

Setiap module yang taruh di `./addons` akan muncul di Apps > Update Apps List.

```bash
# Rebuild tanpa hapus volume
docker compose restart
```

## Tips Development

1. **Live reload**: Odoo auto-reload pas edit Python files
2. **Restart container**: `docker compose restart odoo`
3. **Akses shell**: `docker compose exec odoo bash`
4. **Akses DB**: `docker compose exec db psql -U odoo -d odoo`
5. **Log level debug**: tambah env `LOG_LEVEL=debug`
