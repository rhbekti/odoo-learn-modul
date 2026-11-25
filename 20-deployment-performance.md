# Bab 20: Deployment & Performance

> **Tahap:** 5 Profesional | **Prasyarat:** Bab 1, 2, 4, 10 | **Estimasi:** ± 5 jam | **Versi:** Odoo 18 (catatan Odoo 19)

## Tujuan Belajar

Setelah bab ini kamu bisa:
- Menjelaskan beda mode threaded (development) dan multiprocessing (production), lalu menghitung `workers` dan memori awal.
- Menyusun stack production: Odoo + PostgreSQL + Nginx dengan HTTPS, `proxy_mode`, dan jalur websocket.
- Mengamankan instalasi (`dbfilter`, `list_db`, `admin_passwd`) dan membuat backup/restore yang lengkap.
- Meng-update module di production dengan urutan yang aman.
- Menerapkan optimasi dasar: stored computed field, batch/`_read_group`, SQL aman, index, dan tuning PostgreSQL awal.
- Memakai cache registry (`@tools.ormcache`) dengan benar, termasuk invalidasinya, dan membedakannya dari cache record (`invalidate_model`/`invalidate_recordset`).
- Menemukan query lambat lewat `pg_stat_statements` dan `log_min_duration_statement`, serta membaca log worker Odoo.
- Memasang Odoo tanpa Docker (paket `.deb` atau dari source) dan menjalankannya sebagai service systemd di belakang Nginx.
- Merencanakan upgrade antar versi mayor: upgrade modul custom (migration script), alur Odoo upgrade service, dan strategi uji di salinan database.

> Compose dasar ada di [Bab 1](01-docker-setup.md), sedangkan `odoo.conf`, CLI, dan backup sederhana ada di [Bab 2](02-install-config.md). Bab ini hanya membahas apa yang **berubah** saat naik ke production. Bagian 11 sampai 14 adalah topik lanjutan yang berdiri sendiri; kerjakan setelah bagian 1 sampai 10 jika waktumu terbatas.

---

## 1. Dari Development ke Production

Odoo punya dua mode server:

| | Threaded (default) | Multiprocessing (production) |
|---|---|---|
| Aktif jika | `workers = 0` | `workers` bukan 0 |
| Cara kerja | Satu proses, satu thread per request | Pool worker proses; request antre di OS sampai ada worker kosong |
| Cron | Thread tambahan | Worker cron tambahan |
| Live chat / websocket | Lewat port HTTP biasa | Worker terpisah di `gevent_port` (default 8072) |
| Pemakaian | Development, demo (bisa di Windows) | Production (hanya Linux) |

Di mode multiprocessing ada "process reaper" yang mematikan dan me-restart worker yang melewati batas memori atau waktu. Batas-batas itulah yang kamu atur di `odoo.conf`.

---

## 2. Compose Production

Perbedaan utama dari compose development di Bab 1:
- Odoo dan PostgreSQL **tidak** membuka port ke host; hanya Nginx yang terbuka (80/443).
- Password dibaca dari file `.env` (jangan di-commit ke git).
- Ada service `nginx`, dan `odoo.conf` dipasang dari folder `config/`.
- Tidak ada `version:` (usang di Compose v2).

```yaml
services:
  odoo:
    image: odoo:18.0
    depends_on:
      db:
        condition: service_healthy
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=${DB_PASSWORD}
    expose:
      - "8069"   # HTTP
      - "8072"   # websocket (gevent)
    volumes:
      - odoo-data:/var/lib/odoo
      - ./addons:/mnt/extra-addons
      - ./config/odoo.conf:/etc/odoo/odoo.conf
    restart: unless-stopped

  db:
    image: postgres:16
    environment:
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=postgres
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo -d postgres"]
      interval: 5s
      timeout: 5s
      retries: 10
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/odoo.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
    depends_on:
      - odoo
    restart: unless-stopped

volumes:
  odoo-data:
  db-data:
```

File `.env` di samping `docker-compose.yml`:

```
DB_PASSWORD=isi_dengan_password_acak_yang_kuat
```

Credential database sengaja **tidak** ditulis di `odoo.conf` supaya hanya ada satu sumber (env var dari `.env`).

---

## 3. odoo.conf Production

```ini
[options]
; Database (credential datang dari env var di compose)
db_host = db
db_port = 5432
db_name = production_db
dbfilter = ^production_db$
list_db = False

; Addons (path bawaan image resmi odoo)
addons_path = /mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons
data_dir = /var/lib/odoo

; Multiprocessing
workers = 4
max_cron_threads = 1
limit_memory_soft = 2147483648
limit_memory_hard = 2684354560
limit_time_cpu = 600
limit_time_real = 1200
limit_request = 8192

; Di belakang reverse proxy
proxy_mode = True
gevent_port = 8072

; Log (stdout, dibaca lewat `docker compose logs`)
log_level = warn

; Master password (lihat bagian Keamanan)
admin_passwd = ganti_dengan_nilai_acak_atau_hash
```

Catatan:
- Opsi `xmlrpc_interface` dan `longpolling_port` dari versi lama **tidak dipakai lagi**. Di Odoo 18 namanya `http_interface` dan `http_port` (default `0.0.0.0` dan 8069, tidak perlu diisi di Docker). Port websocket diatur `gevent_port` (default 8072).
- Di Docker, log paling mudah ke stdout (tanpa `logfile`) lalu dikelola oleh Docker. Kalau tetap memakai `logfile`, rotasi file diurus `logrotate` di sisi host/volume.

### Arti parameter performance

| Parameter | Fungsi | Default (dok. 18) |
|-----------|--------|-------------------|
| `workers` | Jumlah worker HTTP (0 = threaded) | 0 |
| `max_cron_threads` | Jumlah worker cron (tambahan di luar worker HTTP) | 2 |
| `limit_memory_soft` | Memori virtual per worker; jika lewat, worker di-recycle di akhir request | 2048 MiB |
| `limit_memory_hard` | Batas keras; worker langsung dimatikan | 2560 MiB |
| `limit_time_cpu` | Maksimum detik CPU per request | 60 |
| `limit_time_real` | Maksimum detik nyata (wall time, termasuk SQL) per request | 120 |
| `limit_request` | Jumlah request sebelum worker di-recycle | sekitar 8196 |

Nilai pada contoh di atas (600/1200 detik) sengaja lebih longgar dari default untuk laporan dan import besar. Mulai dari default, naikkan hanya jika memang ada request sah yang terpotong.

### Menghitung `workers` dan memori

