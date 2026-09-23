# Bab 4: Models & ORM

> **Catatan versi:** Disesuaikan dengan Odoo 18 dan 19. Perubahan utama dibanding versi lama:
> - Parameter `states={...}` **di level field Python** (bukan di view) **sudah dihapus di Odoo 18**. Logika readonly/required dinamis sekarang ditangani lewat `compute` + `readonly=False` (dengan `precompute`/`store`), atau lewat atribut inline di view (`invisible=`, `readonly=`, dst — lihat Bab 5).
> - `name_get()` sudah **deprecated sejak Odoo 17** dan makin ditinggalkan di 18/19, diganti `_compute_display_name()`.
> - Pola override `create()` standar sekarang **batch-style** dengan `@api.model_create_multi`, menerima `vals_list` (list of dict), bukan satu `vals` dict.
> - Operasi one2many/many2many pakai `Command` object (`from odoo import Command`), bukan lagi tuple angka `(0, 0, {...})`.
> - `@api.multi` sudah lama tidak ada lagi (dihapus sejak Odoo 11) — jangan dipakai di kode baru.
> - `read_group()` digantikan `_read_group()` dengan API baru (return record objects, bukan dict).
> - Sejak Odoo 18, ada opsi deklaratif baru `models.Constraint` sebagai alternatif `_sql_constraints`.

## Dasar Model

Model di Odoo adalah Python class yang mapping ke database table.

```python
from odoo import models, fields, api

class LibraryBook(models.Model):
    _name = 'library.book'
    _description = 'Library Book'
    _inherit = ['mail.thread', 'mail.activity.mixin']

    name = fields.Char(string='Title', required=True)
```

**Inheritance attributes:**

| Attribute | Fungsi |
|----------|--------|
| `_name` | Nama unik model (dot notation: library.book) |
| `_description` | Deskripsi untuk user |
| `_inherit` | Parent model(s) untuk inheritance |
| `_table` | Nama table DB (auto-generated dari _name) |
| `_order` | Default sort field, default: id |
| `_rec_name` | Field untuk display name, default: name |

## Field Types

### Basic Fields

```python
name = fields.Char(string='Name', size=100, required=True)
description = fields.Text(string='Description')
bio = fields.Html(string='Biography', sanitize=True)
age = fields.Integer(string='Age', default=0)
price = fields.Float(string='Price', digits=(10, 2))
is_active = fields.Boolean(string='Active', default=True)
birth_date = fields.Date(string='Birth Date')
create_date = fields.Datetime(string='Created At')
```

### Selection Fields

```python
state = fields.Selection([
    ('draft', 'Draft'),
    ('confirm', 'Confirmed'),
    ('done', 'Done'),
    ('cancel', 'Cancelled'),
], string='Status', default='draft', tracking=True)

# Dynamic selection (method-based)
priority = fields.Selection(selection='_selection_priority')

@api.model
def _selection_priority(self):
    return [
        ('low', 'Low'),
        ('medium', 'Medium'),
        ('high', 'High'),
    ]
```

### Relational Fields

```python
# Many2one - Satu relasi ke model lain
partner_id = fields.Many2one('res.partner', string='Partner')

# Many2one dengan domain
country_id = fields.Many2one(
    'res.country',
    string='Country',
    domain=[('is_eu', '=', True)]
)

# One2many - Satu ke banyak
line_ids = fields.One2many(
    'library.book.line',
    'book_id',
    string='Lines'
)

# Many2many - Banyak ke banyak
tag_ids = fields.Many2many(
    'library.tag',
    'library_book_tag_rel',
    'book_id',
    'tag_id',
    string='Tags'
)

# Reference - Generic reference
res_id = fields.Reference([
    ('res.partner', 'Partner'),
    ('res.users', 'User'),
], string='Reference')
```

### Menulis nilai One2many/Many2many: pakai `Command`

Sejak Odoo 17+, cara resmi untuk membuat/mengubah/menghapus baris one2many atau many2many adalah lewat `Command`, bukan lagi tuple angka `(0, 0, {...})` yang harus dihafal artinya.

```python
from odoo import Command  # bukan dari odoo.fields!

self.env['library.book'].create({
    'name': 'Clean Code',
    'line_ids': [
        Command.create({'chapter': 'Intro'}),      # dulu: (0, 0, {...})
        Command.update(line_id, {'chapter': 'X'}), # dulu: (1, id, {...})
        Command.delete(old_line_id),                # dulu: (2, id, 0)
        Command.unlink(other_line_id),               # dulu: (3, id, 0)
        Command.link(existing_line_id),               # dulu: (4, id, 0)
    ],
    'tag_ids': [Command.set([tag1.id, tag2.id])],     # dulu: (6, 0, [ids])
})
```

## Field Attributes

```python
name = fields.Char(
    string='Display Name',
    required=True,
    index=True,
    translate=True,
    help='Tooltip description',
    default='Default Value',
    readonly=True,
)
```

