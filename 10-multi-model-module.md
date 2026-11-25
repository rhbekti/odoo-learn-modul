# Bab 10: Multi-Model Module (Studi Kasus Library)

> **Tahap:** 2 Inti Pengembangan (proyek akhir) | **Prasyarat:** Bab 3–9 | **Estimasi:** ± 4 jam | **Versi:** Odoo 18 (catatan Odoo 19)

Bab ini adalah proyek akhir Tahap 2. Kita merangkai semua yang sudah dipelajari di Bab 4–9 (model, view, security, data, inheritance, wizard) menjadi satu module utuh dengan banyak model yang saling berhubungan: pola header-line, relasi antar-model, dan computed fields lintas model.

## Tujuan Belajar

Setelah bab ini kamu bisa:

- Merancang module dengan beberapa model yang saling berelasi (Many2one, One2many, Many2many).
- Menerapkan pola header-line (`library.loan` dan `library.loan.line`) lengkap dengan form, list, dan search view.
- Memakai delegation inheritance (`_inherits`) dan kategori rekursif (`_parent_store`).
- Menyusun urutan file module (manifest, model, security, data, view, menu) yang benar dan mengujinya secara manual.

## Studi Kasus: Library Management System

Kita akan membuat system perpustakaan lengkap dengan model-model berikut:

```
library.book           → Data buku
library.book.category  → Kategori buku (hierarki)
library.book.tag       → Tag buku (model kecil pendukung)
library.book.copy      → Salinan fisik buku (1 buku bisa punya banyak copy)
library.member         → Anggota perpustakaan
library.loan           → Peminjaman (header)
library.loan.line      → Detail peminjaman (lines)
library.fine           → Denda keterlambatan
```

Enam model inti: category, book, copy, member, loan, fine. Tag dan loan line adalah model pendukung.

## Peta Belajar: Urutan Membangun Module

Bangun module langkah demi langkah, dan install/upgrade setelah tiap langkah supaya error cepat ketahuan.

| Langkah | File yang dibuat | Isi | Konsep dari |
|---------|------------------|-----|-------------|
| 1 | `__manifest__.py`, `__init__.py` | Metadata, `depends`, urutan `data` | Bab 3 |
| 2 | `models/*.py` | 6 model inti + tag + loan line | Bab 4, 8 |
| 3 | `security/groups.xml`, `ir.model.access.csv` | Group User/Manager, akses semua model | Bab 6 |
| 4 | `data/sequence.xml`, `category_data.xml` | Penomoran member/loan, seed kategori | Bab 7 |
| 5 | `views/*_views.xml` | Form, list, search, action per model | Bab 5 |
| 6 | `views/menu.xml` | Struktur menu | Bab 5 |
| 7 | Uji manual | Install, buat buku, copy, member, loan, return | Bab 18 (debugging) jika error |

Untuk langkah 2, mulai dari model yang tidak bergantung pada model lain (category), lalu book, copy, member, loan, fine. Bab 9 (wizard) dipakai di bagian Latihan.

---

## Struktur Direktori

```
library_management/
├── __init__.py
├── __manifest__.py
├── models/
│   ├── __init__.py
│   ├── book_category.py
│   ├── book.py
│   ├── book_copy.py
│   ├── member.py
│   ├── loan.py
│   └── fine.py
├── views/
│   ├── book_category_views.xml
│   ├── book_views.xml          (termasuk view/action untuk tag)
│   ├── book_copy_views.xml
│   ├── member_views.xml
│   ├── loan_views.xml
│   ├── fine_views.xml
│   └── menu.xml
├── security/
│   ├── ir.model.access.csv
│   └── groups.xml
├── data/
│   ├── sequence.xml
│   └── category_data.xml
└── static/
    └── description/
        └── icon.png
```

---

## __manifest__.py

```python
{
    'name': 'Library Management',
    'version': '18.0.1.0.0',
    'category': 'Services/Library',
    'summary': 'Manage books, members, and loans',
    'depends': ['base', 'mail'],
    'data': [
        # Security pertama
        'security/groups.xml',
        'security/ir.model.access.csv',
        # Data
        'data/sequence.xml',
        'data/category_data.xml',
        # Views
        'views/book_category_views.xml',
        'views/book_views.xml',
        'views/book_copy_views.xml',
        'views/member_views.xml',
        'views/loan_views.xml',
        'views/fine_views.xml',
        'views/menu.xml',
    ],
    'installable': True,
    'application': True,
    'license': 'LGPL-3',
}
```

**Urutan `data` penting!** Security dulu, lalu data, lalu views, terakhir menu. Jika view atau menu merujuk group atau action yang belum di-load, akan error. Menu ditaruh paling akhir karena merujuk action yang didefinisikan di file views.

---

## models/__init__.py

```python
from . import book_category
from . import book
from . import book_copy
from . import member
from . import loan
from . import fine
```

Urutan import di sini hanya soal kerapian: relasi memakai nama model sebagai string (`'library.book.category'`), jadi Odoo tetap bisa menyambungkannya selama semua file di-import. Yang wajib berurutan adalah `_inherit` ke model buatan sendiri: model induknya harus sudah ter-load.

---

## Model 1: Book Category (Parent-Child / Recursive)

