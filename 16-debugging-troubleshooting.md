# Bab 16: Debugging & Troubleshooting

## Developer Mode

### Mengaktifkan Developer Mode

```
# Cara 1: Via URL
https://localhost:8069/web?debug=1

# Cara 2: Via Settings
Settings > General Settings > scroll ke bawah > Activate Developer Mode

# Cara 3: With Assets (untuk debug JS)
https://localhost:8069/web?debug=assets
```

### Developer Mode Berguna Untuk

- Melihat technical name field (hover field di form)
- Akses menu Technical (Settings > Technical)
- Edit views langsung dari UI
- Melihat metadata record (ID, XML ID, create date, dll)
- Debug JS tanpa minifikasi (`debug=assets`)

---

## Odoo Shell

Interactive Python shell dengan akses penuh ke environment Odoo.

```bash
# Masuk ke shell
docker compose exec odoo odoo shell -d odoo

# Atau jika tanpa Docker
./odoo-bin shell -d odoo
```

### Operasi Umum di Shell

```python
# Cek record
>>> env['library.book'].search([])
library.book(1, 2, 3)

>>> env['library.book'].search_read([], ['name', 'author'], limit=5)
[{'id': 1, 'name': 'Book 1', 'author': 'Author 1'}, ...]

# Cek field definition
>>> env['library.book']._fields
{'id': ..., 'name': ..., 'author': ...}

>>> env['library.book']._fields['name'].required
True

# Cek installed modules
>>> env['ir.module.module'].search([('state', '=', 'installed')]).mapped('name')
['base', 'mail', 'library_management', ...]

# Cek XML ID
>>> env.ref('library_management.category_fiction')
library.book.category(1,)

>>> env['ir.model.data'].search([('model', '=', 'library.book.category')])

# Cek access rights
>>> env['ir.model.access'].search([('model_id.model', '=', 'library.book')])

# Test method
>>> loan = env['library.loan'].browse(1)
>>> loan.action_confirm()

# Manual create
>>> book = env['library.book'].create({'name': 'Test', 'category_id': 1})
>>> env.cr.commit()  # PENTING: commit agar tersimpan

# Rollback jika salah
>>> env.cr.rollback()
```

---

## Logging & Print Debugging

### Menggunakan Logger

```python
import logging
_logger = logging.getLogger(__name__)

class LibraryBook(models.Model):
    _name = 'library.book'

    def action_confirm(self):
        _logger.info('=== action_confirm called ===')
        _logger.info('Self: %s', self)
        _logger.info('Self IDs: %s', self.ids)
        _logger.info('Context: %s', self._context)

        for record in self:
            _logger.debug('Processing book: %s (id=%s)', record.name, record.id)
            _logger.debug('Current state: %s', record.state)
```

### Lihat Log

```bash
# Lihat log realtime
docker compose logs -f odoo

# Lihat log dengan filter
docker compose logs -f odoo 2>&1 | grep "library"

# Log level di odoo.conf untuk development
log_level = debug
log_handler = :INFO,odoo.addons.library_management:DEBUG

# Atau via CLI
docker compose exec odoo odoo -d odoo --log-level=debug --log-handler=odoo.addons.library_management:DEBUG
```

### Breakpoint Debugging (pdb)

```python
def action_confirm(self):
    import pdb; pdb.set_trace()  # Execution berhenti di sini
    # Atau di Python 3.7+:
    breakpoint()

    self.write({'state': 'confirmed'})
```

**Perintah pdb:**

| Command | Fungsi |
|---------|--------|
| `n` | Next line |
| `s` | Step into function |
| `c` | Continue execution |
| `p variable` | Print variable |
| `pp variable` | Pretty print |
| `l` | List source code |
| `q` | Quit debugger |
| `h` | Help |

**Penting:** pdb hanya bekerja jika Odoo dijalankan **tanpa** `--workers` (single process mode). Untuk Docker, jalankan:

```bash
docker compose exec odoo odoo -d odoo --workers=0 --dev=all
```

---

## --dev Mode

```bash
# Development mode: auto-reload Python + XML
docker compose exec odoo odoo -d odoo --dev=all

# Hanya auto-reload Python
docker compose exec odoo odoo -d odoo --dev=reload

# Hanya auto-reload XML (views)
docker compose exec odoo odoo -d odoo --dev=xml

# Kombinasi
docker compose exec odoo odoo -d odoo --dev=reload,xml,qweb
```

| Flag | Efek |
|------|------|
| `reload` | Auto-restart saat Python file berubah |
| `xml` | Reload XML views tanpa restart |
| `qweb` | Reload QWeb templates |
| `all` | Semua di atas + werkzeug debugger |

---

## Common Errors & Solusi

### 1. Access Denied / Access Error

```
odoo.exceptions.AccessError: You are not allowed to access 'Library Book' (library.book) records.
```

**Penyebab:**
- Model belum punya entry di `ir.model.access.csv`
- User tidak masuk group yang benar
- Record rule memblokir akses

**Solusi:**
```python
# Cek di shell
>>> env['ir.model.access'].search([('model_id.model', '=', 'library.book')])
# Jika kosong, tambahkan access rights

# Cek user groups
>>> env.user.groups_id.mapped('full_name')

# Bypass sementara (development only)
>>> env['library.book'].sudo().search([])
```

### 2. Field "xxx" does not exist

```
ValueError: Field "xxx" does not exist in model "library.book"
```

**Penyebab:**
- Field ada di view XML tapi belum didefinisikan di Python model
- Typo nama field
- Module belum di-update setelah menambah field