> ⚠️ **Parameter `states={...}` di field Python sudah dihapus di Odoo 18** (contoh lama: `readonly=True, states={'draft': [('readonly', False)]}`). Kalau butuh field yang readonly/required tergantung state, ada dua opsi pengganti:
>
> **Opsi 1 — Compute + `readonly=False`** (field tetap `store=True`, nilainya dihitung tapi user bisa override selama masih dianggap "readonly=False" oleh compute):
> ```python
> partner_id = fields.Many2one(
>     'res.partner',
>     compute='_compute_partner_id', store=True, readonly=False, precompute=True,
> )
> ```
>
> **Opsi 2 — Atur langsung di view** (lebih umum dipakai, lihat Bab 5):
> ```xml
> <field name="partner_id" readonly="state != 'draft'"/>
> ```

## Compute & Related Fields

```python
# Computed field
full_name = fields.Char(
    string='Full Name',
    compute='_compute_full_name',
    store=True,
    compute_sudo=True,
)

@api.depends('first_name', 'last_name')
def _compute_full_name(self):
    for record in self:
        record.full_name = f"{record.first_name} {record.last_name}"

# Related field
country_name = fields.Char(
    string='Country',
    related='partner_id.country_id.name',
    readonly=True,
)
```

## Menampilkan Nama Record: `_compute_display_name` (bukan `name_get`)

`name_get()` sudah lama diganti oleh field computed `display_name`. Di Odoo 17/18/19, cara yang benar adalah override `_compute_display_name`:

```python
class LibraryBook(models.Model):
    _name = 'library.book'

    name = fields.Char(required=True)
    author = fields.Char()

    def _compute_display_name(self):
        for record in self:
            record.display_name = f"{record.name} ({record.author})" if record.author else record.name
```

Kalau meng-extend model lain yang sudah punya `_compute_display_name`, panggil `super()` seperti compute biasa:

```python
class SaleOrder(models.Model):
    _inherit = 'sale.order'

    def _compute_display_name(self):
        super()._compute_display_name()
        for record in self:
            record.display_name = f"{record.display_name} (Custom)"
```

Karena `display_name` sekarang field computed biasa, bisa di-`store=True` dan dipakai untuk sorting/filter di search.

## Constraints

```python
# SQL constraint (masih valid di semua versi)
_sql_constraints = [
    ('name_uniq', 'unique(name)', 'Name must be unique!'),
    ('price_positive', 'CHECK(price > 0)', 'Price must be positive!'),
]

# Alternatif deklaratif baru (Odoo 18+): models.Constraint
from odoo.models import Constraint

_constraints = [
    Constraint('name_uniq', 'UNIQUE(name)', 'Name must be unique!'),
    Constraint('price_positive', 'CHECK(price > 0)', 'Price must be positive!'),
]

# Python constraint
@api.constrains('date_to', 'date_from')
def _check_dates(self):
    for record in self:
        if record.date_to < record.date_from:
            raise ValidationError('End date must be after start date!')
```

> `_sql_constraints` tetap berfungsi di Odoo 18/19 — belum wajib migrasi. `models.Constraint` adalah arah baru yang lebih terintegrasi dengan ORM, tapi keduanya masih didukung.

## ORM Methods

```python
# Create
record = self.env['library.book'].create({
    'name': 'New Book',
    'price': 100.0,
})

# Create banyak sekaligus (lebih efisien daripada create() satu-satu dalam loop)
records = self.env['library.book'].create([
    {'name': 'Book A', 'price': 50.0},
    {'name': 'Book B', 'price': 75.0},
])

# Search
books = self.env['library.book'].search([
    ('price', '>', 50),
    ('state', '=', 'available'),
])

# Browse
book = self.env['library.book'].browse(1)

# Write
book.write({'price': 150.0})

# Unlink (delete)
book.unlink()

# Read
data = book.read(['name', 'price'])
```

### `_read_group()` menggantikan `read_group()`

API grouping baru mengembalikan tuple berisi record object langsung (bukan dict dengan format `group['field'][1]` untuk ambil nama relasi).

```python
# Cara baru (Odoo 17+)
results = self.env['library.book']._read_group(
    domain=[('state', '=', 'available')],
    groupby=['partner_id'],
    aggregates=['price:sum', '__count'],
)
for partner, price_sum, count in results:
    print(partner.name, price_sum, count)  # partner sudah berupa record, bukan dict
```

### Invalidate cache & flush

```python
# Cara baru (Odoo 17+), menggantikan invalidate_cache()/flush()
records.invalidate_recordset(['name', 'price'])
records.flush_recordset(['name', 'price'])
# Atau di level model:
self.env['library.book'].invalidate_model(['name'])
self.env['library.book'].flush_model(['name'])
```

## Search Domain

