# Bab 11: Data Files, Sequences & Automated Actions

## Data Files (XML & CSV)

Data files digunakan untuk memasukkan data ke database saat module di-install.

### noupdate: Kapan Data Bisa Di-overwrite

```xml
<!-- noupdate="0" (default): data AKAN di-update setiap upgrade module -->
<data noupdate="0">
    <record id="view_something" model="ir.ui.view">
        <!-- Views selalu noupdate=0 agar perubahan terdeteksi saat upgrade -->
    </record>
</data>

<!-- noupdate="1": data TIDAK di-update saat upgrade -->
<!-- Artinya jika user sudah mengubah data ini, perubahannya tidak ditimpa -->
<data noupdate="1">
    <record id="default_category" model="library.book.category">
        <!-- Seed data: user mungkin sudah edit, jangan timpa -->
    </record>
</data>
```

**Kapan pakai `noupdate="1"`:**
- Seed/default data (categories, sequences, email templates)
- Record rules dan security rules
- Cron jobs (automated actions)
- Data yang kemungkinan diubah user via UI

**Kapan pakai `noupdate="0"` (default):**
- Views, menus, actions
- Apapun yang developer kontrol sepenuhnya

### Cara Menulis Record XML

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <!-- 1. Record biasa -->
        <record id="category_fiction" model="library.book.category">
            <field name="name">Fiction</field>
        </record>

        <!-- 2. Record dengan relasi Many2one (ref) -->
        <record id="category_scifi" model="library.book.category">
            <field name="name">Science Fiction</field>
            <field name="parent_id" ref="category_fiction"/>
        </record>

        <!-- 3. Record dengan eval (untuk tipe data Python) -->
        <record id="book_sample" model="library.book">
            <field name="name">Sample Book</field>
            <field name="price" eval="99.50"/>
            <field name="active" eval="True"/>
            <field name="date_published" eval="'2024-01-15'"/>
        </record>

        <!-- 4. Many2many via eval -->
        <record id="book_tagged" model="library.book">
            <field name="name">Tagged Book</field>
            <field name="tag_ids" eval="[
                (4, ref('tag_bestseller')),
                (4, ref('tag_new_arrival')),
            ]"/>
        </record>

        <!-- 5. One2many via eval -->
        <record id="loan_with_lines" model="library.loan">
            <field name="member_id" ref="member_john"/>
            <field name="line_ids" eval="[
                (0, 0, {'copy_id': ref('copy_001'), 'notes': 'Good condition'}),
                (0, 0, {'copy_id': ref('copy_002')}),
            ]"/>
        </record>

        <!-- 6. HTML field -->
        <record id="book_with_desc" model="library.book">
            <field name="name">Book with Description</field>
            <field name="description" type="html">
                <p>This is a <strong>great</strong> book.</p>
            </field>
        </record>

        <!-- 7. File field (base64 dari file) -->
        <record id="book_with_image" model="library.book">
            <field name="cover_image" type="base64"
                   file="library_management/static/img/default_cover.png"/>
        </record>
    </data>
</odoo>
```

### Relational Field Commands (Magic Numbers)

Digunakan dalam `eval` untuk field `One2many` dan `Many2many`:

| Command | Syntax | Efek |
|---------|--------|------|
| `(0, 0, {vals})` | Create | Buat record baru dengan vals |
| `(1, id, {vals})` | Update | Update record id dengan vals |
| `(2, id, 0)` | Delete | Hapus record id dari database |
| `(3, id, 0)` | Unlink | Hapus relasi (M2M saja), record tetap ada |
| `(4, id, 0)` | Link | Tambah relasi ke record yang sudah ada |
| `(5, 0, 0)` | Unlink All | Hapus semua relasi (M2M saja) |
| `(6, 0, [ids])` | Replace | Set ulang relasi ke list of ids |

**Contoh penggunaan di Python:**
```python
# Tambah tag ke book
book.write({'tag_ids': [(4, tag_id)]})

# Set ulang semua tags
book.write({'tag_ids': [(6, 0, [tag1_id, tag2_id])]})

# Buat line baru di loan
loan.write({'line_ids': [(0, 0, {'copy_id': copy_id})]})

# Update line tertentu
loan.write({'line_ids': [(1, line_id, {'notes': 'Updated'})]})

# Hapus line
loan.write({'line_ids': [(2, line_id, 0)]})
```

### Fungsi dalam eval

```xml
<!-- Referensi ke record lain -->
<field name="partner_id" eval="ref('base.main_partner')"/>

<!-- Tanggal relatif -->
<field name="date" eval="(DateTime.now() + relativedelta(days=30)).strftime('%Y-%m-%d')"/>