```python
# models/book_category.py
from odoo import models, fields, api
from odoo.exceptions import ValidationError

class BookCategory(models.Model):
    _name = 'library.book.category'
    _description = 'Book Category'
    _parent_name = 'parent_id'
    _parent_store = True
    _order = 'complete_name'

    name = fields.Char(required=True)
    complete_name = fields.Char(
        compute='_compute_complete_name',
        recursive=True,
        store=True,
    )
    parent_id = fields.Many2one(
        'library.book.category',
        string='Parent Category',
        index=True,
        ondelete='cascade',
    )
    parent_path = fields.Char(index=True, unaccent=False)
    child_ids = fields.One2many(
        'library.book.category',
        'parent_id',
        string='Child Categories',
    )
    book_count = fields.Integer(compute='_compute_book_count')

    @api.depends('name', 'parent_id.complete_name')
    def _compute_complete_name(self):
        for category in self:
            if category.parent_id:
                category.complete_name = f"{category.parent_id.complete_name} / {category.name}"
            else:
                category.complete_name = category.name

    def _compute_book_count(self):
        for category in self:
            category.book_count = self.env['library.book'].search_count(
                [('category_id', '=', category.id)]
            )

    @api.constrains('parent_id')
    def _check_parent_recursion(self):
        if self._has_cycle():
            raise ValidationError('Error! You cannot create recursive categories.')

    _sql_constraints = [
        ('name_parent_uniq', 'unique(name, parent_id)', 'Category name must be unique within parent!'),
    ]
```

**Konsep:**
- `_parent_store = True` — menyimpan `parent_path` untuk query hierarchy yang cepat
- `recursive=True` pada compute — supaya `complete_name` di-recompute saat parent berubah
- `_has_cycle()` — method bawaan Odoo untuk cek circular reference (return `True` jika ada siklus)
- `_sql_constraints` — constraint level database (sintaks Odoo 18, lihat kotak "Beda di Odoo 19" di akhir bab)
- `book_count` tidak punya `@api.depends` karena non-stored dan dihitung lewat `search_count`

---

## Model 2: Book (Model Utama)

```python
# models/book.py
from odoo import models, fields, api

class LibraryBook(models.Model):
    _name = 'library.book'
    _description = 'Library Book'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'name'

    name = fields.Char(string='Title', required=True, tracking=True)
    isbn = fields.Char(string='ISBN', copy=False)
    author = fields.Char(string='Author')
    publisher = fields.Char(string='Publisher')
    date_published = fields.Date(string='Date Published')
    cover_image = fields.Image(string='Cover', max_width=256, max_height=256)
    description = fields.Html(string='Description')
    page_count = fields.Integer(string='Pages')
    active = fields.Boolean(default=True)

    # Relasi
    category_id = fields.Many2one(
        'library.book.category',
        string='Category',
        required=True,
        tracking=True,
    )
    tag_ids = fields.Many2many(
        'library.book.tag',
        'library_book_tag_rel',
        'book_id', 'tag_id',
        string='Tags',
    )
    copy_ids = fields.One2many(
        'library.book.copy',
        'book_id',
        string='Copies',
    )

    # Computed fields
    total_copies = fields.Integer(
        compute='_compute_copy_stats',
        store=True,
        string='Total Copies',
    )
    available_copies = fields.Integer(
        compute='_compute_copy_stats',
        store=True,
        string='Available Copies',
    )

    @api.depends('copy_ids', 'copy_ids.state')
    def _compute_copy_stats(self):
        for book in self:
            book.total_copies = len(book.copy_ids)
            book.available_copies = len(book.copy_ids.filtered(
                lambda c: c.state == 'available'
            ))

    _sql_constraints = [
        ('isbn_uniq', 'unique(isbn)', 'ISBN must be unique!'),
    ]

    @api.depends('name', 'author')
    def _compute_display_name(self):
        for book in self:
            if book.author:
                book.display_name = f"{book.name} ({book.author})"
            else:
                book.display_name = book.name


class LibraryBookTag(models.Model):
    _name = 'library.book.tag'
    _description = 'Book Tag'
    _order = 'name'

    name = fields.Char(required=True)
    color = fields.Integer(string='Color Index')

    _sql_constraints = [
        ('name_uniq', 'unique(name)', 'Tag name must be unique!'),
    ]
```

**Konsep:**
- `copy=False` pada `isbn` — field ini tidak ter-copy saat user duplicate record
- `fields.Image` — otomatis resize gambar sesuai `max_width`/`max_height`
- `_compute_display_name` — pengganti `name_get()` (deprecated sejak Odoo 17); isi `display_name`, jangan lupa `@api.depends`
- `store=True` pada computed field — disimpan di database, di-update otomatis saat dependency berubah
- `filtered(lambda)` — cara Odoo filter recordset

---

## Model 3: Book Copy (Detail per Salinan Fisik)

```python
# models/book_copy.py
from odoo import models, fields, api

class BookCopy(models.Model):
    _name = 'library.book.copy'
    _description = 'Physical Book Copy'
    _rec_name = 'barcode'

    barcode = fields.Char(string='Barcode', required=True, copy=False)
    book_id = fields.Many2one(
        'library.book',
        string='Book',
        required=True,
        ondelete='cascade',
    )
    state = fields.Selection([
        ('available', 'Available'),
        ('borrowed', 'Borrowed'),
        ('maintenance', 'Maintenance'),
        ('lost', 'Lost'),
    ], default='available', required=True)
    location = fields.Char(string='Shelf Location')
    condition = fields.Selection([
        ('new', 'New'),
        ('good', 'Good'),
        ('fair', 'Fair'),
        ('poor', 'Poor'),
    ], default='good')
    acquisition_date = fields.Date(string='Acquisition Date', default=fields.Date.today)
    notes = fields.Text(string='Notes')

    # Related fields (shortcut ke parent)
    book_title = fields.Char(related='book_id.name', string='Title', store=True)
    book_author = fields.Char(related='book_id.author', string='Author')
    category_id = fields.Many2one(related='book_id.category_id', store=True)

    _sql_constraints = [
        ('barcode_uniq', 'unique(barcode)', 'Barcode must be unique!'),
    ]
```

**Konsep:**
- `_rec_name = 'barcode'` — saat direferensi di Many2one, tampilkan barcode bukan `name`
- `ondelete='cascade'` — hapus copy jika book dihapus
- `related` field — shortcut untuk akses field dari relasi, `store=True` menyimpan di DB agar bisa di-search/group
- Model ini tidak mewarisi `mail.thread`, jadi `tracking=True` tidak dipakai di sini (tracking hanya berfungsi di model dengan chatter)

