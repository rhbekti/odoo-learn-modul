# Bab 4: Models & ORM

> **Tahap:** 2 Inti Pengembangan | **Prasyarat:** Bab 3 | **Estimasi:** ± 3,5 jam | **Versi:** Odoo 18 (catatan Odoo 19)

## Tujuan Belajar

Setelah bab ini kamu bisa:
- Mendefinisikan model dengan atribut dasar (`_name`, `_description`, `_inherit`, `_order`, `_rec_name`).
- Memilih tipe field yang tepat, termasuk field relasi, dan menulis relasi dengan `Command`.
- Membuat field compute/related dan mengatur nama tampilan lewat `_compute_display_name`.
- Menambah constraint (SQL dan Python) serta memakai method ORM dasar (create, search, write, unlink, `_read_group`).
- Mengolah recordset dengan `mapped`, `filtered`, `sorted`, operasi himpunan, `ensure_one`, `browse`, dan `exists`.
- Menghindari query di dalam loop (N+1) dengan `_read_group` atau `search_count` di luar loop.
- Menulis domain pencarian dan meng-override `create`/`write`/`unlink` dengan benar.

## Dasar Model

Model di Odoo adalah Python class yang dipetakan ke tabel database.

```python
from odoo import models, fields, api


class LibraryBook(models.Model):
    _name = 'library.book'
    _description = 'Library Book'
    _inherit = ['mail.thread', 'mail.activity.mixin']

    name = fields.Char(string='Title', required=True)
```

Karena `_inherit` di atas memakai `mail.thread`, module kamu harus punya `'mail'` di `depends` (lihat Bab 3).

| Atribut | Fungsi |
|---------|--------|
| `_name` | Nama unik model (notasi titik: `library.book`) |
| `_description` | Deskripsi yang terbaca manusia |
| `_inherit` | Model induk yang diwarisi/di-extend (dibahas lengkap di Bab 8) |
| `_table` | Nama tabel DB (otomatis dari `_name`, titik jadi underscore) |
| `_order` | Urutan default, default `id` |
| `_rec_name` | Field yang dipakai sebagai nama record, default `name` |

Odoo otomatis menambah field `id`, `create_date`, `create_uid`, `write_date`, `write_uid`. Jangan didefinisikan ulang.

Semua potongan kode di bab ini adalah fragmen dari model `library.book` yang punya field: `name`, `author`, `price`, `cost`, `state`, `partner_id`, `borrower_email`, `date_borrow`, `date_return`, `line_ids`, `tag_ids`. Model `library.book.line` dan `library.tag` hanya ilustrasi relasi.

## Tipe Field

### Field Dasar

```python
name = fields.Char(string='Name', size=100, required=True)
description = fields.Text(string='Description')
bio = fields.Html(string='Biography', sanitize=True)
age = fields.Integer(string='Age', default=0)
price = fields.Float(string='Price', digits=(10, 2))
is_active = fields.Boolean(string='Active', default=True)
birth_date = fields.Date(string='Birth Date')
date_borrow = fields.Datetime(string='Borrowed At')
```

### Selection

```python
state = fields.Selection([
    ('draft', 'Draft'),
    ('confirm', 'Confirmed'),
    ('done', 'Done'),
    ('cancel', 'Cancelled'),
], string='Status', default='draft', tracking=True)

# Selection dinamis (lewat method)
priority = fields.Selection(selection='_selection_priority')

@api.model
def _selection_priority(self):
    return [
        ('low', 'Low'),
        ('medium', 'Medium'),
        ('high', 'High'),
    ]
```

### Field Relasi

```python
# Many2one: banyak record ini menunjuk satu record lain
partner_id = fields.Many2one('res.partner', string='Partner')

# Many2one dengan domain
borrower_id = fields.Many2one(
    'res.partner',
    string='Borrower',
    domain=[('is_company', '=', False)],
)

# One2many: kebalikan dari Many2one (field kedua = nama Many2one di model tujuan)
line_ids = fields.One2many('library.book.line', 'book_id', string='Lines')

# Many2many: nama tabel relasi, kolom model ini, kolom model tujuan
tag_ids = fields.Many2many(
    'library.tag',
    'library_book_tag_rel',
    'book_id',
    'tag_id',
    string='Tags',
)

# Reference: menunjuk ke record dari model apa saja
ref_doc = fields.Reference([
    ('res.partner', 'Partner'),
    ('res.users', 'User'),
], string='Reference')
```

