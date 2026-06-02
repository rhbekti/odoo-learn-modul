# Bab 10: Multi-Model Module (Contoh Lengkap)

Bab ini menunjukkan cara membuat module dengan banyak model yang saling berhubungan, seperti pola header-line, relasi antar-model, dan computed fields lintas model.

## Studi Kasus: Library Management System

Kita akan membuat system perpustakaan lengkap dengan model-model berikut:

```
library.book           → Data buku
library.book.category  → Kategori buku
library.book.copy      → Salinan fisik buku (1 buku bisa punya banyak copy)
library.member         → Anggota perpustakaan
library.loan           → Peminjaman (header)
library.loan.line      → Detail peminjaman (lines)
library.fine           → Denda keterlambatan
```

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
│   ├── book_views.xml
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

**Urutan `data` penting!** Security & data files dulu, baru views. Jika views merujuk group yang belum di-load, akan error.

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

**Urutan import penting** jika ada dependensi antar model (misalnya `book` punya field ke `book_category`, maka `book_category` harus di-import dulu).

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
        if not self._check_recursion():
            raise ValidationError('Error! You cannot create recursive categories.')

    _sql_constraints = [
        ('name_parent_uniq', 'unique(name, parent_id)', 'Category name must be unique within parent!'),
    ]
```

**Konsep:**
- `_parent_store = True` — menyimpan `parent_path` untuk query hierarchy yang cepat
- `recursive=True` pada compute — supaya `complete_name` di-recompute saat parent berubah
- `_check_recursion()` — method bawaan Odoo untuk cek circular reference

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

    def name_get(self):
        result = []
        for book in self:
            name = book.name
            if book.author:
                name = f"{name} ({book.author})"
            result.append((book.id, name))
        return result


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
- `fields.Image` — otomatis resize gambar (built-in di Odoo 18)
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
    ], default='available', required=True, tracking=True)
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

    def _compute_active_loan_count(self):
        for member in self:
            member.active_loan_count = self.env['library.loan'].search_count([
                ('member_id', '=', member.id),
                ('state', '=', 'active'),
            ])

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('member_number', 'New') == 'New':
                vals['member_number'] = self.env['ir.sequence'].next_by_code('library.member')
            if not vals.get('expiry_date') and vals.get('join_date'):
                join = fields.Date.from_string(vals['join_date'])
                vals['expiry_date'] = join + relativedelta(years=1)
        return super().create(vals_list)
```