Dokumentasi resmi memberi aturan praktis:
- `(jumlah CPU * 2) + 1` sebagai batas atas teoretis jumlah worker.
- Satu worker melayani kira-kira 6 user bersamaan.
- Worker cron juga butuh CPU.
- Perkiraan RAM: `workers * ((0,8 * 150 MB) + (0,2 * 1 GB))`. Asumsinya 20% request berat (sekitar 1 GB) dan 80% ringan (sekitar 150 MB).

Contoh: server 4 CPU, 60 user bersamaan. Kebutuhan teoretis 60/6 = 10 worker, batas atas (4*2)+1 = 9. Pilih 8 worker (+ cron), RAM sekitar 3 GB hanya untuk Odoo. Ini titik awal; pantau beban CPU dan sesuaikan.

---

## 4. Nginx, HTTPS, dan Websocket

Odoo mengirim data login tanpa enkripsi sendiri, jadi production **wajib** HTTPS. Pola yang dipakai: Nginx menerima HTTPS lalu meneruskan ke Odoo, dan Odoo dijalankan dengan `proxy_mode = True` supaya memakai header `X-Forwarded-*` (host, skema, IP asli).

> Peringatan: `proxy_mode` hanya boleh aktif jika Odoo benar-benar di belakang reverse proxy dan port Odoo tidak terbuka ke internet. Karena itu compose di atas memakai `expose`, bukan `ports`.

```nginx
# nginx/odoo.conf
upstream odoo {
    server odoo:8069;
}

upstream odoochat {
    server odoo:8072;
}

map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

# HTTP -> HTTPS
server {
    listen 80;
    server_name odoo.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name odoo.example.com;

    ssl_certificate     /etc/letsencrypt/live/odoo.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/odoo.example.com/privkey.pem;
    ssl_session_timeout 30m;

    proxy_read_timeout    720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout    720s;

    client_max_body_size 100m;

    proxy_set_header Host              $host;
    proxy_set_header X-Forwarded-Host  $http_host;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP         $remote_addr;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";

    # Websocket (live chat, notifikasi) -> worker gevent
    location /websocket {
        proxy_pass http://odoochat;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
    }

    # Selain itu -> worker HTTP biasa
    location / {
        proxy_redirect off;
        proxy_pass http://odoo;
    }

    gzip on;
    gzip_types text/css text/plain text/xml application/xml application/json application/javascript;
}
```

Poin penting:
- `location /websocket` harus menuju `gevent_port` (8072). Tanpa ini, fitur real-time (chat, notifikasi bus) tidak jalan di mode multiprocessing.
- `proxy_read_timeout` 720 detik mengikuti contoh dokumentasi resmi, supaya request panjang (laporan, import) tidak diputus Nginx.
- Header `Strict-Transport-Security` baru dipasang setelah HTTPS stabil, karena browser akan menolak HTTP biasa selama setahun.

### Sertifikat Let's Encrypt (certbot)

Salah satu cara paling umum untuk mendapat sertifikat gratis (jalankan di host, sebelum Nginx di compose menyala karena butuh port 80):

```bash
sudo certbot certonly --standalone -d odoo.example.com
```

Sertifikat tersimpan di `/etc/letsencrypt/live/odoo.example.com/` (sudah di-mount ke container Nginx pada compose di atas). Setelah sertifikat diperpanjang, muat ulang Nginx: `docker compose exec nginx nginx -s reload`.

---

## 5. Keamanan Dasar

| Langkah | Alasan |
|---------|--------|
| `dbfilter = ^production_db$` | Odoo hanya melayani database yang cocok dengan regex. Wajib jika ada banyak database di server yang sama. |
| `list_db = False` | Menyembunyikan daftar database dan layar database manager. |
| `admin_passwd` acak dan kuat | Hanya dicek sebelum operasi database manager; hanya bisa diatur lewat file konfigurasi. |
| User PostgreSQL bukan superuser | Peringatan eksplisit di dokumentasi resmi. |
| `proxy_mode = True` + HTTPS | Lihat bagian 4. |

`admin_passwd` bisa ditulis sebagai teks biasa atau dalam bentuk hash (`$pbkdf2-sha512$...`). Jangan memakai nilai contoh dari tutorial.

---

## 6. Backup & Restore

Backup lengkap = **dump database + filestore** (alasannya ada di [Bab 2](02-install-config.md)). Gunakan `-T` pada `docker compose exec` setiap kali ada pipe atau redirect, supaya output tidak rusak oleh TTY.

### Script backup

```bash
#!/bin/bash
# backup.sh - jalankan dari folder yang berisi docker-compose.yml
BACKUP_DIR="/backups/odoo"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="production_db"

mkdir -p "$BACKUP_DIR"

# 1. Database
docker compose exec -T db pg_dump -U odoo "$DB_NAME" | gzip > "$BACKUP_DIR/${DB_NAME}_${DATE}.sql.gz"

# 2. Filestore
docker compose exec -T odoo tar czf - -C /var/lib/odoo/filestore "$DB_NAME" > "$BACKUP_DIR/filestore_${DB_NAME}_${DATE}.tar.gz"

# 3. Hapus backup lebih dari 30 hari
find "$BACKUP_DIR" -type f -mtime +30 -delete

echo "Backup selesai: $DATE"
```

Jadwalkan dengan cron di host, misalnya setiap hari pukul 02:00: `0 2 * * * cd /path/ke/project && ./backup.sh`. Simpan salinan di luar server yang sama, dan **uji restore** secara berkala; backup yang tidak pernah dicoba belum bisa dianggap ada.

### Restore

```bash
# Hentikan Odoo supaya tidak ada koneksi aktif ke database
docker compose stop odoo

# Buat ulang database kosong
docker compose exec -T db dropdb -U odoo --if-exists production_db
docker compose exec -T db createdb -U odoo production_db

# Restore dump
gunzip < production_db_20260518_020000.sql.gz | docker compose exec -T db psql -U odoo -d production_db

# Restore filestore
docker compose exec -T odoo tar xzf - -C /var/lib/odoo/filestore < filestore_production_db_20260518_020000.tar.gz

docker compose start odoo
```

Alternatif yang lebih mudah untuk database kecil: database manager Odoo (backup zip berisi dump + filestore). Karena `list_db = False` menyembunyikannya, aktifkan hanya sementara jika perlu.

---

## 7. Update Module di Production

```bash
# 1. Backup dulu (jalankan backup.sh)

# 2. Tarik kode terbaru
cd addons && git pull origin main && cd ..

# 3. Upgrade module yang berubah
docker compose exec odoo odoo -d production_db -u library_management --stop-after-init

# 4. Restart server utama
docker compose restart odoo
```