### Menulis One2many/Many2many dengan `Command`

Cara resmi untuk membuat/mengubah/menghapus baris one2many atau many2many adalah `Command`, bukan tuple angka seperti `(0, 0, {...})` yang harus dihafal artinya.

```python
from odoo import Command

self.env['library.book'].create({
    'name': 'Clean Code',
    'line_ids': [
        Command.create({'chapter': 'Intro'}),       # dulu: (0, 0, {...})
        Command.update(line_id, {'chapter': 'X'}),  # dulu: (1, id, {...})
        Command.delete(old_line_id),                # dulu: (2, id, 0)
        Command.unlink(other_line_id),              # dulu: (3, id, 0)
        Command.link(existing_line_id),             # dulu: (4, id, 0)
    ],
    'tag_ids': [Command.set([tag1.id, tag2.id])],   # dulu: (6, 0, [ids])
})
```

Beda `delete` dan `unlink`: `delete` menghapus record-nya dari database, `unlink` hanya memutus relasi.

## Atribut Field

```python
name = fields.Char(
    string='Display Name',
    required=True,
    index=True,
    translate=True,
    copy=False,
    help='Tooltip description',
    default='Default Value',
    readonly=True,
)
```

Parameter `states={...}` di field Python (contoh lama: `readonly=True, states={'draft': [('readonly', False)]}`) tidak dipakai lagi di Odoo 18, jangan ditulis di kode baru. Untuk field yang readonly/required tergantung state, ada dua pengganti:

**Opsi 1: compute dengan `readonly=False`.** Nilainya dihitung otomatis, tapi user tetap boleh mengubahnya:

```python
partner_id = fields.Many2one(
    'res.partner',
    compute='_compute_partner_id', store=True, readonly=False, precompute=True,
)
```

**Opsi 2: atur langsung di view** (paling umum, dibahas di Bab 5):

```xml
<field name="partner_id" readonly="state != 'draft'"/>
```

## Compute dan Related Field

```python
# Computed field
full_title = fields.Char(
    string='Full Title',
    compute='_compute_full_title',
    store=True,
)

@api.depends('name', 'author')
def _compute_full_title(self):
    for record in self:
        record.full_title = f"{record.name} - {record.author}" if record.author else record.name

# Selisih harga jual dan modal
margin = fields.Float(compute='_compute_margin')

@api.depends('price', 'cost')
def _compute_margin(self):
    for record in self:
        record.margin = record.price - record.cost

# Related field
country_name = fields.Char(
    string='Country',
    related='partner_id.country_id.name',
    readonly=True,
)
```

Aturan compute:
- `@api.depends` harus mencantumkan semua field yang dipakai. Kalau ada yang terlewat, hasil tidak ter-update.
- Method compute wajib mengisi field untuk **setiap** record di `self`, makanya pakai `for record in self`.
- Tanpa `store=True`, nilai dihitung saat dibaca dan tidak bisa dipakai untuk search/group.

## Nama Tampilan: `_compute_display_name`

`name_get()` sudah deprecated sejak Odoo 17. Gantinya, override `_compute_display_name` yang mengisi field `display_name`:

```python
class LibraryBook(models.Model):
    _name = 'library.book'

    name = fields.Char(required=True)
    author = fields.Char()

    @api.depends('name', 'author')
    def _compute_display_name(self):
        for record in self:
            record.display_name = f"{record.name} ({record.author})" if record.author else record.name
```

Kalau meng-extend model lain yang sudah punya `_compute_display_name`, panggil `super()` lalu tambahkan hasilnya:

```python
class SaleOrder(models.Model):
    _inherit = 'sale.order'

    @api.depends('state')
    def _compute_display_name(self):
        super()._compute_display_name()
        for record in self:
            record.display_name = f"{record.display_name} [{record.state}]"
```

## Constraint

```python
from odoo.exceptions import ValidationError

# SQL constraint (dipakai di Odoo 18)
_sql_constraints = [
    ('name_uniq', 'unique(name)', 'Name must be unique!'),
    ('price_positive', 'CHECK(price > 0)', 'Price must be positive!'),
]

# Python constraint
@api.constrains('date_borrow', 'date_return')
def _check_dates(self):
    for record in self:
        if record.date_borrow and record.date_return and record.date_return < record.date_borrow:
            raise ValidationError('Return date must be after borrow date!')
```