---

## Model 4: Member (Delegation Inheritance dari res.partner)

```python
# models/member.py
from odoo import models, fields, api
from dateutil.relativedelta import relativedelta

class LibraryMember(models.Model):
    _name = 'library.member'
    _inherits = {'res.partner': 'partner_id'}
    _description = 'Library Member'
    _inherit = ['mail.thread']

    partner_id = fields.Many2one(
        'res.partner',
        required=True,
        ondelete='cascade',
    )
    member_number = fields.Char(
        string='Member No.',
        readonly=True,
        copy=False,
        default='New',
    )
    membership_type = fields.Selection([
        ('student', 'Student'),
        ('regular', 'Regular'),
        ('premium', 'Premium'),
    ], default='regular', required=True, tracking=True)
    join_date = fields.Date(string='Join Date', default=fields.Date.today)
    expiry_date = fields.Date(string='Expiry Date')
    max_books = fields.Integer(
        compute='_compute_max_books',
        string='Max Books Allowed',
    )
    loan_ids = fields.One2many('library.loan', 'member_id', string='Loans')
    active_loan_count = fields.Integer(compute='_compute_active_loan_count')
    state = fields.Selection([
        ('active', 'Active'),
        ('expired', 'Expired'),
        ('suspended', 'Suspended'),
    ], default='active', tracking=True)

    @api.depends('membership_type')
    def _compute_max_books(self):
        limits = {'student': 3, 'regular': 5, 'premium': 10}
        for member in self:
            member.max_books = limits.get(member.membership_type, 5)

    @api.depends('loan_ids.state')
    def _compute_active_loan_count(self):
        for member in self:
            member.active_loan_count = len(
                member.loan_ids.filtered(lambda l: l.state == 'active')
            )

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('member_number', 'New') == 'New':
                vals['member_number'] = self.env['ir.sequence'].next_by_code('library.member')
            if not vals.get('expiry_date'):
                join = fields.Date.to_date(vals.get('join_date')) or fields.Date.today()
                vals['expiry_date'] = join + relativedelta(years=1)
        return super().create(vals_list)
```

**Konsep:**
- `_inherits` — field `name`, `email`, `phone` dari `res.partner` langsung bisa dipakai; saat member dibuat, Odoo otomatis membuat record `res.partner`-nya (jika `partner_id` tidak diisi)
- `@api.model_create_multi` — terima list of vals untuk batch create
- `ir.sequence` — auto-generate nomor member (`MBR/0001`, `MBR/0002`, ...)
- `expiry_date` dihitung di `create`; jika `join_date` tidak dikirim, dipakai tanggal hari ini (sama dengan default `join_date`)
- `relativedelta` — menghitung tanggal (join + 1 tahun)

---

## Model 5: Loan / Peminjaman (Header-Line Pattern)

```python
# models/loan.py
from odoo import models, fields, api
from odoo.exceptions import UserError, ValidationError
from dateutil.relativedelta import relativedelta

class LibraryLoan(models.Model):
    _name = 'library.loan'
    _description = 'Book Loan'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'loan_date desc'

    name = fields.Char(
        string='Loan Reference',
        readonly=True,
        copy=False,
        default='New',
    )
    member_id = fields.Many2one(
        'library.member',
        string='Member',
        required=True,
        tracking=True,
    )
    loan_date = fields.Date(
        string='Loan Date',
        default=fields.Date.today,
        required=True,
    )
    due_date = fields.Date(
        string='Due Date',
        required=True,
    )
    return_date = fields.Date(string='Return Date')
    state = fields.Selection([
        ('draft', 'Draft'),
        ('active', 'Active'),
        ('returned', 'Returned'),
        ('cancel', 'Cancelled'),
    ], default='draft', required=True, tracking=True)
    notes = fields.Text(string='Notes')

    # Header-Line pattern: loan punya banyak line
    line_ids = fields.One2many(
        'library.loan.line',
        'loan_id',
        string='Loan Lines',
    )

    # Computed summary dari lines
    total_books = fields.Integer(
        compute='_compute_totals',
        store=True,
        string='Total Books',
    )
    # Tidak di-store: hasilnya bergantung pada tanggal hari ini, jadi nilai
    # yang tersimpan di database akan basi besok. Untuk filter, pakai domain
    # pada state + due_date (lihat search view).
    is_overdue = fields.Boolean(compute='_compute_is_overdue')

    # Related fields
    member_name = fields.Char(related='member_id.name', store=True)
    membership_type = fields.Selection(related='member_id.membership_type')

    @api.depends('line_ids')
    def _compute_totals(self):
        for loan in self:
            loan.total_books = len(loan.line_ids)

    @api.depends('due_date', 'state')
    def _compute_is_overdue(self):
        today = fields.Date.today()
        for loan in self:
            loan.is_overdue = bool(
                loan.state == 'active'
                and loan.due_date
                and loan.due_date < today
            )

    @api.onchange('member_id', 'loan_date')
    def _onchange_default_due_date(self):
        # Default masa pinjam 14 hari sejak tanggal pinjam
        if self.member_id and self.loan_date:
            self.due_date = self.loan_date + relativedelta(days=14)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = self.env['ir.sequence'].next_by_code('library.loan')
        return super().create(vals_list)

    def action_confirm(self):
        for loan in self:
            if not loan.line_ids:
                raise UserError('Tambahkan minimal 1 buku untuk dipinjam!')
            if loan.member_id.state != 'active':
                raise UserError(f'Keanggotaan {loan.member_id.name} tidak aktif!')
            # Batas dihitung per buku, bukan per transaksi
            borrowed = self.env['library.loan.line'].search_count([
                ('loan_id.member_id', '=', loan.member_id.id),
                ('loan_id.state', '=', 'active'),
            ])
            if borrowed + len(loan.line_ids) > loan.member_id.max_books:
                raise UserError(
                    f'{loan.member_id.name} sudah mencapai batas maksimal '
                    f'peminjaman ({loan.member_id.max_books} buku)!'
                )
            # Pastikan semua copy masih tersedia, lalu update state-nya
            for line in loan.line_ids:
                if line.copy_id.state != 'available':
                    raise UserError(f'Copy {line.copy_id.barcode} tidak tersedia!')
                line.copy_id.state = 'borrowed'
        self.write({'state': 'active'})

    def action_return(self):
        for loan in self:
            if loan.state != 'active':
                raise UserError('Hanya peminjaman aktif yang bisa dikembalikan!')
            for line in loan.line_ids:
                line.copy_id.state = 'available'
            loan.return_date = fields.Date.today()
            # Cek keterlambatan
            if loan.due_date < fields.Date.today():
                loan._create_fine()
        self.write({'state': 'returned'})

    def action_cancel(self):
        for loan in self:
            for line in loan.line_ids:
                if line.copy_id.state == 'borrowed':
                    line.copy_id.state = 'available'
        self.write({'state': 'cancel'})

    def _create_fine(self):
        self.ensure_one()
        days_late = (fields.Date.today() - self.due_date).days
        amount = days_late * 1000  # Rp 1.000 per hari
        self.env['library.fine'].create({
            'loan_id': self.id,
            'member_id': self.member_id.id,
            'amount': amount,
            'days_late': days_late,
        })

    @api.constrains('due_date', 'loan_date')
    def _check_dates(self):
        for loan in self:
            if loan.due_date and loan.loan_date and loan.due_date < loan.loan_date:
                raise ValidationError('Due date harus setelah loan date!')


class LibraryLoanLine(models.Model):
    _name = 'library.loan.line'
    _description = 'Loan Line'

    loan_id = fields.Many2one(
        'library.loan',
        string='Loan',
        required=True,
        ondelete='cascade',
    )
    copy_id = fields.Many2one(
        'library.book.copy',
        string='Book Copy',
        required=True,
        domain=[('state', '=', 'available')],
    )
    # Related fields dari copy untuk tampilan di list
    book_id = fields.Many2one(related='copy_id.book_id', store=True)
    book_title = fields.Char(related='copy_id.book_title')
    barcode = fields.Char(related='copy_id.barcode')
    notes = fields.Char(string='Notes')

    _sql_constraints = [
        ('copy_loan_uniq', 'unique(loan_id, copy_id)',
         'Cannot add the same book copy twice in one loan!'),
    ]
```