<!-- Waktu sekarang -->
<field name="create_date" eval="DateTime.now().strftime('%Y-%m-%d %H:%M:%S')"/>

<!-- Boolean -->
<field name="active" eval="True"/>
<field name="active" eval="False"/>
```

### CSV Data Files

Cara cepat untuk memasukkan banyak data. Nama file = nama model.

```
# data/library.book.category.csv
id,name,parent_id:id
category_fiction,Fiction,
category_scifi,Science Fiction,category_fiction
category_fantasy,Fantasy,category_fiction
category_nonfiction,Non-Fiction,
category_science,Science,category_nonfiction
category_history,History,category_nonfiction
```

**Kolom khusus:**
- `id` — external ID (XML ID)
- `field_id:id` — referensi ke external ID record lain (untuk Many2one)
- `field_id/id` — alternatif untuk referensi

---

## Sequences (Auto-number)

### Definisi Sequence

```xml
<!-- data/sequence.xml -->
<data noupdate="1">
    <record id="seq_library_loan" model="ir.sequence">
        <field name="name">Library Loan</field>
        <field name="code">library.loan</field>
        <field name="prefix">LOAN/%(year)s/%(month)s/</field>
        <field name="padding">5</field>
        <field name="number_increment">1</field>
        <field name="number_next">1</field>
    </record>
</data>
```

### Prefix/Suffix Placeholders

| Placeholder | Hasil | Contoh |
|------------|-------|--------|
| `%(year)s` | Tahun 4 digit | 2026 |
| `%(month)s` | Bulan 2 digit | 05 |
| `%(day)s` | Tanggal 2 digit | 18 |
| `%(y)s` | Tahun 2 digit | 26 |
| `%(doy)s` | Day of year | 138 |
| `%(woy)s` | Week of year | 20 |
| `%(h24)s` | Jam (24h) | 14 |
| `%(sec)s` | Detik | 35 |

**Hasil contoh:** `LOAN/2026/05/00001`, `LOAN/2026/05/00002`, ...

### Menggunakan Sequence di Python

```python
@api.model_create_multi
def create(self, vals_list):
    for vals in vals_list:
        if vals.get('name', 'New') == 'New':
            vals['name'] = self.env['ir.sequence'].next_by_code('library.loan') or 'New'
    return super().create(vals_list)
```

### Sequence per Company (Multi-company)

```xml
<record id="seq_library_loan" model="ir.sequence">
    <field name="name">Library Loan</field>
    <field name="code">library.loan</field>
    <field name="prefix">LOAN/%(year)s/</field>
    <field name="padding">5</field>
    <field name="company_id" eval="False"/>  <!-- Shared across companies -->
</record>
```

---

## Automated Actions (ir.cron)

### Scheduled Action (Cron Job)

```xml
<!-- data/cron.xml -->
<data noupdate="1">
    <record id="cron_check_overdue_loans" model="ir.cron">
        <field name="name">Library: Check Overdue Loans</field>
        <field name="model_id" ref="model_library_loan"/>
        <field name="state">code</field>
        <field name="code">model._cron_check_overdue()</field>
        <field name="interval_number">1</field>
        <field name="interval_type">days</field>
        <field name="numbercall">-1</field>  <!-- -1 = unlimited -->
        <field name="active" eval="True"/>
    </record>

    <record id="cron_check_expired_members" model="ir.cron">
        <field name="name">Library: Check Expired Memberships</field>
        <field name="model_id" ref="model_library_member"/>
        <field name="state">code</field>
        <field name="code">model._cron_check_expired()</field>
        <field name="interval_number">1</field>
        <field name="interval_type">days</field>
        <field name="numbercall">-1</field>
        <field name="active" eval="True"/>
    </record>
</data>
```

**interval_type options:** `minutes`, `hours`, `days`, `weeks`, `months`

### Method untuk Cron

```python
class LibraryLoan(models.Model):
    _name = 'library.loan'

    @api.model
    def _cron_check_overdue(self):
        today = fields.Date.today()
        overdue_loans = self.search([
            ('state', '=', 'active'),
            ('due_date', '<', today),
        ])
        for loan in overdue_loans:
            loan.state = 'overdue'
            loan.message_post(
                body=f'Loan {loan.name} is overdue! Due date was {loan.due_date}.',
                message_type='notification',
            )
            loan.activity_schedule(
                'mail.mail_activity_data_todo',
                summary=f'Overdue loan: {loan.name}',
                note=f'Member {loan.member_id.name} has overdue books.',
            )


class LibraryMember(models.Model):
    _name = 'library.member'

    @api.model
    def _cron_check_expired(self):
        today = fields.Date.today()
        expired_members = self.search([
            ('state', '=', 'active'),
            ('expiry_date', '<', today),
        ])
        expired_members.write({'state': 'expired'})