Pakai SQL constraint untuk aturan sederhana pada satu tabel (cepat dan dijaga oleh database). Pakai Python constraint untuk aturan yang butuh logika.

> **Beda di Odoo 19:** constraint bisa ditulis deklaratif dengan `models.Constraint`, atribut class berawalan `_`:
> ```python
> _name_uniq = models.Constraint('UNIQUE(name)', 'Name must be unique!')
> _price_positive = models.Constraint('CHECK(price > 0)', 'Price must be positive!')
> ```
> Odoo 19 juga punya `models.Index` dan `models.UniqueIndex`. Di dokumentasi Odoo 18, cara resminya tetap `_sql_constraints`. Sebagai petunjuk arah: di kode sumber 19.0 model `ir.cron` sudah memakai `models.Constraint`, sedangkan di 18.0 masih `_sql_constraints`.

## Method ORM

```python
# Create
record = self.env['library.book'].create({
    'name': 'New Book',
    'price': 100.0,
})

# Create banyak sekaligus (lebih efisien daripada create() dalam loop)
records = self.env['library.book'].create([
    {'name': 'Book A', 'price': 50.0},
    {'name': 'Book B', 'price': 75.0},
])

# Search
books = self.env['library.book'].search([
    ('price', '>', 50),
    ('state', '=', 'available'),
], limit=5, order='price desc')
total = self.env['library.book'].search_count([('state', '=', 'available')])

# Browse (ambil record dari ID, tanpa query pencarian)
book = self.env['library.book'].browse(1)

# Write
book.write({'price': 150.0})

# Unlink (hapus)
book.unlink()

# Read (hasilnya list of dict)
data = book.read(['name', 'price'])
```

### Grouping dengan `_read_group`

`_read_group` mengembalikan list tuple. Untuk field many2one, nilainya sudah berupa record, bukan dict atau pasangan `(id, nama)`.

```python
results = self.env['library.book']._read_group(
    domain=[('state', '=', 'available')],
    groupby=['partner_id'],
    aggregates=['price:sum', '__count'],
)
for partner, price_sum, count in results:
    print(partner.name, price_sum, count)
```

> **Beda di Odoo 19:** dokumentasi ORM Odoo 19 hanya mencantumkan `_read_group`. Di Odoo 18, `read_group` (hasil berupa list dict) masih terdokumentasi, tapi untuk kode baru `_read_group` lebih nyaman dan dipakai sama di kedua versi.

### Invalidate Cache dan Flush

```python
# Pada recordset
records.invalidate_recordset(['name', 'price'])
records.flush_recordset(['name', 'price'])

# Pada level model
self.env['library.book'].invalidate_model(['name'])
self.env['library.book'].flush_model(['name'])
```

Method lama `invalidate_cache()` dan `flush()` sudah diganti oleh method di atas. Kamu jarang butuh ini kecuali menulis SQL mentah.

## Operasi Recordset

Hasil `search()`, `browse()`, dan field relasi (many2one, one2many, many2many) selalu berupa **recordset**: kumpulan record dari satu model, bisa berisi nol, satu, atau banyak record. Bagian ini memakai model dari module `library_management` di Bab 10 (`library.loan` dengan `member_id`, `loan_date`, `due_date`, `state`, `is_overdue`, `line_ids`; `library.loan.line` dengan `copy_id` dan `book_id`; `library.book.copy` dengan `state`). Kamu bisa mencobanya di `odoo shell`.

```python
loans = self.env['library.loan'].search([('state', '=', 'active')])
```

### Ukuran, Iterasi, dan `in`

```python
len(loans)            # jumlah record
bool(loans)           # False kalau kosong, jadi `if loans:` aman dipakai

for loan in loans:    # tiap iterasi menghasilkan recordset berisi SATU record
    print(loan.name, loan.due_date)

first = loans[0]      # index dan slice juga menghasilkan recordset
some = loans[:5]
```

Operator `in` menguji apakah sebuah record ada di dalam recordset:

```python
loan = loans[0]
loan in loans                  # True
loan.member_id in loans.mapped('member_id')   # True
```

Sisi kiri `in` harus satu record dari model yang sama dengan recordset di sisi kanan.

### `mapped()`: Ambil Nilai dari Banyak Record

