# Bab 1: Setup Docker untuk Odoo

> **Tahap:** 1 Persiapan | **Prasyarat:** Tidak ada | **Estimasi:** ± 1 jam | **Versi:** Odoo 18 (catatan Odoo 19)

## Tujuan Belajar

Setelah bab ini kamu bisa:
- Menyiapkan Odoo 18 + PostgreSQL di Docker lewat satu file `docker-compose.yml`.
- Menjelaskan fungsi tiap volume (addons, data Odoo, data PostgreSQL).
- Menjalankan, menghentikan, dan melihat log container dengan perintah harian.
- Membuat database pertama dan masuk ke Odoo lewat browser.
- Masuk ke shell container Odoo dan `psql` untuk keperluan debugging.

## Persiapan

Install Docker (sudah termasuk Docker Compose v2, perintahnya `docker compose`, tanpa tanda hubung) di machine kamu. Cek dengan:

```bash
docker --version
docker compose version
```

## Struktur Direktori Project

```
project/
├── docker-compose.yml
└── addons/                  # custom module kamu taruh di sini
    └── .gitkeep
```

Data Odoo (filestore) dan data PostgreSQL disimpan di **named volume** Docker, jadi tidak ada folder tambahan di project dan tidak ada masalah permission di folder host.

## docker-compose.yml

```yaml
services:
  odoo:
    image: odoo:18.0
    container_name: odoo18_dev
    depends_on:
      db:
        condition: service_healthy
    environment:
      - HOST=db
      - PORT=5432
      - USER=odoo
      - PASSWORD=odoo
    ports:
      - "8069:8069"
    volumes:
      - ./addons:/mnt/extra-addons
      - odoo-data:/var/lib/odoo
    restart: unless-stopped

  db:
    image: postgres:16
    container_name: odoo18_db
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo -d postgres"]
      interval: 5s
      timeout: 5s
      retries: 10
    restart: unless-stopped

volumes:
  odoo-data:
  db-data:
```

Penjelasan singkat:

| Bagian | Fungsi |
|--------|--------|
| `HOST`, `PORT`, `USER`, `PASSWORD` | Variabel yang dibaca image resmi `odoo` untuk koneksi ke PostgreSQL. Nilainya harus cocok dengan `POSTGRES_*` di service `db`. |
| `./addons:/mnt/extra-addons` | Folder module custom kamu (bind mount, jadi bisa diedit langsung dari host). |
| `odoo-data:/var/lib/odoo` | Filestore Odoo (attachment, session, dsb). Kalau hilang, file lampiran ikut hilang. |
| `db-data` | Data PostgreSQL. |
| `healthcheck` + `condition: service_healthy` | Odoo baru start setelah PostgreSQL siap, jadi tidak ada error koneksi saat boot pertama. |
| `POSTGRES_DB=postgres` | Database bawaan saja. Database Odoo dibuat dari browser (lihat bawah), jangan dibuat di sini supaya tidak bentrok. |

> Compose v2 tidak memakai key `version:` lagi, jadi baris itu sengaja tidak ada. Kalau kamu menemukan `version: "3.8"` di tutorial lain, boleh dihapus.

> **Beda di Odoo 19:** ganti tag image menjadi `odoo:19.0` (dan sebaiknya nama container, mis. `odoo19_dev`). `postgres:16` tetap bisa dipakai. Syarat minimum versi PostgreSQL dan Python ada di Bab 2.

Konfigurasi lebih lanjut (file `odoo.conf`, dev mode, password master) dibahas di [Bab 2](02-install-config.md).

## Menjalankan Container

```bash
# Start semua service di background
docker compose up -d

# Cek status
docker compose ps

# Lihat log (Ctrl+C untuk keluar, container tetap jalan)
docker compose logs -f odoo

# Stop (data tetap aman di volume)
docker compose down
```

Untuk menghapus data sama sekali (reset total), lihat bagian "Reset Database" di Bab 2.

## Akses Odoo Pertama Kali

1. Buka http://localhost:8069
2. Di halaman "Create Database", isi:
   - **Master Password**: password untuk manajemen database (catat baik-baik).
   - **Database Name**: pakai `odoo` (nama ini dipakai di seluruh contoh materi ini).
   - **Email** dan **Password**: akun admin Odoo. Email ini jadi username login.
3. Klik **Create Database** dan tunggu proses selesai.

## Memasang Module dari Folder addons

Setiap folder module yang ditaruh di `./addons` otomatis terbaca oleh container. Supaya muncul di daftar:

1. Aktifkan developer mode (Settings > Activate the developer mode).
2. Buka Apps > **Update Apps List**.
3. Cari module, klik Install.

Cara install/upgrade lewat CLI dan alur kerja lengkapnya ada di [Bab 3](03-module-structure.md).

## Perintah Harian

```bash
# Restart Odoo (mis. setelah edit kode Python)
docker compose restart odoo

# Masuk ke shell container Odoo
docker compose exec odoo bash

# Masuk ke psql (ganti odoo dengan nama database kamu)
docker compose exec db psql -U odoo -d odoo
```

Catatan penting:
- Odoo **tidak** otomatis reload kode Python hanya karena kamu menyimpan file. Pilihannya: restart container, atau aktifkan dev mode `reload` (dibahas di Bab 2).
- Image resmi hanya membaca `HOST`, `PORT`, `USER`, `PASSWORD` dari environment. Opsi lain seperti log level **tidak** bisa diset lewat env var; pakai `odoo.conf` atau argumen perintah (Bab 2).

## Ringkasan

- Satu `docker-compose.yml` berisi dua service: `odoo` (image `odoo:18.0`) dan `db` (`postgres:16`).
- `HOST/PORT/USER/PASSWORD` di service `odoo` harus cocok dengan `POSTGRES_*` di service `db`.
- Module custom ditaruh di `./addons`, dipetakan ke `/mnt/extra-addons` di container.
- Filestore Odoo dan data PostgreSQL disimpan di named volume, jadi aman saat container dibuat ulang.
- Database Odoo dibuat lewat browser pada akses pertama ke http://localhost:8069.
- Perintah harian: `up -d`, `ps`, `logs -f`, `restart`, `down`, `exec`.

## Latihan

1. Buat folder project dan `docker-compose.yml` di atas, jalankan `docker compose up -d`, lalu pastikan `docker compose ps` menunjukkan kedua service berjalan (service `db` berstatus healthy).
2. Buka http://localhost:8069, buat database bernama `odoo`, lalu login sebagai admin.
3. Masuk ke psql dengan `docker compose exec db psql -U odoo -d odoo` dan jalankan `\dt` untuk melihat tabel yang dibuat Odoo. Keluar dengan `\q`.

## Lanjut ke

[Bab 2: Install & Konfigurasi Odoo](02-install-config.md)