Urutan ini sama dengan di Bab 2. Tambahan untuk production:
- Coba dulu di staging dengan salinan database production.
- Gunakan `-u all` hanya jika memang perlu (lambat dan berisiko); biasanya `-u nama_module` cukup.
- Cek log setelah restart: `docker compose logs --tail=100 odoo`.

---

## 8. Optimasi Performance

Urutan prioritas: **ukur dulu**, perbaiki query/logika yang lambat, baru tuning server.

### 8.1 Stored computed field

```python
# Tanpa store: dihitung setiap kali diakses
total = fields.Float(compute='_compute_total')

# Dengan store: dihitung saat dependency berubah, lalu disimpan di database
total = fields.Float(compute='_compute_total', store=True)
```

Pakai `store=True` jika field sering tampil di list view, dipakai untuk search/filter/group by, dan dependency-nya jarang berubah. Jangan pakai jika dependency sangat sering berubah atau hitungannya sangat ringan. Ingat juga: field yang bergantung pada tanggal hari ini tidak cocok di-store, karena nilainya basi besok (contoh `is_overdue` di Bab 10).

### 8.2 Hindari query di dalam loop (N+1)

Odoo sudah melakukan prefetch: membaca field relasi di dalam loop atas satu recordset **tidak** menghasilkan satu query per record. Yang mahal adalah memanggil `search()` atau `search_count()` di dalam loop.

```python
# LAMBAT: satu query per buku
for book in books:
    copies = self.env['library.book.copy'].search([('book_id', '=', book.id)])

# CEPAT: satu query untuk semua buku
all_copies = self.env['library.book.copy'].search([('book_id', 'in', books.ids)])
copies_by_book = {}
for copy in all_copies:
    copies_by_book.setdefault(copy.book_id.id, self.env['library.book.copy'])
    copies_by_book[copy.book_id.id] |= copy
```

### 8.3 Agregasi dengan `_read_group`

```python
# LAMBAT: baca semua record, hitung di Python
loans = self.env['library.loan'].search([('state', '=', 'active')])
by_member = {}
for loan in loans:
    by_member[loan.member_id.id] = by_member.get(loan.member_id.id, 0) + 1

# CEPAT: GROUP BY di database
rows = self.env['library.loan']._read_group(
    domain=[('state', '=', 'active')],
    groupby=['member_id'],
    aggregates=['__count'],
)
by_member = {member.id: count for member, count in rows}
```

Hasil `_read_group` berupa list tuple; untuk Many2one nilainya sudah berupa record (lihat [Bab 4](04-models-orm.md)).

### 8.4 SQL langsung (hanya jika ORM tidak cukup)

```python
def _get_active_loan_statistics(self):
    # ORM menyimpan perubahan di cache; tulis dulu ke database sebelum SQL mentah
    self.env.flush_all()
    self.env.cr.execute("""
        SELECT m.id AS member_id,
               COUNT(l.id) AS loan_count
          FROM library_loan l
          JOIN library_member m ON l.member_id = m.id
         WHERE l.state = %s
         GROUP BY m.id
         ORDER BY loan_count DESC
    """, ('active',))
    return self.env.cr.dictfetchall()
```

Aturan SQL mentah:
- Selalu kirim nilai lewat parameter `%s` dan argumen kedua `execute`, **jangan** menyisipkan nilai dengan f-string atau `%` (risiko SQL injection; lihat [Bab 21](21-tips-best-practices.md)).
- SQL mentah melewati access rights dan record rule. Pakai hanya jika ORM benar-benar tidak efisien.
- Setelah SQL yang mengubah data, cache record di ORM perlu di-invalidate (lihat Bab 4 dan bedanya dengan cache registry di bagian 11).
- Untuk menyusun query dengan aman, pakai `odoo.tools.SQL` (lihat [Bab 15](15-database-views-filtering.md), subbagian "Query SQL Aman dengan `odoo.tools.SQL`").

### 8.5 Index

```python
isbn = fields.Char(index=True)
state = fields.Selection([...], index=True)
loan_date = fields.Date(index=True)
member_id = fields.Many2one('library.member', index=True)
```

Beri `index=True` pada field yang sering muncul di domain/filter/order. Jangan asal menambah index: setiap index memperlambat tulis dan memakan ruang.

### 8.6 Tuning PostgreSQL (titik awal)

Contoh untuk server khusus 8 GB RAM, bisa dipasang lewat `command` di service `db`:

```yaml
  db:
    image: postgres:16
    command: >
      postgres
      -c shared_buffers=2GB
      -c effective_cache_size=6GB
      -c work_mem=64MB
      -c maintenance_work_mem=512MB
      -c random_page_cost=1.1
      -c max_connections=200
```

`random_page_cost=1.1` hanya untuk SSD. Angka-angka ini bukan rekomendasi resmi Odoo; anggap titik awal lalu ukur. `work_mem` dipakai per operasi (bukan per koneksi), jadi nilai besar dikalikan banyak koneksi bisa menghabiskan RAM. `max_connections` harus cukup untuk semua worker Odoo (lihat `db_maxconn`, batas koneksi per proses Odoo).

---

## 9. Monitoring & Logging

### Logging di kode

```python
import logging
_logger = logging.getLogger(__name__)

class LibraryLoan(models.Model):
    _inherit = 'library.loan'

    def action_confirm(self):
        for loan in self:
            _logger.info('Confirming loan %s for member %s', loan.name, loan.member_id.name)
        return super().action_confirm()
```

Beri argumen terpisah pada `_logger.info('... %s', value)`, jangan format string sendiri. Untuk error di blok `except`, `_logger.exception(...)` ikut mencatat traceback.

| Level | Kapan dipakai |
|-------|---------------|
| `debug` | Detail teknis (development) |
| `info` | Event bisnis normal |
| `warning` | Tidak ideal, tapi bukan error |
| `error` | Perlu diinvestigasi |
| `critical` | Sistem tidak bisa jalan |

### Level log di `odoo.conf`

```ini
log_level = info

; level per logger: nama:LEVEL, dipisah koma
log_handler = :WARNING,odoo.addons.library_management:DEBUG

; Log SQL (hanya saat debugging, sangat verbose)
; log_handler = odoo.sql_db:DEBUG
```

Production umumnya `log_level = warn` atau `info`; naikkan ke `debug` per module saja saat menyelidiki masalah (lihat [Bab 18](18-debugging-troubleshooting.md)).

---

## 10. Checklist Deployment