**Konsep Header-Line Pattern:**
- **Header** (`library.loan`) — data utama peminjaman (siapa, kapan, status)
- **Line** (`library.loan.line`) — detail per buku yang dipinjam
- Header punya `One2many` ke Line, Line punya `Many2one` ke Header
- Pattern ini sama dengan `sale.order` → `sale.order.line` di Odoo
- `domain=[('state', '=', 'available')]` pada `copy_id` hanya membatasi pilihan di UI; validasi sebenarnya ada di `action_confirm`
- `is_overdue` sengaja tidak di-store karena bergantung pada tanggal hari ini; filter "Overdue" memakai domain `state` + `due_date` di search view

---

## Model 6: Fine / Denda

```python
# models/fine.py
from odoo import models, fields, api

class LibraryFine(models.Model):
    _name = 'library.fine'
    _description = 'Library Fine'
    _order = 'create_date desc'

    loan_id = fields.Many2one('library.loan', string='Loan', required=True)
    member_id = fields.Many2one('library.member', string='Member', required=True)
    amount = fields.Float(string='Fine Amount', required=True)
    days_late = fields.Integer(string='Days Late')
    state = fields.Selection([
        ('unpaid', 'Unpaid'),
        ('paid', 'Paid'),
        ('waived', 'Waived'),
    ], default='unpaid')
    payment_date = fields.Date(string='Payment Date')
    notes = fields.Text(string='Notes')

    # Related
    member_name = fields.Char(related='member_id.name', store=True)
    loan_name = fields.Char(related='loan_id.name')

    def action_pay(self):
        self.write({
            'state': 'paid',
            'payment_date': fields.Date.today(),
        })

    def action_waive(self):
        self.write({'state': 'waived'})
```

---

## Sequence Data

```xml
<!-- data/sequence.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="seq_library_member" model="ir.sequence">
            <field name="name">Library Member</field>
            <field name="code">library.member</field>
            <field name="prefix">MBR/</field>
            <field name="padding">4</field>
        </record>

        <record id="seq_library_loan" model="ir.sequence">
            <field name="name">Library Loan</field>
            <field name="code">library.loan</field>
            <field name="prefix">LOAN/%(year)s/</field>
            <field name="padding">5</field>
        </record>
    </data>
</odoo>
```

Hasil sequence: `MBR/0001`, `MBR/0002`, `LOAN/2026/00001`, dst.

---

## Category Seed Data

```xml
<!-- data/category_data.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="category_fiction" model="library.book.category">
            <field name="name">Fiction</field>
        </record>
        <record id="category_scifi" model="library.book.category">
            <field name="name">Science Fiction</field>
            <field name="parent_id" ref="category_fiction"/>
        </record>
        <record id="category_fantasy" model="library.book.category">
            <field name="name">Fantasy</field>
            <field name="parent_id" ref="category_fiction"/>
        </record>
        <record id="category_nonfiction" model="library.book.category">
            <field name="name">Non-Fiction</field>
        </record>
        <record id="category_science" model="library.book.category">
            <field name="name">Science</field>
            <field name="parent_id" ref="category_nonfiction"/>
        </record>
        <record id="category_history" model="library.book.category">
            <field name="name">History</field>
            <field name="parent_id" ref="category_nonfiction"/>
        </record>
    </data>
</odoo>
```

---

## Security

