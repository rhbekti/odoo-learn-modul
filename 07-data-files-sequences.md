# Bab 7: Data Files, Sequences & Automated Actions

> **Tahap:** 2 Inti Pengembangan | **Prasyarat:** Bab 3, 4, 6 | **Estimasi:** ± 3 jam | **Versi:** Odoo 18 (catatan Odoo 19)

## Tujuan Belajar

Setelah bab ini kamu bisa:
- Menulis data file XML dan CSV, termasuk relasi Many2one, Many2many, dan One2many.
- Menentukan kapan memakai `noupdate="1"` dan kapan tidak.
- Membuat sequence otomatis dan memakainya dari Python.
- Membuat scheduled action (`ir.cron`), server action, dan email template.
- Mengatur urutan file `data` dan `demo` di `__manifest__.py`.

> **Beda di Odoo 19:** Belum ada perbedaan terverifikasi untuk sintaks data file di bab ini. Kalau modulmu gagal di-install di Odoo 19, periksa dulu field `ir.cron` dan server action yang kamu pakai terhadap release notes versi 19.

Catatan: contoh di bab ini memakai model contoh seperti `library.book.category`, `library.loan`, `library.member`, dan `library.book.copy`. Kalau modulmu belum punya model tersebut, ganti dengan model milikmu sendiri.

## Data Files (XML & CSV)

Data file memasukkan data ke database saat modul di-install atau di-upgrade. Semuanya didaftarkan di `'data'` (atau `'demo'`) pada manifest.

### noupdate: Kapan Data Bisa Di-overwrite

```xml
<!-- noupdate="0" (default): record DI-UPDATE setiap upgrade modul -->
<data noupdate="0">
    <record id="view_something" model="ir.ui.view">
        <!-- Views, menu, action: developer yang mengontrol, perubahan harus ikut -->
    </record>
</data>

<!-- noupdate="1": record TIDAK ditimpa saat upgrade (hanya dibuat saat install) -->
<data noupdate="1">
    <record id="default_category" model="library.book.category">
        <!-- Seed data: user mungkin sudah edit, jangan timpa -->
    </record>
</data>
```

`noupdate` juga bisa dipasang di root: `<odoo noupdate="1">`.

**Kapan pakai `noupdate="1"`:**
- Seed/default data (kategori, sequence, email template)
- Record rules (Bab 6) dan data konfigurasi lain yang boleh diubah admin
- Cron job
- Data yang kemungkinan diubah user lewat UI

**Kapan pakai `noupdate="0"` (default):**
- Views, menu, action
- Apa pun yang sepenuhnya dikontrol developer

Konsekuensi: kalau kamu mengubah record yang ada di blok `noupdate="1"` pada XML, perubahan itu tidak akan masuk ke database yang sudah terinstall. Ubah lewat UI, lewat migrasi, atau hapus recordnya agar dibuat ulang.

### Cara Menulis Record XML

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <!-- 1. Record biasa -->
        <record id="category_fiction" model="library.book.category">
            <field name="name">Fiction</field>
        </record>

        <!-- 2. Many2one lewat ref -->
        <record id="category_scifi" model="library.book.category">
            <field name="name">Science Fiction</field>
            <field name="parent_id" ref="category_fiction"/>
        </record>

        <!-- 3. Nilai bertipe Python lewat eval -->
        <record id="book_sample" model="library.book">
            <field name="name">Sample Book</field>
            <field name="price" eval="99.50"/>
            <field name="active" eval="True"/>
            <field name="date_published">2024-01-15</field>
        </record>

        <!-- 4. Many2many lewat eval (tag_bestseller dan tag_new_arrival harus sudah ada) -->
        <record id="book_tagged" model="library.book">
            <field name="name">Tagged Book</field>
            <field name="tag_ids" eval="[
                (4, ref('tag_bestseller')),
                (4, ref('tag_new_arrival')),
            ]"/>
        </record>

        <!-- 5. One2many lewat eval -->
        <record id="loan_with_lines" model="library.loan">
            <field name="member_id" ref="member_john"/>
            <field name="line_ids" eval="[
                (0, 0, {'copy_id': ref('copy_001'), 'notes': 'Good condition'}),
                (0, 0, {'copy_id': ref('copy_002')}),
            ]"/>
        </record>

        <!-- 6. Field HTML -->
        <record id="book_with_desc" model="library.book">
            <field name="name">Book with Description</field>
            <field name="description" type="html">
                <p>This is a <strong>great</strong> book.</p>
            </field>
        </record>

        <!-- 7. Field file (base64 dari file di modul) -->
        <record id="book_with_image" model="library.book">
            <field name="cover_image" type="base64"
                   file="library_management/static/img/default_cover.png"/>
        </record>
    </data>