```python
# Basic operators
[('field', '=', value)]
[('field', '!=', value)]
[('field', '>', value)]
[('field', '<', value)]
[('field', '>=', value)]
[('field', '<=', value)]

# String operators
[('name', 'ilike', 'pattern')]  # case-insensitive like
[('name', 'like', 'pattern')]   # case-sensitive like
[('name', 'not ilike', 'pattern')]

# In/Not in
[('state', 'in', ['draft', 'done'])]
[('state', 'not in', ['cancel'])]

# Special
[('field', '=', False)]  # is null
[('field', '!=', False)] # is not null

# Combine domains
domain = ['&', ('state', '=', 'done'), ('price', '>', 100)]
domain = ['|', ('field1', '=', 1), ('field2', '=', 2)]
```

> Sejak Odoo 17, tersedia juga API `odoo.fields.Domain` / `odoo.domain.Domain` untuk menyusun domain secara terprogram dengan operator Python (`Domain('state', '=', 'done') & Domain('price', '>', 100)`) sebagai alternatif format list `['&', (...), (...)]` di atas. Format list lama tetap sepenuhnya didukung.

## API Decorators

```python
@api.model          # Method tidak pakai recordset (dipanggil di level class/env)
@api.depends()       # Trigger recompute
@api.onchange()      # Trigger on UI change
@api.constrains()    # Validation constraint
@api.returns()       # Specify return model
@api.model_create_multi  # Menandai create() menerima list of dict (vals_list)

# Contoh onchange
@api.onchange('partner_id')
def _onchange_partner(self):
    if self.partner_id:
        self.email = self.partner_id.email

# Contoh depends
@api.depends('list_price', 'cost')
def _compute_margin(self):
    for record in self:
        record.margin = record.list_price - record.cost
```

> `@api.multi` **tidak ada lagi** (sudah dihapus sejak Odoo 11) — semua method recordset memang defaultnya bekerja atas `self` yang bisa berisi banyak record, tanpa decorator tambahan. Jangan tulis ulang decorator ini di kode baru.

## Lifecycle Hooks

Pola override `create()` standar sekarang **batch-style**: menerima `vals_list` (list berisi banyak dict), ditandai dengan `@api.model_create_multi`.

```python
class LibraryBook(models.Model):
    _name = 'library.book'

    @api.model_create_multi
    def create(self, vals_list):
        # Before create — vals_list adalah list of dict
        for vals in vals_list:
            if vals.get('name'):
                vals['name'] = vals['name'].upper()
        records = super().create(vals_list)
        # After create
        return records

    def write(self, vals):
        # Before write
        result = super().write(vals)
        # After write
        return result

    def unlink(self):
        # Before delete
        return super().unlink()

    def search_read(self, domain=None, fields=None, offset=0, limit=None, order=None):
        return super().search_read(domain, fields, offset, limit, order)
```

> Meng-override `create(self, vals)` gaya lama (satu dict, tanpa `@api.model_create_multi`) masih jalan karena ORM otomatis membungkusnya, tapi **tidak direkomendasikan** untuk kode baru — bisa jadi tidak efisien saat ORM internal memanggil `create()` dengan banyak record sekaligus (misalnya saat import data).

## Action Methods

```python
def action_confirm(self):
    self.write({'state': 'confirm'})
    return True

def action_cancel(self):
    self.write({'state': 'cancel'})
    return {
        'type': 'ir.actions.act_window_close',
    }

def action_open_wizard(self):
    return {
        'name': 'Wizard Title',
        'type': 'ir.actions.act_window',
        'res_model': 'library.wizard',
        'view_mode': 'form',
        'target': 'new',
    }
```

## Ringkasan Perubahan Versi

| Area | Odoo ≤16 | Odoo 17 | Odoo 18 | Odoo 19 |
|---|---|---|---|---|
| `states=` di field Python | Dipakai | Masih ada (deprecated) | **Dihapus** | Dihapus |
| `name_get()` | Dipakai | Deprecated, pakai `_compute_display_name` | `_compute_display_name` wajib | Sama |
| One2many/Many2many write | Tuple `(0,0,{})` dll | `Command` object direkomendasikan | Sama | Sama |
| `create()` override | `create(self, vals)` | Direkomendasikan `@api.model_create_multi` | Sama | Sama |
| `read_group()` | Dipakai | `_read_group()` baru tersedia | `read_group()` makin ditinggalkan | Sama |
| `invalidate_cache()` / `flush()` | Dipakai | Diganti `invalidate_recordset/model`, `flush_recordset/model` | Sama | Sama |
| `_sql_constraints` | Satu-satunya cara | Sama | Alternatif `models.Constraint` tersedia | Sama |
| `@api.multi` | Sudah lama tidak ada | Tidak ada | Tidak ada | Tidak ada |

**Saran:** untuk modul baru yang ditarget Odoo 18/19, hindari `states=` di field Python dan `name_get()`, gunakan `Command` untuk relasi, dan pakai pola `@api.model_create_multi` pada `create()`.