```

---

## Server Actions

Server actions bisa dipanggil dari button, menu, atau secara otomatis.

### Tipe Server Action

```xml
<!-- 1. Execute Python Code -->
<record id="action_mark_books_available" model="ir.actions.server">
    <field name="name">Mark as Available</field>
    <field name="model_id" ref="model_library_book_copy"/>
    <field name="binding_model_id" ref="model_library_book_copy"/>
    <field name="binding_view_types">list</field>
    <field name="state">code</field>
    <field name="code">
        for record in records:
            record.state = 'available'
    </field>
</record>

<!-- 2. Create new record -->
<record id="action_create_fine" model="ir.actions.server">
    <field name="name">Create Fine</field>
    <field name="model_id" ref="model_library_loan"/>
    <field name="binding_model_id" ref="model_library_loan"/>
    <field name="state">object_create</field>
    <field name="crud_model_id" ref="model_library_fine"/>
    <field name="value">amount=1000</field>
</record>

<!-- 3. Send Email -->
<record id="action_send_overdue_email" model="ir.actions.server">
    <field name="name">Send Overdue Notification</field>
    <field name="model_id" ref="model_library_loan"/>
    <field name="state">email</field>
    <field name="template_id" ref="email_template_overdue"/>
</record>
```

### binding_model_id

Membuat server action muncul sebagai opsi di **Action** dropdown pada list/form view model tertentu. User bisa memilih records di tree view, lalu klik Action > nama server action.

---

## Email Templates

```xml
<!-- data/mail_template.xml -->
<data noupdate="1">
    <record id="email_template_overdue" model="mail.template">
        <field name="name">Library: Overdue Notification</field>
        <field name="model_id" ref="model_library_loan"/>
        <field name="subject">Overdue Book Loan: {{ object.name }}</field>
        <field name="email_from">{{ (object.company_id.email or user.email) }}</field>
        <field name="email_to">{{ object.member_id.email }}</field>
        <field name="body_html" type="html">
            <div>
                <p>Dear {{ object.member_id.name }},</p>
                <p>Your book loan <strong>{{ object.name }}</strong> is overdue.</p>
                <p>Due date was: <strong>{{ object.due_date }}</strong></p>
                <p>Books borrowed:</p>
                <ul>
                    <t t-foreach="object.line_ids" t-as="line">
                        <li><t t-out="line.book_title"/> ({{ line.barcode }})</li>
                    </t>
                </ul>
                <p>Please return the books as soon as possible to avoid fines.</p>
                <p>Regards,<br/>Library Management</p>
            </div>
        </field>
    </record>
</data>
```

### Mengirim Email dari Python

```python
def action_send_overdue_notice(self):
    template = self.env.ref('library_management.email_template_overdue')
    for loan in self:
        template.send_mail(loan.id, force_send=True)
```

---

## Demo Data

Demo data hanya di-load saat install dengan flag `--demo`. Berguna untuk testing.

```python
# __manifest__.py
{
    'demo': [
        'demo/demo_data.xml',
    ],
}
```

```xml
<!-- demo/demo_data.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data>
        <record id="demo_member_1" model="library.member">
            <field name="name">John Doe</field>
            <field name="email">john@example.com</field>
            <field name="membership_type">regular</field>
        </record>

        <record id="demo_book_1" model="library.book">
            <field name="name">The Great Gatsby</field>
            <field name="author">F. Scott Fitzgerald</field>
            <field name="isbn">978-0-7432-7356-5</field>
            <field name="category_id" ref="category_fiction"/>
        </record>

        <record id="demo_copy_1" model="library.book.copy">
            <field name="barcode">LIB-001-001</field>
            <field name="book_id" ref="demo_book_1"/>
            <field name="state">available</field>
        </record>
    </data>
</odoo>
```

---

## Ringkasan: Urutan File di __manifest__.py

```python
'data': [
    # 1. Security groups (paling awal, karena access rules merujuk group)
    'security/groups.xml',

    # 2. Access rights (harus setelah groups, sebelum views)
    'security/ir.model.access.csv',

    # 3. Data: sequences, seed data, cron jobs, email templates
    'data/sequence.xml',
    'data/category_data.xml',
    'data/cron.xml',
    'data/mail_template.xml',

    # 4. Views dan menus (paling akhir, karena action merujuk model yang sudah ada)
    'views/book_category_views.xml',
    'views/book_views.xml',
    'views/loan_views.xml',
    'views/menu.xml',  # Menu terakhir karena merujuk action dari views
],
```

**Aturan utama:** file yang dirujuk oleh file lain harus di-load duluan.