</odoo>
```

### Relational Field Commands

Dipakai untuk field `One2many` dan `Many2many`. Di XML (`eval`) kamu menulis tuple angka; di Python gunakan `Command` dari `odoo` supaya lebih mudah dibaca (`from odoo import Command`).

| Tuple (di XML eval) | Python | Efek |
|---------|--------|------|
| `(0, 0, {vals})` | `Command.create(vals)` | Buat record baru |
| `(1, id, {vals})` | `Command.update(id, vals)` | Update record `id` dengan vals |
| `(2, id, 0)` | `Command.delete(id)` | Hapus record `id` dari database |
| `(3, id, 0)` | `Command.unlink(id)` | Lepas relasi, record tetap ada |
| `(4, id, 0)` | `Command.link(id)` | Tambah relasi ke record yang sudah ada |
| `(5, 0, 0)` | `Command.clear()` | Lepas semua relasi |
| `(6, 0, [ids])` | `Command.set([ids])` | Ganti seluruh relasi dengan daftar ids |

Contoh di Python:

```python
from odoo import Command

# Tambah tag ke book
book.write({'tag_ids': [Command.link(tag_id)]})

# Set ulang semua tags
book.write({'tag_ids': [Command.set([tag1_id, tag2_id])]})

# Buat line baru di loan
loan.write({'line_ids': [Command.create({'copy_id': copy_id})]})

# Update line tertentu
loan.write({'line_ids': [Command.update(line_id, {'notes': 'Updated'})]})

# Hapus line
loan.write({'line_ids': [Command.delete(line_id)]})
```

### Fungsi dalam eval

```xml
<!-- Referensi ke record lain -->
<field name="partner_id" eval="ref('base.main_partner')"/>

<!-- Tanggal relatif -->
<field name="date" eval="(DateTime.now() + relativedelta(days=30)).strftime('%Y-%m-%d')"/>
```

### CSV Data Files

Cara cepat memasukkan banyak data. Nama file = nama model, dan baris pertama adalah header kolom.

`data/library.book.category.csv`:

```
id,name,parent_id:id
category_fiction,Fiction,
category_scifi,Science Fiction,category_fiction
category_fantasy,Fantasy,category_fiction
category_nonfiction,Non-Fiction,
category_science,Science,category_nonfiction
category_history,History,category_nonfiction
```

**Kolom khusus:**
- `id`: external ID (XML ID) record
- `field_id:id`: referensi ke external ID record lain (untuk Many2one)
- `field_id/id`: penulisan alternatif untuk referensi yang sama

Catatan: CSV tidak punya mekanisme `noupdate` per baris. Untuk data yang tidak boleh ditimpa, pakai XML dengan `noupdate="1"`. File `ir.model.access.csv` (Bab 6) memakai aturan yang sama dengan CSV data biasa.

---

## Sequences (Auto-number)

### Definisi Sequence

```xml
<!-- data/sequence.xml -->
<odoo>
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
</odoo>
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

Field `name` pada model biasanya diberi `default='New'` dan `copy=False`.

### Sequence Bersama atau per Company

Field `company_id` pada sequence menentukan cakupannya. Isi `False` supaya satu sequence dipakai bersama semua company; tanpa itu, sequence terikat ke company tertentu (Bab 14 membahas multi-company lebih lengkap).

