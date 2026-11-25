# Bab 2: Install & Konfigurasi Odoo

> **Tahap:** 1 Persiapan | **Prasyarat:** Bab 1 | **Estimasi:** ± 1,5 jam | **Versi:** Odoo 18 (catatan Odoo 19)

## Tujuan Belajar

Setelah bab ini kamu bisa:
- Membuat dan memasang `odoo.conf` ke container, serta memahami urutan prioritas konfigurasi.
- Mengaktifkan dev mode yang tepat untuk development.
- Memakai CLI Odoo (`-i`, `-u`, `shell`, `--stop-after-init`) lewat `docker compose exec`.
- Melakukan backup, restore, dan reset database.
- Mengecek persyaratan versi Python dan PostgreSQL untuk Odoo 18 dan 19.

> Setup `docker-compose.yml` dasar ada di [Bab 1](01-docker-setup.md). Bab ini hanya membahas konfigurasi Odoo, CLI, dan manajemen database.

## Dari Mana Odoo Membaca Konfigurasi?

Ada tiga sumber, urutan prioritas dari tertinggi:

1. **Argumen CLI** (`--db_host=db`, `-d odoo`, dst).
2. **File `odoo.conf`**.
3. **Default bawaan Odoo**.

Image resmi Docker juga menerjemahkan env var `HOST`, `PORT`, `USER`, `PASSWORD` menjadi argumen `--db_host`, dst saat container start. Itu sebabnya Bab 1 bisa jalan tanpa `odoo.conf`.

## odoo.conf

Buat file `config/odoo.conf` di folder project:

```ini
[options]
admin_passwd = ganti_dengan_password_kuat
db_host = db
db_port = 5432
db_user = odoo
db_password = odoo
addons_path = /mnt/extra-addons
data_dir = /var/lib/odoo

; Development
dev_mode = reload,xml
log_level = debug

; Server
limit_time_cpu = 60
limit_time_real = 120
max_cron_threads = 2
workers = 0
```

Lalu tambahkan satu baris di `volumes:` service `odoo` pada `docker-compose.yml` dari Bab 1:

```yaml
    volumes:
      - ./addons:/mnt/extra-addons
      - odoo-data:/var/lib/odoo
      - ./config/odoo.conf:/etc/odoo/odoo.conf
```

Buat file `config/odoo.conf` **sebelum** `docker compose up`, kalau tidak Docker akan membuat folder kosong dengan nama itu.

Catatan:
- `data_dir = /var/lib/odoo` wajib ada. Tanpa itu, filestore ditulis ke luar volume `odoo-data` dan hilang saat container dibuat ulang.
- `db_name` sengaja tidak diisi; database dipilih lewat browser atau argumen `-d`.
- `admin_passwd` adalah master password untuk membuat/menghapus/backup database lewat halaman database manager. Jangan pakai nilai contoh di server sungguhan.

## Opsi odoo.conf yang Penting

| Opsi | Fungsi |
|------|--------|
| `admin_passwd` | Master password untuk operasi database manager |
| `db_host`, `db_port`, `db_user`, `db_password` | Koneksi PostgreSQL |
| `addons_path` | Daftar folder module (pisahkan dengan koma) |
| `data_dir` | Lokasi filestore dan session |
| `dev_mode` | Fitur development (lihat bagian berikut) |
| `log_level` | Level logging (`info`, `debug`, `warn`, `error`) |
| `workers` | `0` = mode threaded satu proses (cocok untuk development); `>0` = multiprocessing untuk production |
| `limit_time_cpu`, `limit_time_real` | Batas waktu CPU dan waktu nyata per request (detik) |
| `max_cron_threads` | Jumlah thread untuk scheduled action |
| `list_db` | `False` menyembunyikan database manager (disarankan di production) |

## Dev Mode

`dev_mode` menerima daftar fitur dipisah koma:

| Nilai | Efek |
|-------|------|
| `reload` | Server restart otomatis saat file Python berubah |
| `xml` | View XML dibaca langsung dari file di disk, jadi perubahan view tidak perlu upgrade module |
| `qweb` | Mengaktifkan debug template QWeb |
| `all` | Menyalakan beberapa fitur sekaligus |

Untuk belajar, `reload,xml` sudah cukup dan lebih mudah diprediksi daripada `all`. Perubahan **field model** tetap butuh upgrade module (`-u`), dev mode tidak mengubah itu.

Dev mode di server (opsi `dev_mode`) berbeda dengan debug mode di browser (`?debug=1` di URL atau tombol di Settings), yang hanya menampilkan menu teknis dan info debug di UI.

## CLI Odoo di Dalam Container

Karena `odoo.conf` sudah berisi koneksi database, perintah `odoo` di bawah ini tidak perlu argumen `--db_host` lagi:

```bash
# Odoo shell (Python interaktif dengan env siap pakai)
docker compose exec odoo odoo shell -d odoo

# Install module
docker compose exec odoo odoo -d odoo -i nama_module --stop-after-init

# Upgrade module (setelah edit kode)
docker compose exec odoo odoo -d odoo -u nama_module --stop-after-init
```

`--stop-after-init` membuat proses tambahan ini berhenti setelah selesai, supaya tidak bentrok dengan server utama yang sudah memakai port 8069. Setelah upgrade, restart server utama dengan `docker compose restart odoo`.

Di dalam `odoo shell`, perubahan data baru tersimpan kalau kamu panggil `env.cr.commit()`.

## Manajemen Database

### Masuk ke PostgreSQL

```bash
docker compose exec db psql -U odoo -d odoo
```

Di dalam psql:

```sql
SELECT name, state FROM ir_module_module WHERE name = 'base';
\q
```

### Backup dan Restore

```bash
# Backup struktur + data tabel
docker compose exec db pg_dump -U odoo odoo > backup.sql

# Restore ke database yang sudah ada (kosong)
cat backup.sql | docker compose exec -T db psql -U odoo -d odoo
```

`pg_dump` hanya menyimpan isi database. File lampiran ada di filestore (volume `odoo-data`), jadi backup lengkap harus menyertakan keduanya. Cara paling mudah: pakai database manager di http://localhost:8069/web/database/manager, yang membuat backup zip berisi dump dan filestore (butuh `admin_passwd`).

### Reset Database

```bash
# Hapus container DAN semua named volume (data hilang permanen)
docker compose down -v

# Start ulang dari kosong
docker compose up -d
```

## Persyaratan Versi

| | Odoo 18 | Odoo 19 |
|---|---|---|
| PostgreSQL minimum | 12 | 13 |
| Python minimum | 3.10 | 3.10 |

Image `postgres:16` dari Bab 1 memenuhi keduanya. Karena kamu memakai image resmi Odoo, versi Python sudah diurus oleh image.

Bab ini dan Bab 1 memakai Docker. Kalau kamu perlu memasang Odoo langsung di server Linux (paket `.deb` atau dari source, lengkap dengan contoh unit systemd), lihat [Bab 20, bagian 13](20-deployment-performance.md). Persyaratan versi di atas berlaku sama.

> **Beda di Odoo 19:** PostgreSQL minimum naik ke 13. Untuk menjalankan 19, ganti tag image ke `odoo:19.0` dan gunakan database baru, jangan menunjuk ke database Odoo 18 tanpa proses upgrade.

## Troubleshooting

**Container Odoo tidak start:**
```bash
docker compose logs odoo
```

**Error koneksi database:**
```bash
docker compose exec db pg_isready -U odoo
```
Pastikan `db_host`/`HOST` bernilai `db` (nama service, bukan `localhost`) dan user/password sama dengan di service `db`.

**Port 8069 sudah dipakai:** ubah mapping jadi `"8070:8069"` atau hentikan proses lain yang memakai port itu.

**Perubahan di `odoo.conf` tidak berlaku:** restart dengan `docker compose restart odoo`, dan pastikan baris mount `./config/odoo.conf` ada.

## Ringkasan

- Prioritas konfigurasi: argumen CLI, lalu `odoo.conf`, lalu default.
- `odoo.conf` dipasang ke `/etc/odoo/odoo.conf`; jangan lupa `data_dir = /var/lib/odoo` supaya filestore ikut volume.
- `dev_mode = reload,xml` cukup untuk development; field baru tetap butuh `-u`.
- `workers = 0` berarti mode threaded (development), bukan "tanpa thread".
- Jalankan CLI tambahan dengan `--stop-after-init` agar tidak bentrok dengan server utama.
- Backup lengkap = dump database + filestore (atau database manager).
- Odoo 18 butuh PostgreSQL 12+, Odoo 19 butuh PostgreSQL 13+; keduanya Python 3.10+.

## Latihan

1. Buat `config/odoo.conf`, pasang di compose, restart, lalu buktikan opsi `log_level = debug` aktif dengan melihat `docker compose logs odoo`.
2. Buka `odoo shell`, jalankan `env['res.partner'].search_count([])`, lalu keluar dengan Ctrl+D.
3. Buat backup `pg_dump`, lakukan `docker compose down -v` dan `up -d`, buat database kosong dengan `docker compose exec db createdb -U odoo odoo`, lalu restore dari `backup.sql` (jangan buat database lewat browser, karena itu sudah mengisi tabel Odoo).

## Lanjut ke

[Bab 3: Struktur Module Odoo](03-module-structure.md)