```
[ ] Backup database + filestore sebelum deploy, dan restore pernah diuji
[ ] Update dicoba di staging dengan salinan data production
[ ] Image dikunci ke versi (odoo:18.0, postgres:16), bukan "latest"
[ ] workers > 0, batas memori/waktu diatur, max_cron_threads sesuai
[ ] proxy_mode = True, Odoo tidak terbuka langsung ke internet
[ ] Nginx + HTTPS aktif, jalur /websocket menuju gevent_port
[ ] dbfilter diatur dan list_db = False
[ ] admin_passwd acak dan kuat; password database dari .env
[ ] Backup otomatis terjadwal (cron) dan salinan disimpan di luar server
[ ] log_level sesuai (warn/info), log dipantau
[ ] Tidak ada flag --dev / dev_mode di production
[ ] Semua fungsi utama dicek setelah deploy
[ ] Method ber-@ormcache punya invalidasi di create/write/unlink (bagian 11)
[ ] Slow query log atau pg_stat_statements aktif, dan log worker pernah dibaca (bagian 12)
[ ] Instalasi non-Docker: service systemd/paket jalan, port Odoo hanya di localhost (bagian 13)
[ ] Rencana upgrade versi mayor: uji di salinan database, migration script, rehearsal (bagian 14)
```

Checklist untuk kode module (sebelum deploy) ada di [Bab 21](21-tips-best-practices.md).

---

## 11. Cache ORM: `@tools.ormcache`

Odoo punya dua jenis cache yang namanya mirip tapi bekerja berbeda. Mencampuradukkannya adalah sumber bug yang umum.

| | Cache record/field | Cache registry (`ormcache`) |
|---|---|---|
| Isi | Nilai field record yang sudah dibaca/ditulis | Hasil method yang diberi `@tools.ormcache` |
| Umur | Mengikuti `Environment`/transaksi | Selama registry hidup di proses worker itu |
| Dibersihkan dengan | `invalidate_model()` / `invalidate_recordset()` (Bab 4) | `self.env.registry.clear_cache()` |
| Dipakai untuk | Menghindari baca ulang field dalam satu transaksi | Menghindari menghitung ulang lookup yang jarang berubah, lintas request |

`invalidate_*` tidak menyentuh `ormcache`, dan `clear_cache()` tidak menyentuh cache record.

### 11.1 Contoh: lookup tarif denda

Misal tarif denda per hari ditentukan per kategori buku lewat model baru `library.fine.rule` (contoh tambahan, bukan bagian Bab 10). Method pencarinya dipanggil setiap kali denda dihitung, sedangkan aturannya jarang berubah, jadi cocok di-cache.

```python
from odoo import api, fields, models, tools


class LibraryFineRule(models.Model):
    _name = 'library.fine.rule'
    _description = 'Aturan Denda per Kategori'

    category_id = fields.Many2one('library.book.category', required=True, ondelete='cascade')
    daily_rate = fields.Float(required=True)

    @api.model
    @tools.ormcache('category_id')
    def _get_daily_rate(self, category_id):
        # sudo: hasil di-cache untuk semua user, jangan bergantung pada record rule user tertentu
        rule = self.sudo().search([('category_id', '=', category_id)], limit=1)
        return rule.daily_rate   # float biasa, bukan recordset

    @api.model_create_multi
    def create(self, vals_list):
        rules = super().create(vals_list)
        self.env.registry.clear_cache()
        return rules

    def write(self, vals):
        result = super().write(vals)
        self.env.registry.clear_cache()
        return result

    def unlink(self):
        result = super().unlink()
        self.env.registry.clear_cache()
        return result
```

Cara membacanya:
- Argumen decorator adalah **string ekspresi** yang merujuk ke parameter method. `'category_id'` membuat kunci cache berbeda untuk tiap kategori. Nama model dan method otomatis ikut dalam kunci.
- Apa pun yang memengaruhi hasil tetapi tidak ada di kunci akan "bocor" antar pemanggil. Kalau hasil bergantung pada user atau company, tambahkan ekspresi seperti `'self.env.uid'` atau `'self.env.company.id'`, atau (seperti contoh) pakai `sudo()` supaya hasilnya memang sama untuk semua.
- **Jangan mengembalikan recordset.** Docstring `ormcache` di source menyatakan hal ini karena cursor di baliknya akhirnya ditutup. Kembalikan nilai biasa: angka, string, tuple, atau list id.
- Objek yang sama dikembalikan ke setiap pemanggil, jadi jangan memodifikasi hasilnya (pakai tuple atau nilai primitif).
- Pemanggilan `self.env['library.fine.rule']._get_daily_rate(category.id)` yang pertama menjalankan query, berikutnya langsung dari memori sampai cache dibersihkan.

### 11.2 Invalidasi: nama API yang benar

| API | Status |
|-----|--------|
| `self.env.registry.clear_cache()` | Dipakai di 18 maupun 19. Tanpa argumen membersihkan cache bernama `'default'`. |
| `self.env.registry.clear_all_caches()` | Ada di 18 dan 19; membersihkan semua cache `ormcache`. |
| `ormcache.clear(model, *args)` | Di 18 sudah deprecated; source-nya mengarahkan ke `registry.clear_cache()`. |

Pola ini juga dipakai kode inti, misalnya model `res.lang` memanggil `self.env.registry.clear_cache()` di create/write/unlink-nya (Odoo 18).

Catatan penting:
- `clear_cache()` membersihkan cache **semua** method `@ormcache` di grup itu, bukan hanya milikmu. Jangan memanggilnya di jalur yang sering (mis. tiap peminjaman); taruh hanya di perubahan data konfigurasi yang jarang.
- Kalau kamu mengubah tabel lewat SQL mentah, ORM tidak tahu. Panggil `clear_cache()` sendiri (dan `invalidate_model()` untuk cache record).
- `@tools.ormcache_context('category_id', keys=('lang',))` ada di Odoo 18: nilai `lang` dari context ikut menjadi kunci. Gunakan hanya jika hasil memang bergantung pada context.

> **Beda di Odoo 19:** `ormcache_context` memberi `DeprecationWarning`; pakai `@tools.ormcache('category_id', 'self.env.context.get("lang")')`. Parameter `skiparg` juga deprecated. Odoo 19 menambah nama cache `'stable'` untuk data yang hampir tidak berubah (`@tools.ormcache(..., cache='stable')` dan `clear_cache('stable')`, dipakai `res.lang`). `clear_cache()` tanpa argumen tetap untuk `'default'`.

### 11.3 Cache dan multi-worker

Setiap worker adalah proses terpisah dengan cache registry sendiri di memorinya. Supaya perubahan di satu worker sampai ke yang lain, Odoo memakai sequence di database sebagai sinyal (urutannya sesuai source Odoo 18):

