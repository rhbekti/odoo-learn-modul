# Bab 15: Deployment & Performance

## Deployment Odoo 18 dengan Docker (Production)

### docker-compose.yml (Production)

```yaml
version: '3.8'

services:
  odoo:
    image: odoo:18.0
    depends_on:
      - db
    ports:
      - "8069:8069"
      - "8072:8072"  # longpolling (live chat, notifications)
    volumes:
      - odoo-data:/var/lib/odoo
      - ./addons:/mnt/extra-addons
      - ./config/odoo.conf:/etc/odoo/odoo.conf
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=strong_password_here
    restart: unless-stopped

  db:
    image: postgres:16
    environment:
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=strong_password_here
      - POSTGRES_DB=postgres
    volumes:
      - db-data:/var/lib/postgresql/data
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/odoo.conf:/etc/nginx/conf.d/default.conf
      - ./nginx/ssl:/etc/nginx/ssl
    depends_on:
      - odoo
    restart: unless-stopped

volumes:
  odoo-data:
  db-data:
```

### config/odoo.conf (Production)

```ini
[options]
; Database
db_host = db
db_port = 5432
db_user = odoo
db_password = strong_password_here
db_name = production_db
dbfilter = ^production_db$
list_db = False

; Addons
addons_path = /mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons

; Performance
workers = 4
max_cron_threads = 1
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_time_cpu = 600
limit_time_real = 1200
limit_time_real_cron = 3600
limit_request = 8192

; Proxy
proxy_mode = True
xmlrpc_interface = 0.0.0.0

; Longpolling
gevent_port = 8072

; Logging
logfile = /var/log/odoo/odoo.log
log_level = warn
log_handler = :WARNING,odoo.models:WARNING,odoo.addons:WARNING

; Security
admin_passwd = $pbkdf2-sha512$...
```

**Penjelasan parameter performance:**

| Parameter | Penjelasan | Rekomendasi |
|-----------|-----------|-------------|
| `workers` | Jumlah worker process | `(CPU cores * 2) + 1` |
| `max_cron_threads` | Thread untuk cron jobs | 1-2 |
| `limit_memory_hard` | Max RAM per worker (bytes) | 2.5 GB |
| `limit_memory_soft` | Soft limit (worker restart) | 2 GB |
| `limit_time_cpu` | Max CPU time per request | 600s |
| `limit_time_real` | Max wall time per request | 1200s |
| `limit_request` | Max requests sebelum worker restart | 8192 |

---

### Nginx Reverse Proxy

```nginx
# nginx/odoo.conf
upstream odoo {
    server odoo:8069;
}

upstream odoo-chat {
    server odoo:8072;
}

server {
    listen 80;
    server_name yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.com;

    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    # Proxy settings
    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml;

    # Longpolling
    location /websocket {
        proxy_pass http://odoo-chat;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Static files caching
    location ~* /web/static/ {
        proxy_pass http://odoo;
        proxy_cache_valid 200 90m;
        expires 90d;
        add_header Cache-Control "public, no-transform";
    }

    # Main Odoo
    location / {
        proxy_pass http://odoo;
        proxy_redirect off;
        client_max_body_size 100m;
    }
}
```

---

## Backup & Restore

### Backup Database

```bash
# Backup database + filestore
docker compose exec db pg_dump -U odoo production_db | gzip > backup_$(date +%Y%m%d).sql.gz

# Backup filestore
docker compose exec odoo tar czf /tmp/filestore.tar.gz /var/lib/odoo/filestore/production_db
docker compose cp odoo:/tmp/filestore.tar.gz ./filestore_$(date +%Y%m%d).tar.gz

# Script backup lengkap
#!/bin/bash
BACKUP_DIR="/backups/odoo"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="production_db"

mkdir -p $BACKUP_DIR

# Database
docker compose exec -T db pg_dump -U odoo $DB_NAME | gzip > "$BACKUP_DIR/${DB_NAME}_${DATE}.sql.gz"

# Filestore
docker compose exec -T odoo tar czf - /var/lib/odoo/filestore/$DB_NAME | gzip > "$BACKUP_DIR/filestore_${DATE}.tar.gz"

# Hapus backup lebih dari 30 hari
find $BACKUP_DIR -type f -mtime +30 -delete

echo "Backup completed: $DATE"
```

### Restore Database

```bash
# Restore database
gunzip < backup_20260518.sql.gz | docker compose exec -T db psql -U odoo production_db

# Atau drop dan create ulang
docker compose exec db dropdb -U odoo production_db
docker compose exec db createdb -U odoo production_db
gunzip < backup_20260518.sql.gz | docker compose exec -T db psql -U odoo production_db

# Restore filestore
docker compose cp filestore_20260518.tar.gz odoo:/tmp/
docker compose exec odoo tar xzf /tmp/filestore.tar.gz -C /
```

---

## Update Module di Production

```bash
# 1. Backup dulu!
docker compose exec -T db pg_dump -U odoo production_db > pre_update_backup.sql

# 2. Update kode (pull dari git)
cd addons && git pull origin main

# 3. Update module
docker compose exec odoo odoo -d production_db -u library_management --stop-after-init

# 4. Restart
docker compose restart odoo

# 5. Update semua module (jika banyak perubahan)
docker compose exec odoo odoo -d production_db -u all --stop-after-init
```