`mapped()` menerima nama field (boleh bertitik untuk menelusuri relasi) atau fungsi/lambda.

```python
loans.mapped('name')                       # list: ['LN/0001', 'LN/0002', ...]
loans.mapped('member_id')                  # recordset library.member (tanpa duplikat)
loans.mapped('line_ids.copy_id.book_id')   # recordset library.book dari semua baris loan
loans.mapped(lambda l: (l.due_date - l.loan_date).days)   # list: lama pinjam dalam hari
```

Aturannya: kalau hasilnya field biasa (Char, Integer, ...), kamu mendapat **list**; kalau hasilnya field relasi, kamu mendapat **recordset** yang duplikatnya sudah dibuang, dan urutannya tidak dijamin. Lambda yang mengembalikan recordset juga diperlakukan sama.

### `filtered()`: Saring di Python

`filtered()` menyaring recordset yang sudah ada di memori tanpa query pencarian baru.

```python
overdue = loans.filtered(lambda l: l.is_overdue)
overdue = loans.filtered('is_overdue')                 # string: nama field, lolos kalau nilainya truthy
with_lines = loans.filtered('line_ids')                # one2many tidak kosong
premium = loans.filtered(lambda l: l.member_id.membership_type == 'premium')
```

String boleh bertitik (`'member_id.partner_id.active'`); record lolos kalau salah satu nilai di sepanjang jalur itu truthy. Untuk kondisi perbandingan seperti `== 'premium'`, pakai lambda. Ada juga `filtered_domain([('state', '=', 'active')])` kalau kamu lebih nyaman dengan sintaks domain.

> **Beda di Odoo 19:** di kode sumber 19.0, `filtered()` juga menerima objek `Domain` (`records.filtered(Domain('state', '=', 'active'))`); di 18.0 hanya fungsi atau string. Lambda dan string seperti di atas jalan di kedua versi. Bonus: `grouped(key)` (membagi recordset jadi dict `{nilai: recordset}`) ada di kode sumber 18.0 maupun 19.0.

### `sorted()`: Urutkan di Python

```python
loans.sorted('due_date')                              # nama field
loans.sorted(key=lambda l: l.due_date, reverse=True)  # lambda + terbalik
loans.sorted(lambda l: (l.member_id.name, l.due_date))  # kunci majemuk (tuple)
loans.sorted()                                        # tanpa key: urutan `_order` model
```

`sorted()` mengembalikan recordset baru, `loans` sendiri tidak berubah. Kalau nilai kunci bisa kosong (`False`) bercampur dengan nilai lain, perbandingan bisa error; beri nilai cadangan di lambda, misalnya `l.return_date or l.due_date`.

### Operasi Himpunan: `|`, `&`, `-`, `+`

```python
overdue = loans.filtered('is_overdue')
on_time = loans - overdue          # ada di loans, tidak ada di overdue
both    = loans & overdue          # irisan
either  = on_time | overdue        # gabungan, tanpa duplikat
combined = on_time + overdue       # penyambungan; duplikat tidak dibuang
```

Semua operasi ini mempertahankan urutan kemunculan pertama, dan kedua sisi harus berasal dari model yang sama (kalau tidak, `TypeError`). Hasilnya recordset baru; tidak ada query ke database.

### `ensure_one()`: Pastikan Tepat Satu Record

Akses field langsung (`loan.due_date`) hanya aman pada satu record. Di method yang dipanggil dari tombol pada satu record, tegaskan itu di awal:

```python
def action_extend_due_date(self):
    self.ensure_one()          # ValueError "Expected singleton" kalau len(self) != 1
    self.due_date = fields.Date.add(self.due_date, days=7)
```

Kalau method memang boleh dipanggil untuk banyak record, jangan pakai `ensure_one()`; tulis `for loan in self:`.

### `browse()` dan `exists()`

```python
Loan = self.env['library.loan']
loan = Loan.browse(5)             # satu record dari ID, tanpa query
loans = Loan.browse([1, 2, 3])    # beberapa ID

loans = loans.exists()            # buang record yang sudah terhapus dari database
if not loan.exists():
    ...
```

`browse()` tidak memeriksa apakah ID itu ada; error baru muncul saat field dibaca (`MissingError`). Pakai `exists()` kalau ID berasal dari luar (URL, parameter, data lama). `exists()` mengembalikan subset yang masih ada, jadi bisa dipakai sebagai kondisi `if`.

