# Bab 3: Struktur Module Odoo 18

## Struktur Direktori Module

```
my_module/
├── __init__.py           # Import module
├── __manifest__.py       # Metadata module (wajib)
├── models/
│   ├── __init__.py
│   └── model_name.py     # Model Python
├── views/
│   ├── views.xml         # Form, tree, search views
│   └── templates.xml     # QWeb templates
├── controllers/
│   ├── __init__.py
│   └── main.py           # HTTP endpoints
├── security/
│   └── ir.model.access.csv
├── data/
│   └── data.xml          # Demo/data files
└── static/
    ├── src/
    │   ├── js/
    │   ├── xml/
    │   └── scss/
    └── description/
        └── icon.png
```

## __manifest__.py (Wajib)

```python
{
    'name': "My Module",
    'version': '1.0.0',
    'summary': 'Short description',
    'description': """
        Long description
        multi-line
    """,
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

**Fields utama:**

| Field | Wajib | Deskripsi |
|-------|-------|-----------|
| `name` | Ya | Nama module |
| `version` | Ya | Version number |
| `depends` | Tidak | Module dependencies |
| `data` | Tidak | File loaded saat install/upgrade |
| `demo` | Tidak | File loaded saat demo install |
| `installable` | Ya | Bisa di-install |
| `application` | Ya | Muncul di Apps menu |

## __init__.py (Root)

```python
from . import models
from . import controllers
```

## models/__init__.py

```python
from . import model_name
```

## Contoh Module Sederhana

```
library_app/
├── __init__.py
├── __manifest__.py
├── models/
│   ├── __init__.py
│   └── book.py
└── views/
    ├── views.xml
    └── templates.xml
```

### library_app/__manifest__.py

```python
{
    'name': 'Library Management',
    'version': '1.0.0',
    'category': 'Library',
    'depends': ['base'],
    'data': [
        'security/ir.model.access.csv',
        'views/views.xml',
    ],
    'installable': True,
}
```

### library_app/models/book.py

```python
from odoo import models, fields, api

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

## Install Module

```bash
# Via UI
# 1. Aktifkan developer mode: Settings > Activate Dev Mode
# 2. Buka Apps > Update Apps List
# 3. Search module, klik Install

# Via CLI
docker compose exec odoo odoo -d odoo -i library_app

# Update module (setelah edit)
docker compose exec odoo odoo -d odoo -u library_app
```

## Debugging

**Module tidak muncul:**
- Pastikan `installable: True`
- Update Apps List
- Cek `data` section di manifest, file harus ada

**Install gagal:**
```bash
# Lihat log
docker compose logs odoo

# Via Odoo shell
docker compose exec odoo odoo shell -d odoo
# Lalu ketik: env['ir.module.module'].search([('name','=','library_app')])
```

## Best Practices

1. **Naming**: snake_case untuk file, CamelCase untuk class
2. **Prefix**: Pakai prefix unik (misal `library_`) supaya tidak bentrok
3. **Dependencies**: Jangan terlalu banyak dependency
4. **Versioning**: Gunakan semantic versioning (1.0.0, 1.0.1, dst)