```xml
<record id="seq_library_loan" model="ir.sequence">
    <field name="name">Library Loan</field>
    <field name="code">library.loan</field>
    <field name="prefix">LOAN/%(year)s/</field>
    <field name="padding">5</field>
    <field name="company_id" eval="False"/>  <!-- dipakai bersama semua company -->
</record>
```

---

## Scheduled Actions (ir.cron)

### Cron Job

```xml
<!-- data/cron.xml -->
<odoo>
    <data noupdate="1">
        <record id="cron_check_overdue_loans" model="ir.cron">
            <field name="name">Library: Check Overdue Loans</field>
            <field name="model_id" ref="model_library_loan"/>
            <field name="state">code</field>
            <field name="code">model._cron_check_overdue()</field>
            <field name="user_id" ref="base.user_root"/>
            <field name="interval_number">1</field>
            <field name="interval_type">days</field>
            <field name="active" eval="True"/>
        </record>

        <record id="cron_check_expired_members" model="ir.cron">
            <field name="name">Library: Check Expired Memberships</field>
            <field name="model_id" ref="model_library_member"/>
            <field name="state">code</field>
            <field name="code">model._cron_check_expired()</field>
            <field name="user_id" ref="base.user_root"/>
            <field name="interval_number">1</field>
            <field name="interval_type">days</field>
            <field name="active" eval="True"/>
        </record>
    </data>
</odoo>
```

**interval_type:** `minutes`, `hours`, `days`, `weeks`, `months`

Contoh di atas sengaja tidak memakai field `numbercall` dan `doall`. Kalau kamu menemukan field itu di modul lama dan muncul error saat install, hapus barisnya.

### Method untuk Cron

Method yang dipanggil cron adalah method biasa pada model; kerjakan di batch dan jangan lupa model perlu mewarisi `mail.thread` / `mail.activity.mixin` kalau memakai `message_post` / `activity_schedule`.

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

Server action bisa dipanggil dari tombol, menu, atau dijalankan dari menu Action pada list/form.

### Execute Python Code

```xml
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
```

Di dalam `code`, variabel `records` berisi record yang dipilih user, dan `env` tersedia. Tulis kode mulai dari kolom pertama (tanpa indentasi awal) agar tidak error indentasi.

### Send Email

```xml
<record id="action_send_overdue_email" model="ir.actions.server">
    <field name="name">Send Overdue Notification</field>
    <field name="model_id" ref="model_library_loan"/>
    <field name="state">email</field>
    <field name="template_id" ref="email_template_overdue"/>
</record>
```

Server action tipe lain (membuat/mengubah record tanpa kode) tersedia lewat UI; untuk modul, tipe `code` paling fleksibel dan paling mudah dirawat.

### binding_model_id

Membuat server action muncul di dropdown **Action** pada list/form view model tertentu. User memilih record di list view, lalu klik Action > nama server action. `binding_view_types` menentukan view mana yang menampilkannya (`list`, `form`, atau `list,form`).

---

## Email Templates

Di `body_html` (dirender dengan QWeb) gunakan `t-out` dan `t-foreach`; ekspresi `{{ ... }}` dipakai pada field teks pendek seperti `subject`, `email_from`, dan `email_to`. `t-esc` adalah sintaks lama, gunakan `t-out`.