### security/groups.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data>
        <!-- Kategori untuk mengelompokkan groups -->
        <record id="module_category_library" model="ir.module.category">
            <field name="name">Library</field>
            <field name="sequence">50</field>
        </record>

        <record id="group_library_user" model="res.groups">
            <field name="name">User</field>
            <field name="category_id" ref="module_category_library"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
        </record>

        <record id="group_library_manager" model="res.groups">
            <field name="name">Manager</field>
            <field name="category_id" ref="module_category_library"/>
            <field name="implied_ids" eval="[(4, ref('group_library_user'))]"/>
            <!-- Admin otomatis jadi Library Manager, kalau tidak menu Library tidak muncul -->
            <field name="users" eval="[(4, ref('base.user_root')), (4, ref('base.user_admin'))]"/>
        </record>
    </data>
</odoo>
```

### security/ir.model.access.csv

```
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_book_category_user,library.book.category user,model_library_book_category,group_library_user,1,0,0,0
access_book_category_manager,library.book.category manager,model_library_book_category,group_library_manager,1,1,1,1
access_book_user,library.book user,model_library_book,group_library_user,1,0,0,0
access_book_manager,library.book manager,model_library_book,group_library_manager,1,1,1,1
access_book_tag_user,library.book.tag user,model_library_book_tag,group_library_user,1,0,0,0
access_book_tag_manager,library.book.tag manager,model_library_book_tag,group_library_manager,1,1,1,1
access_book_copy_user,library.book.copy user,model_library_book_copy,group_library_user,1,1,0,0
access_book_copy_manager,library.book.copy manager,model_library_book_copy,group_library_manager,1,1,1,1
access_member_user,library.member user,model_library_member,group_library_user,1,1,1,0
access_member_manager,library.member manager,model_library_member,group_library_manager,1,1,1,1
access_loan_user,library.loan user,model_library_loan,group_library_user,1,1,1,0
access_loan_manager,library.loan manager,model_library_loan,group_library_manager,1,1,1,1
access_loan_line_user,library.loan.line user,model_library_loan_line,group_library_user,1,1,1,1
access_loan_line_manager,library.loan.line manager,model_library_loan_line,group_library_manager,1,1,1,1
access_fine_user,library.fine user,model_library_fine,group_library_user,1,1,1,0
access_fine_manager,library.fine manager,model_library_fine,group_library_manager,1,1,1,1
```

**Penting:** Setiap model yang punya `_name` harus punya access rights. Jika tidak, user non-admin tidak bisa mengakses dan akan error "Access Denied".

Nama `model_id:id` dibuat dari `_name` dengan mengganti `.` menjadi `_` dan menambah prefix `model_`. Contoh: `library.book.copy` → `model_library_book_copy`.

Kenapa hak akses User tidak sekadar read-only? Karena method di Bab ini dijalankan atas nama user yang sedang login: `action_confirm` dan `action_return` menulis `state` di `library.book.copy` (butuh write), dan `_create_fine` membuat record `library.fine` (butuh create). Jika dibiarkan read-only, staf perpustakaan kena `AccessError` saat memproses peminjaman. Hak akses harus selalu dicocokkan dengan apa yang dikerjakan method-nya.

---

## Views & Menus

Setiap model butuh minimal satu action supaya bisa dipasang di menu. Kita mulai dari view paling kompleks (loan, header-line), lalu view model lain yang lebih sederhana. Ingat: `<list>` menggantikan `<tree>`, `<chatter/>` menggantikan blok `oe_chatter` manual, dan `view_mode` memakai `list,form`.

### views/loan_views.xml (Contoh Header-Line View)

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Form View: Header-Line Pattern -->
    <record id="view_library_loan_form" model="ir.ui.view">
        <field name="name">library.loan.form</field>
        <field name="model">library.loan</field>
        <field name="arch" type="xml">
            <form string="Book Loan">
                <header>
                    <button name="action_confirm"
                            string="Confirm"
                            type="object"
                            class="btn-primary"
                            invisible="state != 'draft'"/>
                    <button name="action_return"
                            string="Return Books"
                            type="object"
                            class="btn-primary"
                            invisible="state != 'active'"/>
                    <button name="action_cancel"
                            string="Cancel"
                            type="object"
                            invisible="state in ('returned', 'cancel')"/>
                    <field name="state" widget="statusbar"
                           statusbar_visible="draft,active,returned"/>
                </header>
                <sheet>
                    <div class="oe_title">
                        <h1>
                            <field name="name" readonly="1"/>
                        </h1>
                    </div>
                    <group>
                        <group string="Loan Info">
                            <field name="member_id"
                                   readonly="state != 'draft'"/>
                            <field name="membership_type"/>
                            <field name="loan_date"
                                   readonly="state != 'draft'"/>
                            <field name="due_date"/>
                        </group>
                        <group string="Return Info">
                            <field name="return_date"/>
                            <field name="total_books"/>
                            <field name="is_overdue"
                                   invisible="not is_overdue"/>
                        </group>
                    </group>

                    <!-- ONE2MANY LINES: inti dari header-line pattern -->
                    <notebook>
                        <page string="Books" name="books">
                            <field name="line_ids"
                                   readonly="state != 'draft'">
                                <list editable="bottom">
                                    <field name="copy_id"/>
                                    <field name="book_title"/>
                                    <field name="barcode"/>
                                    <field name="notes"/>
                                </list>
                            </field>
                        </page>
                        <page string="Notes" name="notes">
                            <field name="notes" placeholder="Internal notes..."/>
                        </page>
                    </notebook>
                </sheet>
                <chatter/>
            </form>
        </field>
    </record>

    <!-- List View -->
    <record id="view_library_loan_list" model="ir.ui.view">
        <field name="name">library.loan.list</field>
        <field name="model">library.loan</field>
        <field name="arch" type="xml">
            <list decoration-danger="is_overdue"
                  decoration-muted="state == 'cancel'">
                <field name="name"/>
                <field name="member_name"/>
                <field name="loan_date"/>
                <field name="due_date"/>
                <field name="return_date"/>
                <field name="total_books"/>
                <field name="state" widget="badge"
                       decoration-info="state == 'draft'"
                       decoration-success="state == 'returned'"
                       decoration-warning="state == 'active'"/>
                <field name="is_overdue" column_invisible="1"/>
            </list>
        </field>
    </record>

    <!-- Search View -->
    <record id="view_library_loan_search" model="ir.ui.view">
        <field name="name">library.loan.search</field>
        <field name="model">library.loan</field>
        <field name="arch" type="xml">
            <search>
                <field name="name"/>
                <field name="member_id"/>
                <separator/>
                <filter name="active_loans" string="Active"
                        domain="[('state', '=', 'active')]"/>
                <filter name="overdue" string="Overdue"
                        domain="[('state', '=', 'active'),
                                 ('due_date', '&lt;', context_today().strftime('%Y-%m-%d'))]"/>
                <filter name="returned" string="Returned"
                        domain="[('state', '=', 'returned')]"/>
                <separator/>
                <group expand="0" string="Group By">
                    <filter name="group_member" string="Member"
                            context="{'group_by': 'member_id'}"/>
                    <filter name="group_state" string="State"
                            context="{'group_by': 'state'}"/>
                    <filter name="group_month" string="Loan Month"
                            context="{'group_by': 'loan_date:month'}"/>
                </group>
            </search>
        </field>
    </record>

    <!-- Action -->
    <record id="action_library_loan" model="ir.actions.act_window">
        <field name="name">Loans</field>
        <field name="res_model">library.loan</field>
        <field name="view_mode">list,form</field>
        <field name="search_view_id" ref="view_library_loan_search"/>
        <field name="context">{'search_default_active_loans': 1}</field>
        <field name="help" type="html">
            <p class="o_view_nocontent_smiling_face">
                Create your first loan!
            </p>
        </field>
    </record>
</odoo>
```