### Hindari Query di Dalam Loop (N+1)

Saat kamu iterasi sebuah recordset, ORM mengambil (prefetch) field dari record-record sekitarnya sekaligus, jadi membaca `loan.member_id.name` di dalam `for loan in loans` tidak berarti satu query per baris. Yang mahal adalah **memanggil `search`/`search_count`/`create`/`write` di dalam loop**, karena tiap iterasi menjadi satu query baru.

```python
# Buruk: satu search_count per member (N+1)
counts = {}
for member in members:
    counts[member.id] = self.env['library.loan'].search_count([
        ('member_id', '=', member.id),
        ('state', '=', 'active'),
    ])

# Baik: satu query untuk semua member, dikelompokkan di database
data = self.env['library.loan']._read_group(
    domain=[('member_id', 'in', members.ids), ('state', '=', 'active')],
    groupby=['member_id'],
    aggregates=['__count'],
)
counts = {member.id: count for member, count in data}
```

Member tanpa loan aktif tidak muncul di hasil `_read_group`, jadi baca dengan `counts.get(member.id, 0)`. Aturan yang sama berlaku untuk menulis: `create([...])` dengan banyak dict (lihat atas), atau satu `write()` pada seluruh recordset, lebih baik daripada `write()` per record dalam loop. Kalau cukup mengetahui jumlah total, satu `search_count()` di luar loop sudah cukup.

## Domain Pencarian

Domain adalah list kondisi untuk `search`, filter di view, dan lain-lain.

```python
# Operator perbandingan
[('field', '=', value)]
[('field', '!=', value)]
[('field', '>', value)]
[('field', '<', value)]
[('field', '>=', value)]
[('field', '<=', value)]

# Operator string
[('name', 'ilike', 'pattern')]      # tidak peka huruf besar/kecil
[('name', 'like', 'pattern')]       # peka huruf besar/kecil
[('name', 'not ilike', 'pattern')]

# in / not in
[('state', 'in', ['draft', 'done'])]
[('state', 'not in', ['cancel'])]

# Cek kosong
[('field', '=', False)]    # kosong
[('field', '!=', False)]   # tidak kosong
```

Beberapa kondisi dalam satu list otomatis digabung dengan AND. Operator logika memakai notasi prefix:

```python
# AND eksplisit
domain = ['&', ('state', '=', 'done'), ('price', '>', 100)]

# OR (berlaku untuk dua kondisi setelahnya)
domain = ['|', ('field1', '=', 1), ('field2', '=', 2)]

# (A atau B) dan C
domain = ['|', ('a', '=', 1), ('b', '=', 2), ('c', '=', 3)]
```

> **Beda di Odoo 19:** ada kelas `odoo.fields.Domain` untuk menyusun domain dengan operator Python:
> ```python
> from odoo.fields import Domain
> domain = Domain('state', '=', 'done') & Domain('price', '>', 100)
> ```
> Format list di atas tetap didukung di 18 dan 19.

## Decorator API

```python
@api.model                 # method tidak bergantung pada recordset tertentu
@api.depends('a', 'b')     # picu hitung ulang field compute
@api.onchange('field')     # picu perubahan di form saat user mengubah field
@api.constrains('field')   # validasi saat record disimpan
@api.returns('model')      # tentukan model hasil (jarang dipakai)
@api.model_create_multi    # create() menerima list of dict
```

Contoh `onchange`:

```python
@api.onchange('partner_id')
def _onchange_partner(self):
    if self.partner_id:
        self.borrower_email = self.partner_id.email
```

Kalau nilai sebuah field cukup diturunkan dari field lain, field compute dengan `store=True, readonly=False` biasanya lebih rapi daripada `onchange`.

`@api.multi` sudah tidak ada sejak Odoo 11. Method recordset otomatis bekerja atas `self` yang bisa berisi banyak record, jangan tulis decorator itu lagi.

## Override `create`, `write`, `unlink`

Override `create()` memakai pola batch: menerima `vals_list` (list of dict) dan diberi `@api.model_create_multi`.

```python
class LibraryBook(models.Model):
    _name = 'library.book'

    @api.model_create_multi
    def create(self, vals_list):
        # Sebelum create: vals_list adalah list of dict
        for vals in vals_list:
            if vals.get('name'):
                vals['name'] = vals['name'].upper()
        records = super().create(vals_list)
        # Sesudah create
        return records

    def write(self, vals):
        # Sebelum write
        result = super().write(vals)
        # Sesudah write
        return result

    def unlink(self):
        # Sebelum hapus
        return super().unlink()
```