**Solusi:**
```bash
# Update module
docker compose exec odoo odoo -d odoo -u library_management --stop-after-init
```

### 3. External ID not found

```
ValueError: External ID not found in the system: library_management.view_xxx
```

**Penyebab:**
- XML ID yang direferensikan belum di-load
- Urutan file di `__manifest__.py` salah (file yang dirujuk belum di-load)
- Typo di XML ID

**Solusi:**
- Cek urutan `data` di `__manifest__.py`
- Pastikan file XML yang berisi ID tersebut sudah terdaftar

### 4. Constraint Violation

```
psycopg2.IntegrityError: duplicate key value violates unique constraint "library_book_isbn_uniq"
```

**Penyebab:** Mencoba insert data yang melanggar SQL constraint.

**Solusi:** Validasi data sebelum create, atau handle error:
```python
from psycopg2 import IntegrityError

try:
    book = self.env['library.book'].create(vals)
except IntegrityError:
    self.env.cr.rollback()
    raise UserError('ISBN sudah dipakai!')
```

### 5. RecursionError / Maximum recursion depth

```
RecursionError: maximum recursion depth exceeded
```

**Penyebab:**
- Compute field yang depend ke dirinya sendiri
- Override method yang lupa panggil `super()`
- Onchange yang trigger onchange lain secara circular

**Solusi:**
```python
# Cek dependency cycle
@api.depends('field_a')  # field_a depends on field_b yang depends on field_a?
def _compute_field_b(self):
    ...

# Pastikan super() dipanggil
def write(self, vals):
    return super().write(vals)  # JANGAN lupa!
```

### 6. View Error: Element "xxx" cannot be located

```
ValueError: Element '<xpath expr="//field[@name='xxx']">' cannot be located in parent view
```

**Penyebab:** XPath expression tidak menemukan target di parent view.

**Solusi:**
```bash
# Cek structure parent view di shell
>>> view = env.ref('base.view_partner_form')
>>> print(view.arch)  # Lihat XML structure
```

```python
# Atau cek di browser (Developer Mode):
# Settings > Technical > User Interface > Views
# Cari view yang mau di-inherit, lihat Architecture tab
```

### 7. Module Not Found / Won't Install

**Penyebab:**
- Path addons tidak benar
- `__manifest__.py` error (syntax)
- Dependency module belum terinstall

**Solusi:**
```bash
# Cek addons path
docker compose exec odoo odoo --help | grep addons

# Pastikan path tercantum di odoo.conf
addons_path = /mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons

# Update apps list via CLI
docker compose exec odoo odoo -d odoo -u base --stop-after-init
```

### 8. KeyError pada create/write vals

```
KeyError: 'name'
```

**Penyebab:** Mengakses key yang tidak ada di dictionary `vals`.

**Solusi:**
```python
@api.model
def create(self, vals):
    # WRONG
    name = vals['name']  # KeyError jika 'name' tidak ada

    # CORRECT
    name = vals.get('name', '')  # Default value jika tidak ada
    if 'name' in vals:
        # Process name
        pass
    return super().create(vals)
```

### 9. TransactionRollbackError

```
odoo.exceptions.except_orm: TransactionRollbackError
```

**Penyebab:** Concurrent write ke record yang sama (deadlock).

**Solusi:**
```python
# Gunakan FOR UPDATE untuk lock
self.env.cr.execute(
    "SELECT id FROM library_book WHERE id = %s FOR UPDATE NOWAIT",
    (self.id,)
)
```

### 10. Assets / JS Not Loading

**Penyebab:** JavaScript cache.

**Solusi:**
```bash
# Clear assets cache
# Via URL: https://localhost:8069/web?debug=assets
# Lalu: Settings > Technical > Clear Assets Bundles

# Atau delete dari database
docker compose exec odoo odoo shell -d odoo
>>> env['ir.attachment'].search([('url', 'like', '/web/assets/')]).unlink()
>>> env.cr.commit()

# Atau restart dengan --dev=all
```

---

## Inspect Database Langsung

```bash
# Masuk PostgreSQL
docker compose exec db psql -U odoo odoo

# Lihat tables
\dt library_*

# Lihat struktur table
\d library_book

# Query langsung
SELECT id, name, state FROM library_loan WHERE state = 'active';

# Lihat foreign keys
SELECT conname, conrelid::regclass, confrelid::regclass
FROM pg_constraint
WHERE conrelid = 'library_loan'::regclass;
```

---

## Inspect View Structure

```python
# Di shell: lihat final rendered view (setelah semua inheritance)
>>> view = env.ref('library_management.view_library_book_form')
>>> arch = view._get_combined_arch()
>>> print(arch)

# Lihat semua inherit views
>>> children = env['ir.ui.view'].search([
...     ('inherit_id', '=', view.id)
... ])
>>> for child in children:
...     print(f"{child.name} (module: {child.xml_id})")
```

---

## Tips Debugging Umum

1. **Selalu cek log dulu** — 90% error sudah ada pesan yang jelas di log
2. **Gunakan `--dev=all`** di development — auto-reload sangat menghemat waktu
3. **Shell adalah teman terbaik** — test query, cek data, debug logic tanpa restart
4. **`sudo()`** untuk bypass security sementara — tapi jangan sampai masuk production code
5. **`env.cr.rollback()`** di shell — kalau salah create/write, rollback sebelum commit
6. **Cek installed module version** — kadang module belum ter-update
7. **Backup sebelum eksperimen** — terutama saat edit data via shell