### views/book_views.xml (Book dan Tag)

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_library_book_form" model="ir.ui.view">
        <field name="name">library.book.form</field>
        <field name="model">library.book</field>
        <field name="arch" type="xml">
            <form string="Book">
                <sheet>
                    <field name="cover_image" widget="image" class="oe_avatar"/>
                    <div class="oe_title">
                        <h1><field name="name" placeholder="Book title"/></h1>
                    </div>
                    <group>
                        <group>
                            <field name="author"/>
                            <field name="publisher"/>
                            <field name="isbn"/>
                            <field name="date_published"/>
                        </group>
                        <group>
                            <field name="category_id"/>
                            <field name="tag_ids" widget="many2many_tags"
                                   options="{'color_field': 'color'}"/>
                            <field name="page_count"/>
                            <field name="active"/>
                        </group>
                    </group>
                    <notebook>
                        <page string="Copies" name="copies">
                            <field name="copy_ids">
                                <list editable="bottom">
                                    <field name="barcode"/>
                                    <field name="state"/>
                                    <field name="location"/>
                                    <field name="condition"/>
                                </list>
                            </field>
                        </page>
                        <page string="Description" name="description">
                            <field name="description"/>
                        </page>
                    </notebook>
                </sheet>
                <chatter/>
            </form>
        </field>
    </record>

    <record id="view_library_book_list" model="ir.ui.view">
        <field name="name">library.book.list</field>
        <field name="model">library.book</field>
        <field name="arch" type="xml">
            <list>
                <field name="name"/>
                <field name="author"/>
                <field name="category_id"/>
                <field name="total_copies"/>
                <field name="available_copies"/>
            </list>
        </field>
    </record>

    <record id="view_library_book_search" model="ir.ui.view">
        <field name="name">library.book.search</field>
        <field name="model">library.book</field>
        <field name="arch" type="xml">
            <search>
                <field name="name"/>
                <field name="author"/>
                <field name="isbn"/>
                <filter name="available" string="Available"
                        domain="[('available_copies', '&gt;', 0)]"/>
                <group string="Group By">
                    <filter name="group_category" string="Category"
                            context="{'group_by': 'category_id'}"/>
                </group>
            </search>
        </field>
    </record>

    <record id="action_library_book" model="ir.actions.act_window">
        <field name="name">Books</field>
        <field name="res_model">library.book</field>
        <field name="view_mode">list,form</field>
    </record>

    <!-- Tag: model kecil, cukup list editable -->
    <record id="view_library_book_tag_list" model="ir.ui.view">
        <field name="name">library.book.tag.list</field>
        <field name="model">library.book.tag</field>
        <field name="arch" type="xml">
            <list editable="bottom">
                <field name="name"/>
                <field name="color" widget="color_picker"/>
            </list>
        </field>
    </record>

    <record id="action_library_book_tag" model="ir.actions.act_window">
        <field name="name">Tags</field>
        <field name="res_model">library.book.tag</field>
        <field name="view_mode">list</field>
    </record>
</odoo>
```

### views/book_category_views.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_library_book_category_form" model="ir.ui.view">
        <field name="name">library.book.category.form</field>
        <field name="model">library.book.category</field>
        <field name="arch" type="xml">
            <form string="Category">
                <sheet>
                    <group>
                        <field name="name"/>
                        <field name="parent_id"/>
                        <field name="book_count"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="view_library_book_category_list" model="ir.ui.view">
        <field name="name">library.book.category.list</field>
        <field name="model">library.book.category</field>
        <field name="arch" type="xml">
            <list>
                <field name="complete_name"/>
                <field name="book_count"/>
            </list>
        </field>
    </record>

    <record id="action_library_book_category" model="ir.actions.act_window">
        <field name="name">Categories</field>
        <field name="res_model">library.book.category</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
```