1. `clear_cache()` membersihkan cache di worker yang memanggil dan mencatat bahwa cache itu perlu disinyalkan.
2. Setelah transaksi berhasil, `signal_changes()` menaikkan sequence `base_cache_signaling_<nama>` di database. Kalau transaksi gagal, perubahan dibatalkan dan cache lokal dibersihkan.
3. Worker lain membandingkan nilai sequence itu saat membuka registry di awal request (`check_signaling`), dan membersihkan cache mereka jika berbeda.

Akibatnya: worker lain baru "tahu" saat menerima request berikutnya, jadi ada jeda kecil sempat membaca nilai lama. Di mode threaded (`workers = 0`) semua thread berbagi satu registry, jadi efeknya langsung. Itu juga alasan perubahan lewat SQL mentah tanpa `clear_cache()` berbahaya: tidak ada sinyal sama sekali.

### 11.4 Kapan dipakai, kapan tidak

Cocok: hasil mahal (query atau perhitungan) yang dibaca sangat sering dan jarang berubah, dengan kunci yang kecil dan terbatas (id kategori, kode, nama model). Hindari: data yang berubah tiap transaksi, kunci dengan kardinalitas besar (cache jadi membengkak), atau hasil yang bergantung pada banyak faktor lingkungan yang sulit dimasukkan ke kunci. Sebelum menambah cache, pastikan memang lambat (bagian 12) dan sudah mencoba perbaikan query/index (bagian 8). Cache mempercepat tetapi menambah risiko data basi.

Untuk melihat efektivitasnya, kirim `SIGUSR1` ke proses utama Odoo; source Odoo 18 mendaftarkan handler yang menulis statistik cache (hit, miss, waktu) ke log pada level INFO, jadi `log_level` perlu `info`. Contoh di Docker: `docker compose kill -s USR1 odoo`.

---

## 12. Monitoring: Query Lambat dan Worker

Prinsip bagian 8 ("ukur dulu") butuh alat ukur. Ada tiga sumber data yang gratis dan cukup untuk memulai.

### 12.1 Log query lambat PostgreSQL

`log_min_duration_statement` mencatat setiap statement yang berjalan minimal selama nilai itu. Default `-1` (mati), tanpa satuan dibaca milidetik, dan `0` mencatat semua.

```yaml
  db:
    image: postgres:16
    command: >
      postgres
      -c log_min_duration_statement=500
```

Gabungkan dengan opsi tuning di bagian 8.6 dalam satu `command`. Hasilnya muncul di log database (`docker compose logs db`). Pada server tanpa Docker, tulis `log_min_duration_statement = 500` di `postgresql.conf`. Mulai dari 500 ms atau 1 detik; nilai terlalu kecil membanjiri log.

### 12.2 `pg_stat_statements`: top-N query paling berat

Ekstensi ini mengagregasi statistik per bentuk query di seluruh database pada server, sehingga cocok mencari query yang **total** waktunya terbesar, bukan hanya yang sekali lambat. Langkah (sesuai dokumentasi PostgreSQL):

1. Muat modulnya lewat `shared_preload_libraries`. Karena butuh shared memory, **server PostgreSQL harus di-restart**.

```yaml
  db:
    command: >
      postgres
      -c shared_preload_libraries=pg_stat_statements
```

   Pada server biasa: `shared_preload_libraries = 'pg_stat_statements'` di `postgresql.conf`. Identifikasi query (`compute_query_id`) aktif otomatis pada pengaturan `auto`/`on`.

2. Setelah restart, buat ekstensi di database Odoo (view-nya per database):

```sql
CREATE EXTENSION pg_stat_statements;
```

   Jika perintah ini gagal karena ekstensi tidak ditemukan, paket contrib PostgreSQL belum terpasang di instalasimu (tidak diverifikasi untuk image `postgres:16`).

3. Ambil 10 query dengan total waktu terbesar (PostgreSQL 13 ke atas):

```sql
SELECT calls,
       round(total_exec_time::numeric, 1) AS total_ms,
       round(mean_exec_time::numeric, 2)  AS mean_ms,
       rows,
       left(query, 120)                   AS query
  FROM pg_stat_statements
 ORDER BY total_exec_time DESC
 LIMIT 10;
```

Catatan:
- Di PostgreSQL 12 (minimum Odoo 18) kolomnya masih bernama `total_time` dan `mean_time`; mulai versi 13 diganti `total_exec_time` dan `mean_exec_time`. Odoo 19 butuh PostgreSQL 13 ke atas, jadi nama baru yang berlaku.
- Nilai konstanta diganti `$1`, `$2`, dan seterusnya, sehingga query yang sama dengan parameter berbeda tergabung jadi satu baris.
- Hanya superuser atau role dengan `pg_read_all_stats` yang melihat teks query milik user lain.
- Reset statistik sebelum mengukur skenario tertentu: `SELECT pg_stat_statements_reset();`.

Dari teks query, telusuri kode ORM pemanggilnya, lalu pakai teknik bagian 8 (batch, `_read_group`, index) dan `EXPLAIN` seperti di [Bab 15](15-database-views-filtering.md).

### 12.3 Mengamati worker lewat log Odoo

Di mode multiprocessing, siklus hidup worker dicatat pada level **INFO**. Karena contoh `odoo.conf` produksi memakai `log_level = warn`, baris-baris ini tidak tampil kecuali kamu menaikkannya ke `info` untuk sementara (`log_level = info` atau `--log-level=info`).

Pesan yang ada di source Odoo 18:

| Pesan di log | Artinya |
|--------------|---------|
| `Worker WorkerHTTP (PID) alive` | Worker HTTP baru dimulai (untuk cron: `WorkerCron`) |
| `Worker (PID) virtual memory limit (N) reached.` | Melewati `limit_memory_soft`; worker selesai request ini lalu keluar dan diganti baru |
| `Worker (PID) max request (N) reached.` | Mencapai `limit_request`; di-recycle |
| `Worker (PID) CPU time limit (N) reached.` | Melewati `limit_time_cpu`; request itu gagal dengan "CPU time limit exceeded." |

```bash
docker compose logs --since 1h odoo | grep "Worker"
```

Recycle sesekali itu normal. Pesan memory limit yang muncul terus-menerus pada request yang sama menandakan batas terlalu rendah untuk beban itu, atau ada request berat yang perlu dioptimasi. Cocokkan jam kejadian dengan log query lambat (12.1). Tool pemantauan pihak ketiga (dasbor metrik, analyzer log PostgreSQL) ada, tapi tidak dibahas di kursus ini.

---

## 13. Deployment Tanpa Docker (Paket dan Source di Linux)

