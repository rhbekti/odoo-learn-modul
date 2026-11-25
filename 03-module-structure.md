# Bab 3: Struktur Module Odoo

> **Tahap:** 1 Persiapan | **Prasyarat:** Bab 1, 2 | **Estimasi:** ± 1,5 jam | **Versi:** Odoo 18 (catatan Odoo 19)

## Tujuan Belajar

Setelah bab ini kamu bisa:
- Menjelaskan fungsi folder dan file standar dalam sebuah module Odoo.
- Menulis `__manifest__.py` dengan field yang benar (dan tahu mana yang wajib).
- Membuat module minimal `library_management` yang bisa di-install.
- Meng-install dan meng-upgrade module lewat UI maupun CLI.
- Mendiagnosis masalah umum: module tidak muncul atau install gagal.

## Struktur Direktori Module

```
my_module/
├── __init__.py           # Import sub-package Python
├── __manifest__.py       # Metadata module (wajib)
├── models/
│   ├── __init__.py
│   └── model_name.py     # Model Python
├── views/
│   ├── views.xml         # Form, list, search views
│   └── templates.xml     # QWeb templates
├── controllers/
│   ├── __init__.py
│   └── main.py           # HTTP endpoints
├── security/
│   └── ir.model.access.csv
├── data/
│   ├── data.xml          # Data awal (selalu di-load)
│   └── demo.xml          # Data demo
└── static/
    ├── src/
    │   ├── js/
    │   ├── xml/
    │   └── scss/
    └── description/
        └── icon.png
```

Tidak semua folder wajib ada. Buat sesuai kebutuhan; yang benar-benar wajib hanya `__init__.py` dan `__manifest__.py`.

## __manifest__.py

```python
{
    'name': "My Module",
    'version': '1.0.0',
    'summary': 'Short description',
    'author': 'Your Name',
    'website': 'https://example.com',
    'license': 'LGPL-3',
    'category': 'Uncategorized',
    'depends': ['base'],
    'data': [
        'security/ir.model.access.csv',
        'views/views.xml',
    ],
    'demo': [
        'data/demo.xml',
    ],
    'installable': True,
    'application': True,
    'auto_install': False,
}
```

| Field | Wajib | Deskripsi |
|-------|-------|-----------|
| `name` | Ya | Nama module yang tampil di Apps |
| `version` | Tidak | Nomor versi. Kalau ditulis `1.0.0`, Odoo otomatis menambah prefix seri jadi `18.0.1.0.0`; boleh juga ditulis lengkap |
| `depends` | Tidak (default `base`) | Module yang harus ter-install lebih dulu |
| `data` | Tidak | File yang di-load saat install/upgrade (urutan penting) |
| `demo` | Tidak | File yang di-load hanya kalau database dibuat dengan demo data |
| `installable` | Tidak (default `True`) | Bisa di-install atau tidak |
| `application` | Tidak (default `False`) | `True` kalau module tampil sebagai aplikasi utama di Apps |
| `auto_install` | Tidak (default `False`) | `True` kalau module otomatis ter-install ketika semua `depends`-nya ada |

Hal penting tentang `data`:
- Urutan file di list = urutan load. Taruh `security/` dulu, baru `views/`, supaya view bisa merujuk grup/akses yang sudah ada.
- File yang tidak terdaftar di `data` **tidak pernah di-load**, walaupun ada di folder.
- File yang terdaftar tapi tidak ada di disk membuat install gagal.
- Kalau model kamu memakai `_inherit = ['mail.thread']`, tambahkan `'mail'` ke `depends`.

> **Beda di Odoo 19:** prefix seri pada versi menjadi `19.0` (mis. `19.0.1.0.0`). Struktur folder dan field manifest di bab ini dipakai sama.

## File __init__.py

Setiap folder Python harus punya `__init__.py` yang meng-import isinya.

Root (`my_module/__init__.py`):

```python
from . import models
from . import controllers   # hanya kalau folder controllers ada
```

`models/__init__.py`:

```python
from . import model_name
```

File model baru yang tidak di-import di `__init__.py` tidak akan pernah terbaca oleh Odoo.

## Contoh Module Minimal: library_management

Struktur:

```
library_management/
├── __init__.py
├── __manifest__.py
├── models/
│   ├── __init__.py
│   └── book.py
└── security/
    └── ir.model.access.csv
```

Views belum ada di tahap ini; kita tambahkan di Bab 5. Untuk sekarang module cukup bisa di-install dan membuat tabel `library_book`.

### library_management/__init__.py

```python
from . import models
```

### library_management/__manifest__.py

```python
{
    'name': 'Library Management',
    'version': '1.0.0',
    'category': 'Library',
    'summary': 'Kelola buku perpustakaan',
    'license': 'LGPL-3',
    'depends': ['base'],
    'data': [
        'security/ir.model.access.csv',
    ],
    'installable': True,
    'application': True,
}
```