### views/book_copy_views.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_library_book_copy_form" model="ir.ui.view">
        <field name="name">library.book.copy.form</field>
        <field name="model">library.book.copy</field>
        <field name="arch" type="xml">
            <form string="Book Copy">
                <header>
                    <field name="state" widget="statusbar"
                           statusbar_visible="available,borrowed,maintenance"/>
                </header>
                <sheet>
                    <group>
                        <group>
                            <field name="barcode"/>
                            <field name="book_id"/>
                            <field name="location"/>
                        </group>
                        <group>
                            <field name="condition"/>
                            <field name="acquisition_date"/>
                        </group>
                    </group>
                    <field name="notes" placeholder="Notes..."/>
                </sheet>
            </form>
        </field>
    </record>

    <record id="view_library_book_copy_list" model="ir.ui.view">
        <field name="name">library.book.copy.list</field>
        <field name="model">library.book.copy</field>
        <field name="arch" type="xml">
            <list decoration-muted="state == 'lost'"
                  decoration-warning="state == 'maintenance'">
                <field name="barcode"/>
                <field name="book_title"/>
                <field name="category_id"/>
                <field name="location"/>
                <field name="condition"/>
                <field name="state" widget="badge"/>
            </list>
        </field>
    </record>

    <record id="action_library_book_copy" model="ir.actions.act_window">
        <field name="name">Book Copies</field>
        <field name="res_model">library.book.copy</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
```

### views/member_views.xml

Karena `_inherits`, field `name`, `email`, dan `phone` milik `res.partner` bisa langsung dipakai di view member.

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_library_member_form" model="ir.ui.view">
        <field name="name">library.member.form</field>
        <field name="model">library.member</field>
        <field name="arch" type="xml">
            <form string="Member">
                <header>
                    <field name="state" widget="statusbar"
                           statusbar_visible="active,suspended,expired"/>
                </header>
                <sheet>
                    <div class="oe_title">
                        <h1><field name="name" placeholder="Member name"/></h1>
                        <h3><field name="member_number"/></h3>
                    </div>
                    <group>
                        <group>
                            <field name="email"/>
                            <field name="phone"/>
                        </group>
                        <group>
                            <field name="membership_type"/>
                            <field name="max_books"/>
                            <field name="join_date"/>
                            <field name="expiry_date"/>
                            <field name="active_loan_count"/>
                        </group>
                    </group>
                    <notebook>
                        <page string="Loans" name="loans">
                            <field name="loan_ids" readonly="1">
                                <list>
                                    <field name="name"/>
                                    <field name="loan_date"/>
                                    <field name="due_date"/>
                                    <field name="state"/>
                                </list>
                            </field>
                        </page>
                    </notebook>
                </sheet>
                <chatter/>
            </form>
        </field>
    </record>

    <record id="view_library_member_list" model="ir.ui.view">
        <field name="name">library.member.list</field>
        <field name="model">library.member</field>
        <field name="arch" type="xml">
            <list>
                <field name="member_number"/>
                <field name="name"/>
                <field name="membership_type"/>
                <field name="expiry_date"/>
                <field name="state"/>
            </list>
        </field>
    </record>

    <record id="action_library_member" model="ir.actions.act_window">
        <field name="name">Members</field>
        <field name="res_model">library.member</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
```

### views/fine_views.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_library_fine_form" model="ir.ui.view">
        <field name="name">library.fine.form</field>
        <field name="model">library.fine</field>
        <field name="arch" type="xml">
            <form string="Fine">
                <header>
                    <button name="action_pay" string="Mark as Paid" type="object"
                            class="btn-primary" invisible="state != 'unpaid'"/>
                    <button name="action_waive" string="Waive" type="object"
                            invisible="state != 'unpaid'"/>
                    <field name="state" widget="statusbar"/>
                </header>
                <sheet>
                    <group>
                        <group>
                            <field name="loan_id"/>
                            <field name="member_id"/>
                        </group>
                        <group>
                            <field name="days_late"/>
                            <field name="amount"/>
                            <field name="payment_date" invisible="state != 'paid'"/>
                        </group>
                    </group>
                    <field name="notes" placeholder="Notes..."/>
                </sheet>
            </form>
        </field>
    </record>

    <record id="view_library_fine_list" model="ir.ui.view">
        <field name="name">library.fine.list</field>
        <field name="model">library.fine</field>
        <field name="arch" type="xml">
            <list decoration-success="state == 'paid'"
                  decoration-muted="state == 'waived'">
                <field name="loan_name"/>
                <field name="member_name"/>
                <field name="days_late"/>
                <field name="amount" sum="Total"/>
                <field name="state" widget="badge"/>
            </list>
        </field>
    </record>

    <record id="action_library_fine" model="ir.actions.act_window">
        <field name="name">Fines</field>
        <field name="res_model">library.fine</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
```

Catatan: file view lain selain `loan_views.xml` hanya contoh minimal, kembangkan sendiri (search view, kanban, dsb.) sesuai kebutuhan.

### views/menu.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Root Menu -->
    <menuitem id="menu_library_root"
              name="Library"
              sequence="50"
              groups="group_library_user"/>

    <!-- Submenu: Operations -->
    <menuitem id="menu_library_operations"
              name="Operations"
              parent="menu_library_root"
              sequence="10"/>

    <menuitem id="menu_library_loan"
              name="Loans"
              parent="menu_library_operations"
              action="action_library_loan"
              sequence="10"/>

    <menuitem id="menu_library_fine"
              name="Fines"
              parent="menu_library_operations"
              action="action_library_fine"
              sequence="20"/>

    <!-- Submenu: Catalog -->
    <menuitem id="menu_library_catalog"
              name="Catalog"
              parent="menu_library_root"
              sequence="20"/>

    <menuitem id="menu_library_book"
              name="Books"
              parent="menu_library_catalog"
              action="action_library_book"
              sequence="10"/>

    <menuitem id="menu_library_book_copy"
              name="Book Copies"
              parent="menu_library_catalog"
              action="action_library_book_copy"
              sequence="20"/>

    <!-- Submenu: Members -->
    <menuitem id="menu_library_member"
              name="Members"
              parent="menu_library_root"
              action="action_library_member"
              sequence="30"/>

    <!-- Submenu: Configuration -->
    <menuitem id="menu_library_config"
              name="Configuration"
              parent="menu_library_root"
              sequence="100"
              groups="group_library_manager"/>

    <menuitem id="menu_library_category"
              name="Categories"
              parent="menu_library_config"
              action="action_library_book_category"
              sequence="10"/>

    <menuitem id="menu_library_tag"
              name="Tags"
              parent="menu_library_config"
              action="action_library_book_tag"
              sequence="20"/>
</odoo>
```