```xml
<!-- data/mail_template.xml -->
<odoo>
    <data noupdate="1">
        <record id="email_template_overdue" model="mail.template">
            <field name="name">Library: Overdue Notification</field>
            <field name="model_id" ref="model_library_loan"/>
            <field name="subject">Overdue Book Loan: {{ object.name }}</field>
            <field name="email_from">{{ (object.company_id.email or user.email) }}</field>
            <field name="email_to">{{ object.member_id.email }}</field>
            <field name="body_html" type="html">
                <div>
                    <p>Dear <t t-out="object.member_id.name or ''"/>,</p>
                    <p>Your book loan <strong><t t-out="object.name or ''"/></strong> is overdue.</p>
                    <p>Due date was: <strong><t t-out="object.due_date or ''"/></strong></p>
                    <p>Books borrowed:</p>
                    <ul>
                        <t t-foreach="object.line_ids" t-as="line">
                            <li><t t-out="line.book_title or ''"/> (<t t-out="line.barcode or ''"/>)</li>
                        </t>
                    </ul>
                    <p>Please return the books as soon as possible to avoid fines.</p>
                    <p>Regards,<br/>Library Management</p>
                </div>
            </field>
        </record>
    </data>
</odoo>
```

Model `library.loan` perlu mewarisi `mail.thread` agar template bisa dikirim.

### Mengirim Email dari Python

```python
def action_send_overdue_notice(self):
    template = self.env.ref('library_management.email_template_overdue')
    for loan in self:
        template.send_mail(loan.id, force_send=True)
```

---

## Demo Data

Demo data dipakai untuk testing dan demo; jangan diandalkan di production. Di-load hanya kalau database dibuat dengan demo data aktif (checkbox "Demo data" saat membuat database lewat UI, atau tanpa opsi `--without-demo` di command line). Daftarkan di key `demo` pada manifest.

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
</odoo>
```

---

## Urutan File di `__manifest__.py`

Odoo me-load modul sesuai urutan dependensi. Di dalam satu modul, seluruh file `data` di-load **berurutan sesuai daftar**, dan setelah itu file `demo` (jika demo aktif). Jadi data di `demo` boleh merujuk record dari `data`, tapi tidak sebaliknya.

```python
'data': [
    # 1. Security: group dulu, karena CSV, rule, dan views merujuk group
    'security/groups.xml',
    'security/ir.model.access.csv',
    'security/ir_rule.xml',

    # 2. Data: sequences, seed data, email template, server action, cron
    'data/sequence.xml',
    'data/category_data.xml',
    'data/mail_template.xml',  # sebelum server action yang merujuk template ini
    'data/cron.xml',

    # 3. Views dan menu (paling akhir)
    'views/book_category_views.xml',
    'views/book_views.xml',
    'views/loan_views.xml',
    'views/menu.xml',  # menu terakhir karena merujuk action dari views
],
'demo': [
    'demo/demo_data.xml',
],
```

**Aturan utama:** file yang dirujuk oleh file lain (lewat `ref`, `groups=`, `action=`, `template_id`) harus di-load lebih dulu.

## Ringkasan

- Data file XML/CSV didaftarkan di `'data'` (selalu) atau `'demo'` (hanya jika demo aktif).
- `noupdate="1"` melindungi data dari penimpaan saat upgrade; pakai untuk seed data, sequence, cron, rule, dan template.
- Field relasi diisi dengan command (`(0,0,{})`, `(4,id,0)`, `(6,0,[])`, dst.) di XML dan `Command.*` di Python.
- Sequence dibuat sebagai `ir.sequence` dan dipakai lewat `next_by_code()` di `create()` (`@api.model_create_multi`).
- Cron memanggil method model pada interval tertentu; email template memakai `t-out` di `body_html`.
- Urutan manifest: security, data, views, menu; file `demo` di-load setelah `data` dalam modul yang sama.

## Latihan

1. Buat `data/library.book.category.csv` dengan tiga kategori (satu induk, dua anak). Daftarkan di manifest, upgrade, lalu cek hasilnya di UI.
2. Buat `ir.sequence` dengan prefix `LOAN/%(year)s/` dan padding 4, pakai di `create()` model peminjaman. Buat tiga record dan pastikan nomornya berurutan.
3. Buat satu cron yang berjalan harian dan memanggil method model untuk mengubah status record yang lewat tanggal jatuh tempo. Jalankan manual lewat Settings > Technical > Scheduled Actions (Run Manually) dan cek hasilnya.

## Lanjut ke

Bab 8: Inheritance & Override (`08-inheritance-override.md`).