Docker bukan satu-satunya cara. Dokumentasi Odoo 18 menyediakan dua jalur on-premise: **paket** (mudah, dikelola `apt`) dan **source** (fleksibel, bisa beberapa versi berdampingan). Konfigurasi tuning (`workers`, `limit_*`, `proxy_mode`, `dbfilter`) dari bagian 3 sampai 5 berlaku sama; yang berubah hanya cara memasang dan menjalankan.

Persyaratan: Python 3.10 atau lebih baru, PostgreSQL 12 atau lebih baru untuk Odoo 18 (13 untuk Odoo 19). Paket `.deb` Odoo 18 mendukung Debian 12 (Bookworm) dan Ubuntu 22.04 (Jammy) ke atas. `wkhtmltopdf` untuk laporan PDF tidak dipasang lewat pip dan harus dipasang manual (dokumentasi menyebut versi 0.12.6 agar header/footer didukung).

> **Beda di Odoo 19:** PostgreSQL minimum 13, jadi servermu yang masih PostgreSQL 12 perlu dinaikkan lebih dulu. Halaman instalasi 19 tidak diverifikasi di bab ini: cek URL repositori paket, nama branch (`19.0`), dan daftar OS yang didukung di dokumentasi 19 sebelum menyalin perintah di bawah.

### 13.1 Opsi A: Paket `.deb` dari repositori Odoo