---

## Diagram Relasi Antar Model

Panah dibaca "Many2one ke". Relasi One2many adalah kebalikannya (mis. `book.copy_ids` adalah kebalikan dari `copy.book_id`).

```
library.book.category --parent_id--> library.book.category   (rekursif)
library.book          --category_id--> library.book.category
library.book          <--M2M--> library.book.tag
library.book.copy     --book_id--> library.book              (book.copy_ids = O2M)
library.member        --partner_id--> res.partner            (_inherits)
library.loan          --member_id--> library.member          (member.loan_ids = O2M)
library.loan.line     --loan_id--> library.loan              (loan.line_ids = O2M)
library.loan.line     --copy_id--> library.book.copy
library.fine          --loan_id--> library.loan
library.fine          --member_id--> library.member
```

---

## Uji Manual (Langkah 7)

Setelah semua file siap, install module dan jalankan skenario ini:

1. Install/upgrade: `-u library_management` (lihat Bab 2 untuk cara menjalankan Odoo). Jika ada error XML atau akses, rujuk Bab 18.
2. Buka menu Library, pastikan kategori seed (Fiction, Science Fiction, dst.) muncul.
3. Buat satu buku, tambahkan 2 copy di tab Copies. Cek `Total Copies` = 2 dan `Available Copies` = 2.
4. Buat member baru: `member_number` terisi `MBR/0001`, `expiry_date` = 1 tahun dari `join_date`.
5. Buat loan, pilih member dan satu copy, klik Confirm. State copy berubah ke Borrowed, `Available Copies` di buku turun jadi 1.
6. Ubah `due_date` ke tanggal lampau (lewat form), lalu klik Return Books. Cek apakah record denda terbentuk di menu Fines.
7. Login sebagai user biasa yang hanya punya group Library User: pastikan semua langkah di atas tetap jalan tanpa Access Denied.

---

## Tips untuk Multi-Model Module

1. **Setiap model butuh access rights** — sering lupa untuk model "kecil" seperti tag atau line
2. **Cocokkan hak akses dengan method** — method yang menulis/membuat record di model lain butuh hak tersebut (atau gunakan `sudo()` dengan hati-hati)
3. **`ondelete='cascade'`** — gunakan pada child model agar terhapus otomatis saat parent dihapus
4. **`store=True` pada computed** — gunakan jika perlu search/filter/group by field tersebut, dan hanya jika nilainya tidak bergantung pada tanggal hari ini
5. **`related` field** — shortcut praktis, tapi `store=True` membuat data ter-denormalize (trade-off: cepat search vs. storage ekstra)
6. **Header-Line pattern** — selalu gunakan `editable="bottom"` atau `editable="top"` pada `<list>` di dalam form agar user bisa langsung edit inline
7. **Naming convention**: `modulename.model` untuk `_name`, class CamelCase, file snake_case
8. **Pastikan view dan model konsisten** — setiap field yang dipakai di view harus ada di model, dan setiap action yang dirujuk menu harus didefinisikan

---

> **Beda di Odoo 19:**
> - Di Odoo 19, constraint SQL didokumentasikan dengan `models.Constraint` / `models.UniqueIndex` / `models.Index`; di Odoo 18 tetap pakai `_sql_constraints` seperti di bab ini.
> - Query agregasi: di Odoo 19 hanya `_read_group` yang terdokumentasi (bab ini belum memakainya).
> - `<list>`, `<chatter/>`, dan `invisible="expr"` berlaku sama di Odoo 18 dan 19.

## Ringkasan

- Module multi-model dibangun berurutan: manifest, model, security, data, view, menu, lalu uji manual.
- Urutan `data` di manifest: security, data, views, menu.
- Header-line (`library.loan` dan `library.loan.line`) memakai One2many di header dan Many2one di line, ditampilkan sebagai `<list editable="bottom">` di dalam form.
- `_inherits` membuat `library.member` memakai field `res.partner`; `_parent_store` dan `_has_cycle()` dipakai untuk kategori hierarkis.
- `name_get()` diganti `_compute_display_name`; field computed yang bergantung pada tanggal hari ini sebaiknya tidak di-store.
- Semua model wajib ada di `ir.model.access.csv`, dan hak akses harus cukup untuk apa yang dikerjakan method-nya.

## Latihan

1. **Total denda di member (Bab 4, 5).** Tambahkan field computed `fine_total` di `library.member` (jumlah `amount` denda berstatus `unpaid`) dan tampilkan sebagai smart button di form member yang membuka daftar denda member tersebut.
2. **Wizard perpanjangan (Bab 9).** Buat wizard "Extend Loan" yang menerima jumlah hari tambahan dan memperbarui `due_date` pada loan aktif. Pasang tombolnya di header form loan dan pastikan tombol hanya tampil saat `state == 'active'`.
3. **Cron pengingat jatuh tempo (Bab 7).** Buat `ir.cron` harian yang mencari loan aktif dengan `due_date` kurang dari hari ini dan memposting pesan di chatter loan tersebut (`message_post`).

## Lanjut ke

Bab 11: QWeb Reports. Kamu akan membuat laporan PDF (misalnya kartu anggota atau slip denda) dari model-model yang sudah dibangun di bab ini.