Menulis `create(self, vals)` gaya lama (satu dict) masih jalan karena ORM membungkusnya, tapi tidak direkomendasikan. ORM bisa memanggil `create()` dengan banyak record sekaligus, misalnya saat import data.

## Action Method

Method yang dipanggil dari tombol di view, mengembalikan `True` atau dict action.

```python
def action_confirm(self):
    self.write({'state': 'confirm'})
    return True

def action_cancel(self):
    self.write({'state': 'cancel'})
    return {'type': 'ir.actions.act_window_close'}

def action_open_wizard(self):
    return {
        'name': 'Wizard Title',
        'type': 'ir.actions.act_window',
        'res_model': 'library.wizard',   # model wizard, dibahas di Bab 9
        'view_mode': 'form',
        'target': 'new',
    }
```

## Cheat Sheet Perubahan Versi

| Area | Odoo 18 | Odoo 19 |
|------|---------|---------|
| `states=` di field Python | Jangan dipakai; pakai compute/`readonly=False` atau atribut di view | Sama |
| Nama record | `_compute_display_name` (`name_get()` deprecated sejak 17) | Sama |
| Relasi one2many/many2many | `Command` | Sama |
| Override `create()` | `@api.model_create_multi` | Sama |
| Grouping | `_read_group` (dan `read_group` terdokumentasi) | `_read_group` |
| Constraint | `_sql_constraints` | `models.Constraint`, `models.Index`, `models.UniqueIndex` |
| Domain terprogram | List domain | List domain atau `fields.Domain` |

## Ringkasan

- Model = class Python dengan `_name` dan `_description`; field didefinisikan sebagai atribut class.
- Tulis relasi one2many/many2many dengan `Command`, bukan tuple angka.
- Field compute butuh `@api.depends` yang lengkap; tambahkan `store=True` kalau mau dipakai untuk search/group.
- Nama tampilan diatur lewat `_compute_display_name`, bukan `name_get()`.
- Di Odoo 18 constraint SQL ditulis dengan `_sql_constraints`; `models.Constraint` baru ada di Odoo 19.
- Override `create()` selalu dengan `@api.model_create_multi` dan `vals_list`.
- Untuk grouping pakai `_read_group`; `states=` di field Python dan `@api.multi` jangan dipakai.
- Recordset: `mapped` (list atau recordset), `filtered` (lambda/string), `sorted` (key, reverse), dan `|`, `&`, `-` bekerja di memori tanpa query baru.
- Pakai `ensure_one()` di method yang mengakses field langsung; `browse()` tidak mengecek keberadaan ID, `exists()` yang mengecek.
- Jangan `search`/`search_count` di dalam loop; satu `_read_group` di luar loop menggantikan N query.

## Latihan

1. Di `library_management` (Bab 3), tambahkan field `price`, `cost`, `author`, dan `date_borrow`/`date_return`. Tambahkan `_sql_constraints` agar `price` tidak boleh negatif dan `@api.constrains` agar `date_return` tidak boleh sebelum `date_borrow`. Upgrade module.
2. Tambahkan field compute `full_title` (stored) dan override `_compute_display_name` agar nama buku tampil sebagai `Judul (Penulis)`.
3. Buka `odoo shell`: buat tiga buku dengan satu panggilan `create([...])`, cari yang `price > 50` dengan `search`, lalu hitung total harga per `state` dengan `_read_group`. Panggil `env.cr.commit()` kalau mau datanya tersimpan.
4. Di `odoo shell` (dengan data dari Bab 10), ambil semua `library.loan` berstatus `active`. Tampilkan daftar nama member unik dengan `mapped`, pisahkan loan yang `is_overdue` dengan `filtered`, urutkan dari `due_date` terlama dengan `sorted`, lalu buktikan bahwa `loans - overdue` dan `loans & overdue` bersama-sama membentuk `loans`.
5. Tulis ulang loop yang memanggil `search_count` per member menjadi satu `_read_group`, lalu bandingkan jumlah query-nya (jalankan Odoo dengan `--log-level=debug_sql`).

## Lanjut ke

[Bab 5: Views XML](05-views-xml.md)