Berdasarkan halaman [Packaged installers](https://www.odoo.com/documentation/18.0/administration/on_premise/packages.html) (Community, Debian/Ubuntu):

```bash
# 1. PostgreSQL di host yang sama (konfigurasi bawaan paket memakai PostgreSQL lokal)
sudo apt install postgresql -y

# 2. Repositori nightly Odoo 18 lalu pasang paketnya
wget -q -O - https://nightly.odoo.com/odoo.key | sudo gpg --dearmor -o /usr/share/keyrings/odoo-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/odoo-archive-keyring.gpg] https://nightly.odoo.com/18.0/nightly/deb/ ./' | sudo tee /etc/apt/sources.list.d/odoo.list
sudo apt-get update && sudo apt-get install odoo
```

Alternatifnya mengunduh file `.deb` dari halaman download Odoo (Community dan Enterprise), lalu `dpkg -i`, `apt-get install -f` untuk dependensi yang kurang, dan `dpkg -i` lagi. Dokumentasi mencatat nightly "mungkin sulit dijaga tetap mutakhir".

Yang disiapkan paket (dari skrip `postinst` di source Odoo 18):
- User sistem `odoo`, dan role PostgreSQL `odoo` dengan hak membuat database.
- File konfigurasi `/etc/odoo/odoo.conf` (hak 0640), direktori data `/var/lib/odoo`, dan direktori log `/var/log/odoo`.
- Service systemd bernama `odoo`; paket menjalankan `/usr/bin/odoo --config /etc/odoo/odoo.conf --logfile /var/log/odoo/odoo-server.log`.

Konfigurasi bawaan hanya berisi beberapa baris (`db_host = False` berarti lewat socket lokal, `db_user = odoo`, dan `addons_path` yang dikomentari). Tambahkan opsi bagian 3 ke `/etc/odoo/odoo.conf`, termasuk `addons_path` yang memuat modul kustommu, lalu:

```bash
sudo systemctl restart odoo
sudo systemctl status odoo
tail -f /var/log/odoo/odoo-server.log

# Upgrade module (urutan sama dengan bagian 7), dijalankan sebagai user odoo
sudo -u odoo odoo -c /etc/odoo/odoo.conf -d production_db -u library_management --stop-after-init
sudo systemctl restart odoo
```

### 13.2 Opsi B: Dari source

Berdasarkan halaman [Source install](https://www.odoo.com/documentation/18.0/administration/on_premise/source.html):

```bash
# 1. Ambil source (Community; Enterprise adalah repo terpisah dan wajib ditaruh paling depan di addons_path)
git clone --branch 18.0 https://github.com/odoo/odoo.git

# 2. PostgreSQL: Odoo menolak koneksi sebagai user "postgres", jadi buat user sendiri
sudo apt install postgresql postgresql-client
sudo -u postgres createuser -d -R -S -P odoo      # -P: tanya password

# 3. Dependensi: pilih SALAH SATU
#    a) paket distro (cara yang disarankan dokumentasi)
cd odoo && sudo ./setup/debinstall.sh
#    b) pip di virtualenv (dokumentasi memperingatkan: berisiko jika tidak paham)
sudo apt install python3-pip libldap2-dev libpq-dev libsasl2-dev
python3 -m venv /opt/odoo/venv
/opt/odoo/venv/bin/pip install -r requirements.txt

# 4. Jalankan
python3 odoo-bin --addons-path=addons -d mydb                          # contoh dari dokumentasi
/opt/odoo/venv/bin/python odoo-bin -c /etc/odoo/odoo.conf              # versi produksi dengan file konfigurasi
```

`setup/debinstall.sh` membaca `debian/control` dan memasang paket yang tercantum. Dokumentasi menyarankan paket distro, dan bila memakai pip, isolasi dengan virtualenv. Perintah `python3 -m venv` di atas adalah cara standar Python (dokumentasi menyebut `virtualenv`).

Untuk produksi, jalankan dengan user sistem khusus (bukan root), dan susun, misalnya: kode di `/opt/odoo/odoo`, modul kustom di `/opt/odoo/custom-addons`, config di `/etc/odoo/odoo.conf`. Contoh `odoo.conf` (hanya bagian yang berbeda dari bagian 3):

```ini
[options]
db_host = False          ; socket lokal; atau isi host + db_user/db_password
db_user = odoo
db_name = production_db
dbfilter = ^production_db$
addons_path = /opt/odoo/odoo/addons,/opt/odoo/custom-addons
data_dir = /var/lib/odoo
http_interface = 127.0.0.1   ; hanya Nginx di host yang boleh menjangkau Odoo
proxy_mode = True
workers = 4
```

### 13.3 Unit systemd (ilustrasi)

Paket `.deb` sudah membawa unit sendiri; untuk instalasi dari source kamu menulisnya sendiri. Berikut **contoh ilustrasi**: strukturnya mengikuti unit resmi di source Odoo (`User`, `Group`, `Type=simple`, `KillMode=mixed`), sedangkan `After=postgresql.service` dan `Restart=on-failure` adalah tambahan dari saya dan perlu kamu sesuaikan.

```ini
# /etc/systemd/system/odoo.service  -- ILUSTRASI, sesuaikan path dan user
[Unit]
Description=Odoo (install dari source)
After=network.target postgresql.service

[Service]
Type=simple
User=odoo
Group=odoo
ExecStart=/opt/odoo/venv/bin/python /opt/odoo/odoo/odoo-bin -c /etc/odoo/odoo.conf
KillMode=mixed
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now odoo
journalctl -u odoo -f        # log ke stdout otomatis masuk journal jika tidak ada logfile
```

Pastikan `/var/lib/odoo` ada dan dimiliki user `odoo`. Jika memakai `logfile`, buat direktori lognya dan atur `logrotate`.

### 13.4 Hubungan dengan Nginx dan workers

Konfigurasi Nginx di bagian 4 dipakai apa adanya, dengan dua perubahan: `upstream` menunjuk ke alamat lokal (`server 127.0.0.1:8069;` dan `server 127.0.0.1:8072;`) alih-alih nama service Docker, dan sertifikat dibaca langsung dari host. Syarat `workers > 0` untuk jalur `/websocket` (port `gevent_port`) tetap berlaku. Karena Odoo mendengarkan di `127.0.0.1` saja (`http_interface`), syarat keamanan `proxy_mode` pada bagian 4 terpenuhi. Backup memakai `pg_dump` langsung dan salinan `/var/lib/odoo/filestore/<nama_db>` (lihat Bab 2 untuk alasannya).

---

## 14. Migrasi dan Upgrade Antar Versi Mayor

Ada dua pekerjaan yang sering tercampur:
1. **Upgrade data** database dari versi lama ke baru untuk module standar Odoo.
2. **Upgrade kode** module kustom (dan data miliknya) agar jalan di versi target.

Dokumentasi resmi menegaskan: database yang berisi module kustom tidak bisa di-upgrade sampai ada versi module kustom itu untuk versi target. Kerjakan keduanya paralel.

### 14.1 Opsi untuk upgrade data

| Opsi | Catatan |
|------|---------|
| **Odoo upgrade service** (`upgrade.odoo.com`) | Resmi. Contoh dokumentasi mencakup lompatan 16.0 ke 18.0. Untuk Enterprise, upgrade ke versi terbaru gratis menurut bagian SLA dokumentasi. Syarat untuk Community tidak diverifikasi di sini; cek halaman Upgrade. |
| **OpenUpgrade** (komunitas OCA) | Alternatif sumber terbuka: [github.com/OCA/OpenUpgrade](https://github.com/OCA/OpenUpgrade), berisi module `openupgrade_framework` (dipasang di `server_wide_modules`) dan `openupgrade_scripts` (skrip migrasi module standar Odoo). Cek README dan branch tiap versi untuk jalur yang didukung; tidak dibahas rinci di kursus ini. |

Prinsip dari dokumentasi: semakin kecil selisih versi, semakin mudah upgrade-nya.

### 14.2 Alur upgrade on-premise (upgrade service)

Urutan yang dianjurkan dokumentasi, disesuaikan dengan konteks kursus:

1. **Backup** database dan filestore (bagian 6) dan **bekukan fitur baru** pada module kustom; hanya perbaikan bug yang jalan.
2. **Minta database uji** dari salinan production. Dokumentasi memberi perintah untuk on-premise:

```bash
python <(curl -s https://upgrade.odoo.com/upgrade) test -d <nama_db> -t <versi_target>
```

   Database dikirim **tanpa filestore**, sehingga hasil upgrade berisi `dump.sql` dan folder `filestore` yang harus digabung dengan filestore production sebelum diuji. Database uji dinetralkan (scheduled action dimatikan, mail server keluar dinonaktifkan).
3. **Buat module kustom jalan di versi target**: pasang satu per satu di database **kosong** versi target, perbaiki traceback dan warning, uji view/report/server action/compute, jalankan test (Bab 17).
4. **Terapkan di database hasil upgrade**: restore, lalu update module kustom dengan `-u` (lihat 14.3). Periksa laporan upgrade: view yang bermasalah dinonaktifkan selama upgrade dan dilaporkan di sana.
5. **Uji menyeluruh** alur bisnis dan integrasi, lalu latih ulang seluruh proses (rehearsal) satu hari sebelum hari-H.
6. **Produksi**: ganti `test` dengan `production` pada perintah di atas. Selama proses database production tidak boleh dipakai karena perubahan setelah unggah tidak ikut ke hasil upgrade. Gabungkan filestore sebelum menjalankan versi baru. Siapkan rencana rollback dari backup langkah 1.

### 14.3 Upgrade kode dan data module: `version`, `-u`, migration script

Setiap perubahan struktur data di module kustom ditandai dengan menaikkan `version` di `__manifest__.py`, misalnya dari `18.0.1.0.0` ke `18.0.1.1.0`. Menjalankan `-u library_management` (urutan di bagian 7) memperbarui module, dan pada saat itu **migration script** yang cocok dijalankan.

Aturan dari dokumentasi upgrade scripts (Odoo 18):
- Letak: `library_management/migrations/<versi lengkap>/{pre,post,end}-nama.py`, dengan versi lengkap seperti `18.0.1.1.0` (versi mayor Odoo + versi module). Nama folder `upgrades/` juga valid sejak Odoo 13.
- Isi: fungsi `migrate(cr, version)`; `version` adalah versi module yang terpasang sebelum update.
- Fase: `pre-` sebelum module dimuat; `post-` setelah module dan dependensinya dimuat dan diupdate; `end-` setelah semua module selesai untuk versi itu. Dalam satu fase, file dijalankan berurutan menurut nama (leksikal), misalnya `pre-10-...` sebelum `pre-20-...`.
- Script hanya jalan saat module di-update, dan folder versinya harus lebih tinggi dari versi terpasang serta kurang dari atau sama dengan versi baru di manifest.

Contoh: field `fine_amount` pada `library.fine` diganti namanya menjadi `amount`. Tanpa script, ORM membuat kolom `amount` baru yang kosong dan data lama hilang dari tampilan. Dokumentasi menyarankan rename data teknis lewat upgrade script agar tidak ada data hilang, dan karena kolom lama harus diganti namanya sebelum ORM membuat yang baru, ini cocok di fase `pre-`:

```python
# library_management/migrations/18.0.1.1.0/pre-rename-fine-amount.py
def migrate(cr, version):
    cr.execute("ALTER TABLE library_fine RENAME COLUMN fine_amount TO amount")
```

Sebaliknya, memindahkan data antar tabel yang kolomnya baru dibuat perlu `post-` karena kolom tujuan harus sudah ada. Dokumentasi juga menyebut library "upgrade utils" (`odoo.upgrade.util`) dengan helper seperti `rename_field`, `rename_model`, `rename_xmlid`, `recompute_fields`, dan `remove_module`; kursus ini tidak memasangnya, jadi contoh memakai SQL polos.

### 14.4 Apa yang berubah di module saat 17 ke 18 ke 19

Jangan menulis ulang tabelnya di sini; pakai rujukan yang sudah ada:
- Tabel perubahan versi: [Bab 21, bagian 5](21-tips-best-practices.md) (view `<list>`, `attrs` dihapus, `<chatter/>`, `_read_group`, dan seterusnya).
- Cheat sheet ORM: [Bab 4](04-models-orm.md), bagian "Cheat Sheet Perubahan Versi".
- Sintaks view dan aset: [Bab 5](05-views-xml.md).

Kategori masalah yang disebut dokumentasi saat membuat module kustom installable di versi baru: dependensi tidak valid, perubahan sintaks (deklarasi aset, OWL, `attrs`), referensi ke field/model/view standar yang hilang atau berganti nama, xpath yang bergeser atau hilang, dan method yang diganti nama atau dihapus. Gunakan `-u` pada database kosong dan jalankan test Bab 17 sebagai pagar pengaman.

### 14.5 Strategi ringkas

```
[ ] Backup database + filestore; restore pernah diuji
[ ] Uji selalu pada SALINAN database, bukan production
[ ] Fitur baru dibekukan selama upgrade; module kustom dirapikan/dihapus yang sudah ada di standar
[ ] Module kustom lolos pasang + test di database kosong versi target
[ ] Migration script (pre/post/end) untuk rename/pindah data, diuji di hasil upgrade
[ ] Filestore hasil upgrade digabung dengan filestore production
[ ] Rehearsal penuh sehari sebelum hari-H; jendela downtime diumumkan
[ ] Rencana rollback: backup sebelum upgrade tetap disimpan
[ ] Naik PostgreSQL lebih dulu jika menuju Odoo 19 dan masih di PostgreSQL 12
```

---

> **Beda di Odoo 19:** untuk menjalankan 19 ganti tag image ke `odoo:19.0`; PostgreSQL minimum naik ke 13 (`postgres:16` tetap cocok). Opsi di bab ini diverifikasi terhadap dokumentasi Odoo 18. Cek halaman deployment dokumentasi 19 untuk nilai default dan opsi sebelum produksi. Fitur AI di Odoo 19 butuh ekstensi pgvector; di luar cakupan kursus ini.

## Ringkasan

- Production memakai multiprocessing (`workers > 0`), development memakai threaded (`workers = 0`).
- Aturan awal `workers`: `(CPU * 2) + 1` sebagai batas atas, sekitar 6 user per worker; atur batas memori dan waktu di `odoo.conf`.
- Di belakang Nginx: `proxy_mode = True`, HTTPS, dan `location /websocket` ke `gevent_port` (8072). Opsi `xmlrpc_*` dan `longpolling_port` sudah usang.
- Keamanan dasar: `dbfilter`, `list_db = False`, `admin_passwd` kuat, user PostgreSQL non-superuser.
- Backup lengkap = dump database + filestore; uji restore dan simpan salinan di luar server.
- Optimasi: hindari `search` dalam loop, pakai `_read_group` untuk agregasi, parameterisasi SQL, `index=True` selektif, `store=True` dengan bijak.
- Update module: backup, staging, `-u nama_module --stop-after-init`, restart, cek log.
- Cache registry (`@tools.ormcache`) untuk hasil lookup yang mahal dan jarang berubah; kembalikan nilai biasa, bukan recordset, dan panggil `self.env.registry.clear_cache()` saat data sumbernya berubah. Itu berbeda dari `invalidate_model()`/`invalidate_recordset()` yang mengurus cache record.
- Antar worker, invalidasi disinyalkan lewat sequence di database dan baru terbaca pada request berikutnya; SQL mentah tidak menyinyalkan apa pun. Di Odoo 19 `ormcache_context` deprecated dan ada cache `'stable'`.
- Monitoring: `log_min_duration_statement` untuk query lambat, `pg_stat_statements` (`shared_preload_libraries` + `CREATE EXTENSION`, urut `total_exec_time` di PG 13+) untuk total terberat, dan log INFO worker untuk recycle akibat batas memori/request/CPU.
- Tanpa Docker: paket `.deb` (user, config `/etc/odoo/odoo.conf`, service `odoo`) atau source (`git clone`, dependensi, user PostgreSQL non-`postgres`, `odoo-bin -c`), dengan unit systemd dan Nginx yang sama prinsipnya.
- Upgrade versi mayor: uji di salinan, upgrade data lewat upgrade service (atau OpenUpgrade), upgrade kode module, dan migration script `migrations/<versi>/{pre,post,end}-*.py` dengan fungsi `migrate(cr, version)`; selalu rehearsal sebelum production.

## Latihan

1. Siapkan compose production dari bab ini di mesin lokal (tanpa Let's Encrypt, pakai sertifikat self-signed atau hanya HTTP dulu). Pastikan hanya port Nginx yang terbuka, lalu cek `docker compose ps`.
2. Tulis `backup.sh`, jalankan, lalu restore ke database dengan nama lain (mis. `restore_test`) dan buktikan lampiran (filestore) ikut kembali.
3. Hitung `workers` dan perkiraan RAM untuk server 2 CPU dengan 25 user bersamaan memakai rumus di Bagian 3, lalu tulis nilai `workers` dan `limit_memory_*` yang kamu pilih beserta alasannya.
4. Tambahkan model `library.fine.rule` dari bagian 11. Di `odoo shell`, panggil `_get_daily_rate` dua kali dan buktikan query kedua tidak terjadi (nyalakan `log_handler = odoo.sql_db:DEBUG` lalu lihat apakah ada SELECT ke `library_fine_rule`). Lalu ubah `daily_rate` dan pastikan nilai baru terbaca. Apa yang terjadi jika kamu mengubahnya lewat `env.cr.execute` tanpa `clear_cache()`?
5. Aktifkan `log_min_duration_statement=500` dan `pg_stat_statements` di service `db`. Jalankan beberapa laporan/list besar di Odoo, lalu ambil 10 query teratas berdasarkan `total_exec_time` dan catat satu kandidat optimasi.
6. (Opsional, di VM Ubuntu/Debian) Pasang Odoo dari paket `.deb` atau dari source, jalankan sebagai service, lalu tulis ulang `upstream` Nginx bagian 4 untuk alamat `127.0.0.1`.
7. Naikkan `version` modulmu satu langkah, tulis `pre-` migration script yang mengganti nama satu kolom, lalu jalankan `-u` pada salinan database dan buktikan data lama tetap ada.

## Lanjut ke

[Bab 21: Tips, Best Practices & Checklist](21-tips-best-practices.md)