### library_management/models/__init__.py

```python
from . import book
```

### library_management/models/book.py

```python
from odoo import models, fields


class LibraryBook(models.Model):
    _name = 'library.book'
    _description = 'Library Book'

    name = fields.Char(string='Title', required=True)
    author = fields.Char(string='Author')
    isbn = fields.Char(string='ISBN')
    active = fields.Boolean(string='Active', default=True)
    date_release = fields.Date(string='Release Date')
    state = fields.Selection([
        ('available', 'Available'),
        ('borrowed', 'Borrowed'),
        ('lost', 'Lost'),
    ], string='Status', default='available')
    partner_id = fields.Many2one('res.partner', string='Borrower')
    description = fields.Text(string='Description')
    cover_image = fields.Binary(string='Cover Image')
```

Model dan field dijelaskan lengkap di [Bab 4](04-models-orm.md).

### library_management/security/ir.model.access.csv

```csv
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_library_book_user,library.book user,model_library_book,base.group_user,1,1,1,1
```

Tanpa file ini, user biasa tidak punya akses ke model dan Odoo menulis warning di log. Detail hak akses dibahas di Bab 6.

## Install dan Upgrade Module

### Lewat UI

1. Aktifkan developer mode (Settings > Activate the developer mode).
2. Buka Apps > **Update Apps List**.
3. Hapus filter "Apps" kalau perlu, cari `Library Management`, klik Install.

### Lewat CLI

```bash
# Install
docker compose exec odoo odoo -d odoo -i library_management --stop-after-init

# Upgrade (setelah edit)
docker compose exec odoo odoo -d odoo -u library_management --stop-after-init

# Lalu restart server utama
docker compose restart odoo
```

### Habis Edit Apa, Harus Ngapain?

| Yang kamu ubah | Yang perlu dilakukan |
|----------------|----------------------|
| Logika Python (isi method) | Restart server (atau dev mode `reload`) |
| Field baru/berubah di model | Upgrade module (`-u`) |
| File XML di `data` (view, menu, data) | Upgrade module (`-u`), atau dev mode `xml` untuk view |
| Menambah file baru di `data` | Update `__manifest__.py`, lalu upgrade (`-u`) |
| Module baru di `addons` | Update Apps List, lalu install |

Detail `--stop-after-init` dan `dev_mode` ada di [Bab 2](02-install-config.md).

## Troubleshooting

**Module tidak muncul di Apps:**
- Pastikan `installable` bukan `False`.
- Klik Update Apps List (butuh developer mode).
- Hapus filter "Apps" di pencarian, kalau `application` bernilai `False`.
- Pastikan folder module ada langsung di dalam `addons_path` dan punya `__manifest__.py`.

**Install gagal:**
```bash
docker compose logs odoo
```
Penyebab umum: file di `data` tidak ada di disk, XML salah, atau `depends` merujuk module yang tidak ada.

**Cek status module lewat shell:**
```bash
docker compose exec odoo odoo shell -d odoo
```
```python
env['ir.module.module'].search([('name', '=', 'library_management')]).state
```

## Best Practices

1. **Penamaan**: snake_case untuk file dan folder, CamelCase untuk class.
2. **Prefix unik**: pakai prefix seperti `library_` agar tidak bentrok dengan module lain.
3. **Dependency seperlunya**: tiap `depends` menambah beban dan risiko konflik saat upgrade.
4. **Versi**: gunakan format `<seri>.<major>.<minor>.<patch>`, mis. `18.0.1.0.0`, dan naikkan saat ada perubahan.

## Ringkasan

- Module = folder dengan `__init__.py` dan `__manifest__.py`.
- Hanya `name` yang wajib di manifest; `installable` default `True`, `application` default `False`.
- Urutan file di `data` penting, dan file yang tidak terdaftar tidak di-load.
- File Python baru harus di-import lewat `__init__.py`, kalau tidak Odoo tidak melihatnya.
- Install pakai `-i`, upgrade pakai `-u`, keduanya dengan `--stop-after-init` saat dijalankan lewat `exec`.
- Field baru di model butuh upgrade module, sedangkan perubahan isi method cukup restart.
- Model yang `_inherit` ke `mail.thread` perlu `'mail'` di `depends`.

## Latihan

1. Buat module `library_management` persis seperti contoh di `./addons`, update Apps List, lalu install lewat UI.
2. Tambahkan field `pages = fields.Integer()` ke model, upgrade lewat CLI, lalu cek kolom `pages` di tabel `library_book` memakai psql (`\d library_book`).
3. Sengaja tulis nama file yang salah di `data` (mis. `security/ir.model.access.csvv`), jalankan upgrade, dan baca pesan error di log. Perbaiki lagi.

## Lanjut ke

[Bab 4: Models & ORM](04-models-orm.md)