---

## Performance Optimization

### 1. PostgreSQL Tuning

```ini
# postgresql.conf (untuk server 8GB RAM)
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 64MB
maintenance_work_mem = 512MB
wal_buffers = 16MB
max_connections = 200
random_page_cost = 1.1  # SSD
```

### 2. Stored Computed Fields

```python
# SLOW: computed tanpa store (dihitung setiap kali diakses)
total = fields.Float(compute='_compute_total')

# FAST: stored computed (dihitung sekali, disimpan di DB)
total = fields.Float(compute='_compute_total', store=True)
```

**Kapan pakai `store=True`:**
- Field sering diakses di list view
- Field dipakai untuk search/filter/group by
- Field dependency jarang berubah

**Kapan TANPA `store=True`:**
- Field dependency sangat sering berubah
- Field yang hitungannya sangat ringan

### 3. Prefetch dan Batch

```python
# SLOW: N+1 query problem
for loan in loans:
    print(loan.member_id.name)  # query per record!

# FAST: Odoo auto-prefetch sudah handle ini,
# tapi pastikan akses field di loop, bukan di lambda terpisah

# SLOW: search di loop
for book in books:
    copies = self.env['library.book.copy'].search([('book_id', '=', book.id)])

# FAST: batch search
all_copies = self.env['library.book.copy'].search([('book_id', 'in', books.ids)])
copies_by_book = {}
for copy in all_copies:
    copies_by_book.setdefault(copy.book_id.id, self.env['library.book.copy'])
    copies_by_book[copy.book_id.id] |= copy
```

### 4. Read Group (Aggregasi)

```python
# SLOW: membaca semua records lalu hitung di Python
loans = self.env['library.loan'].search([('state', '=', 'active')])
by_member = {}
for loan in loans:
    by_member[loan.member_id.id] = by_member.get(loan.member_id.id, 0) + 1

# FAST: read_group (SQL GROUP BY)
result = self.env['library.loan'].read_group(
    domain=[('state', '=', 'active')],
    fields=['member_id'],
    groupby=['member_id'],
)
# result = [{'member_id': (1, 'John'), 'member_id_count': 5}, ...]
```

### 5. SQL Langsung (untuk Query Kompleks)

```python
def _get_overdue_statistics(self):
    self.env.cr.execute("""
        SELECT
            m.id as member_id,
            m.name as member_name,
            COUNT(l.id) as overdue_count,
            SUM(f.amount) as total_fines
        FROM library_loan l
        JOIN library_member m ON l.member_id = m.id
        LEFT JOIN library_fine f ON f.loan_id = l.id
        WHERE l.state = 'overdue'
        GROUP BY m.id, m.name
        ORDER BY overdue_count DESC
    """)
    return self.env.cr.dictfetchall()
```

**Gunakan raw SQL hanya jika ORM tidak efisien.** ORM sudah cukup untuk 95% kasus.

### 6. Index pada Field yang Sering Di-search

```python
# Tambah index untuk field yang sering di-search/filter
isbn = fields.Char(index=True)
state = fields.Selection([...], index=True)
loan_date = fields.Date(index=True)
member_id = fields.Many2one('library.member', index=True)  # M2O otomatis ter-index
```

---

## Monitoring & Logging

### Custom Logging

```python
import logging
_logger = logging.getLogger(__name__)

class LibraryLoan(models.Model):
    _name = 'library.loan'

    def action_confirm(self):
        _logger.info('Confirming loan %s for member %s', self.name, self.member_id.name)
        try:
            # ... logic
            _logger.debug('Loan %s confirmed successfully', self.name)
        except Exception as e:
            _logger.error('Failed to confirm loan %s: %s', self.name, str(e))
            raise
```

### Log Levels

| Level | Kapan Dipakai |
|-------|--------------|
| `_logger.debug()` | Detail teknis (development) |
| `_logger.info()` | Event bisnis normal |
| `_logger.warning()` | Sesuatu yang tidak ideal tapi bukan error |
| `_logger.error()` | Error yang perlu investigasi |
| `_logger.critical()` | System down |

### Odoo.conf Logging

```ini
# Log semua ke file
logfile = /var/log/odoo/odoo.log
log_level = info

# Log handler per module
log_handler = :WARNING,odoo.addons.library_management:DEBUG

# Log SQL queries (development only!)
# log_handler = odoo.sql_db:DEBUG
```

---

## Checklist Deployment

```
[ ] Backup database production
[ ] Test update di staging/development dulu
[ ] Set list_db = False (hide database manager)
[ ] Set admin_passwd (hash, bukan plaintext)
[ ] Set proxy_mode = True (jika pakai reverse proxy)
[ ] Set workers > 0 (multiprocessing mode)
[ ] Configure Nginx reverse proxy + SSL
[ ] Setup automated backup (cron)
[ ] Set log_level = warn (production)
[ ] Remove --dev flag
[ ] Test semua fungsi setelah deploy
[ ] Monitor log untuk error
```