**Konsep:**
- `_inherits` — field `name`, `email`, `phone` dari `res.partner` langsung bisa dipakai
- `@api.model_create_multi` — Odoo 18 style: terima list of vals untuk batch create
- `ir.sequence` — auto-generate nomor member (M0001, M0002, ...)
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
        ('overdue', 'Overdue'),
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
    is_overdue = fields.Boolean(compute='_compute_is_overdue', store=True)

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
            loan.is_overdue = (
                loan.state == 'active'
                and loan.due_date
                and loan.due_date < today
            )

    @api.onchange('member_id')
    def _onchange_member_id(self):
        if self.member_id:
            self.due_date = fields.Date.today() + relativedelta(days=14)

    @api.onchange('loan_date')
    def _onchange_loan_date(self):
        if self.loan_date:
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
            if loan.member_id.active_loan_count >= loan.member_id.max_books:
                raise UserError(
                    f'{loan.member_id.name} sudah mencapai batas maksimal '
                    f'peminjaman ({loan.member_id.max_books} buku)!'
                )
            # Update state copy buku
            for line in loan.line_ids:
                line.copy_id.state = 'borrowed'
        self.write({'state': 'active'})

    def action_return(self):
        for loan in self:
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
    # Related fields dari copy untuk tampilan di tree
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
access_book_copy_user,library.book.copy user,model_library_book_copy,group_library_user,1,0,0,0
access_book_copy_manager,library.book.copy manager,model_library_book_copy,group_library_manager,1,1,1,1
access_member_user,library.member user,model_library_member,group_library_user,1,1,1,0
access_member_manager,library.member manager,model_library_member,group_library_manager,1,1,1,1
access_loan_user,library.loan user,model_library_loan,group_library_user,1,1,1,0
access_loan_manager,library.loan manager,model_library_loan,group_library_manager,1,1,1,1
access_loan_line_user,library.loan.line user,model_library_loan_line,group_library_user,1,1,1,1
access_loan_line_manager,library.loan.line manager,model_library_loan_line,group_library_manager,1,1,1,1
access_fine_user,library.fine user,model_library_fine,group_library_user,1,0,0,0
access_fine_manager,library.fine manager,model_library_fine,group_library_manager,1,1,1,1
```

**Penting:** Setiap model yang punya `_name` harus punya access rights. Jika tidak, user non-admin tidak bisa mengakses dan akan error "Access Denied".

Nama `model_id:id` dibuat dari `_name` dengan mengganti `.` menjadi `_` dan menambah prefix `model_`. Contoh: `library.book.copy` → `model_library_book_copy`.

---

## Views & Menus

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
                                <tree editable="bottom">
                                    <field name="copy_id"/>
                                    <field name="book_title"/>
                                    <field name="barcode"/>
                                    <field name="notes"/>
                                </tree>
                            </field>
                        </page>
                        <page string="Notes" name="notes">
                            <field name="notes" placeholder="Internal notes..."/>
                        </page>
                    </notebook>
                </sheet>
                <div class="oe_chatter">
                    <field name="message_follower_ids"/>
                    <field name="activity_ids"/>
                    <field name="message_ids"/>
                </div>
            </form>
        </field>
    </record>

    <!-- Tree View -->
    <record id="view_library_loan_tree" model="ir.ui.view">
        <field name="name">library.loan.tree</field>
        <field name="model">library.loan</field>
        <field name="arch" type="xml">
            <tree decoration-danger="is_overdue"
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
                       decoration-danger="state == 'overdue'"
                       decoration-warning="state == 'active'"/>
                <field name="is_overdue" column_invisible="1"/>
            </tree>
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
                        domain="[('is_overdue', '=', True)]"/>
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
        <field name="view_mode">tree,form,kanban</field>
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

```
┌─────────────────┐       ┌──────────────────┐
│ book.category    │◄──────│ library.book     │
│                  │  M2O  │                  │
│ - name           │       │ - name           │
│ - parent_id ──┐  │       │ - isbn           │
│ - child_ids   │  │       │ - author         │
│               └──┤       │ - category_id    │
│   (recursive)    │       │ - tag_ids ───────┼──── M2M ──── library.book.tag
└─────────────────┘       │ - copy_ids       │
                          └──────┬───────────┘
                                 │ O2M
                          ┌──────┴───────────┐
                          │ library.book.copy │
                          │                  │
                          │ - barcode        │
                          │ - book_id        │
                          │ - state          │
                          └──────┬───────────┘
                                 │ M2O (via loan.line)
┌─────────────────┐       ┌──────┴───────────┐       ┌─────────────────┐
│ library.member   │──M2O──│ library.loan     │──O2M──│ library.fine    │
│                  │       │                  │       │                 │
│ - partner_id ────┼─┐     │ - name           │       │ - amount        │
│ - member_number  │ │     │ - member_id      │       │ - days_late     │
│ - membership_type│ │     │ - loan_date      │       │ - state         │
└─────────────────┘ │     │ - line_ids       │       └─────────────────┘
                     │     └──────┬───────────┘
              _inherits│          │ O2M
                     │     ┌──────┴───────────┐
              ┌──────┴──┐  │ library.loan.line │
              │res.partner│ │                  │
              │          │  │ - loan_id        │
              │ - name   │  │ - copy_id        │
              │ - email  │  │ - notes          │
              └──────────┘  └──────────────────┘
```

---

## Tips untuk Multi-Model Module

1. **Urutan import di `__init__.py`** — model yang direferensikan oleh model lain harus di-import duluan
2. **Setiap model butuh access rights** — sering lupa untuk model "kecil" seperti tag atau line
3. **`ondelete='cascade'`** — gunakan pada child model agar terhapus otomatis saat parent dihapus
4. **`store=True` pada computed** — gunakan jika perlu search/filter/group by field tersebut
5. **`related` field** — shortcut praktis, tapi `store=True` membuat data ter-denormalize (trade-off: cepat search vs. storage ekstra)
6. **Header-Line pattern** — selalu gunakan `editable="bottom"` atau `editable="top"` pada tree di dalam form agar user bisa langsung edit inline
7. **Naming convention**: `modulename.model` untuk `_name`, class CamelCase, file snake_case
