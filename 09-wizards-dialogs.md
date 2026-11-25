# Bab 9: Wizards & Dialogs

> **Tahap:** 2 Inti Pengembangan | **Prasyarat:** Bab 4, 5, 6, 8 | **Estimasi:** ± 2,5 jam | **Versi:** Odoo 18 (catatan Odoo 19)

## Tujuan Belajar

Setelah bab ini kamu bisa:
- Membuat wizard dengan `models.TransientModel` beserta form view berbentuk dialog.
- Membuka wizard dari button (`type="object"` dan `type="action"`) dan menutupnya dengan `ir.actions.act_window_close`.
- Mengisi nilai awal wizard lewat `default_get` dan context (`active_id`, `active_ids`, `active_model`).
- Membuat wizard untuk banyak record sekaligus dan wizard multi-step.
- Mengarahkan user ke record lain setelah wizard selesai.

---

## 1. Konsep Dasar

### Apa itu Wizard?

Wizard adalah transient model yang mengumpulkan data dari user lewat popup dialog, lalu memproses data tersebut.

Karakteristik `TransientModel`:
- Record-nya bersifat sementara dan dibersihkan otomatis secara berkala oleh Odoo (autovacuum), jadi jangan dipakai untuk menyimpan data permanen.
- Tetap punya table di database, field, dan view seperti model biasa.
- Wizard diajarkan setelah inheritance (Bab 8) karena wizard sering dipakai untuk menambah aksi pada model yang sudah ada.

### Struktur File

Konvensinya, wizard ditaruh di folder `wizard/` terpisah dari `models/`:

```
library/
├── __init__.py              # from . import models, wizard
├── __manifest__.py
├── models/
│   ├── __init__.py
│   └── ...
├── wizard/
│   ├── __init__.py          # from . import library_loan_wizard
│   ├── library_loan_wizard.py
│   └── library_loan_wizard_views.xml
└── security/
    └── ir.model.access.csv
```

---

## 2. Wizard Pertama: Pinjam Buku

### 2.1 Transient Model

```python
# wizard/library_loan_wizard.py
from odoo import models, fields, api
from odoo.exceptions import UserError


class LibraryLoanWizard(models.TransientModel):
    _name = 'library.loan.wizard'
    _description = 'Loan Book Wizard'

    book_id = fields.Many2one('library.book', string='Book', required=True)
    partner_id = fields.Many2one('res.partner', string='Borrower', required=True)
    loan_days = fields.Integer(string='Loan Days', default=14, required=True)
    notes = fields.Text(string='Notes')

    def action_confirm_loan(self):
        self.ensure_one()
        if self.book_id.state != 'available':
            raise UserError('Buku ini sedang tidak tersedia!')

        # Buat record loan (asumsi: model library.loan dari studi kasus Bab 10)
        loan = self.env['library.loan'].create({
            'book_id': self.book_id.id,
            'partner_id': self.partner_id.id,
            'loan_days': self.loan_days,
            'notes': self.notes,
        })

        # Update status buku
        self.book_id.write({'state': 'borrowed'})

        return {'type': 'ir.actions.act_window_close'}
```

`{'type': 'ir.actions.act_window_close'}` menutup dialog wizard. Method wizard tanpa return apa pun juga menutup dialog, tetapi return eksplisit lebih jelas.

### 2.2 Wizard View (Dialog)

Tombol aksi wizard ditaruh di dalam `<footer>`, supaya muncul di bagian bawah dialog.

```xml
<record id="view_library_loan_wizard" model="ir.ui.view">
    <field name="name">library.loan.wizard.form</field>
    <field name="model">library.loan.wizard</field>
    <field name="arch" type="xml">
        <form string="Loan Book">
            <group>
                <group string="Book Info">
                    <field name="book_id" readonly="1"/>
                </group>
                <group string="Loan Details">
                    <field name="partner_id"/>
                    <field name="loan_days"/>
                </group>
            </group>
            <field name="notes" placeholder="Additional notes..."/>
            <footer>
                <button name="action_confirm_loan"
                        string="Confirm Loan"
                        class="btn-primary"
                        type="object"/>
                <button string="Cancel" class="btn-secondary" special="cancel"/>
            </footer>
        </form>
    </field>
</record>
```

`special="cancel"` menutup dialog tanpa memanggil method apa pun.

### 2.3 Action untuk Membuka Wizard

Wizard dibuka lewat `ir.actions.act_window` dengan `target` bernilai `new` (artinya tampil sebagai dialog, bukan halaman penuh).

```xml
<record id="action_library_loan_wizard" model="ir.actions.act_window">
    <field name="name">Loan Book</field>
    <field name="res_model">library.loan.wizard</field>
    <field name="view_mode">form</field>
    <field name="target">new</field>
</record>
```

### 2.4 Memanggil Wizard dari Button

Ada dua cara. Pilih salah satu.

**Cara A: button `type="action"` di XML** (memanggil action di atas lewat XML ID):

```xml
<button name="%(library.action_library_loan_wizard)d"
        string="Loan Book"
        type="action"
        class="btn-primary"/>
```

Ganti `library` dengan nama module tempat action didefinisikan.

**Cara B: button `type="object"` + method Python yang me-return action:**

```xml
<button name="action_loan_book" string="Loan Book" type="object" class="btn-primary"/>
```

```python
# di model library.book
def action_loan_book(self):
    self.ensure_one()
    return {
        'name': 'Loan Book',
        'type': 'ir.actions.act_window',
        'res_model': 'library.loan.wizard',
        'view_mode': 'form',
        'target': 'new',
        'context': {
            'default_book_id': self.id,
        },
    }
```

### 2.5 Mengisi Nilai Awal Wizard

Ada dua mekanisme, dan keduanya bisa dipakai bersamaan.

**1. Context `default_<nama_field>`.** Odoo otomatis memakainya sebagai default field. Contoh di Cara B di atas: `'default_book_id': self.id` sudah cukup mengisi `book_id`, tanpa override apa pun.

**2. Override `default_get`.** Dipakai bila nilai awal butuh logika, atau saat wizard dipanggil dari button `type="action"` / Action menu. Saat action dipanggil dari form atau list, Odoo menaruh record yang sedang aktif ke context:

| Key context | Isi |
|-------------|-----|
| `active_id` | ID record yang sedang dibuka (form) |
| `active_ids` | List ID record terpilih (list) |
| `active_model` | Nama model record tersebut, misal `'library.book'` |

```python
@api.model
def default_get(self, fields_list):
    res = super().default_get(fields_list)
    if self.env.context.get('active_model') == 'library.book' and 'book_id' in fields_list:
        res['book_id'] = self.env.context.get('active_id')
    return res
```

Nama parameter `fields_list` dipakai (bukan `fields`) supaya tidak menimpa import `fields` dari `odoo`.

---

## 3. Wizard untuk Banyak Record

Wizard sering dipakai untuk memproses banyak record yang dipilih user di list view. Record yang dipilih ada di `active_ids`.

```python
class LibraryReturnWizard(models.TransientModel):
    _name = 'library.return.wizard'
    _description = 'Return Books Wizard'

    return_date = fields.Date(string='Return Date', required=True,
                              default=fields.Date.context_today)
    penalty = fields.Float(string='Penalty Fee', default=0)

    def action_return_books(self):
        active_ids = self.env.context.get('active_ids', [])
        loans = self.env['library.loan'].browse(active_ids)

        for loan in loans:
            loan.write({
                'return_date': self.return_date,
                'penalty': self.penalty,
                'state': 'returned',
            })
            # Update status buku
            loan.book_id.write({'state': 'available'})

        return {'type': 'ir.actions.act_window_close'}
```

Agar wizard muncul di menu **Action** pada list view `library.loan` dan `active_ids` terisi, action wizard-nya perlu dikaitkan (binding) ke model target:

```xml
<record id="action_library_return_wizard" model="ir.actions.act_window">
    <field name="name">Return Books</field>
    <field name="res_model">library.return.wizard</field>
    <field name="view_mode">form</field>
    <field name="target">new</field>
    <field name="binding_model_id" ref="model_library_loan"/>
</record>
```

`model_library_loan` adalah XML ID otomatis dari model `library.loan` (format `model_<nama_model_dengan_underscore>`). Untuk view form wizard-nya, strukturnya sama seperti Bagian 2.2 (field di body, tombol di `<footer>`).

### Wizard dengan Selection (Aksi Massal)

```python
class LibraryBulkActionWizard(models.TransientModel):
    _name = 'library.bulk.action.wizard'
    _description = 'Bulk Action Wizard'

    action_type = fields.Selection([
        ('mark_available', 'Mark as Available'),
        ('mark_unavailable', 'Mark as Unavailable'),
        ('archive', 'Archive'),
    ], string='Action', required=True)

    def execute_action(self):
        active_ids = self.env.context.get('active_ids', [])
        records = self.env['library.book'].browse(active_ids)

        if self.action_type == 'mark_available':
            records.write({'state': 'available'})
        elif self.action_type == 'mark_unavailable':
            records.write({'state': 'borrowed'})
        elif self.action_type == 'archive':
            records.write({'active': False})

        return {'type': 'ir.actions.act_window_close'}
```

---

## 4. Wizard dengan One2many (Input Banyak Baris)

Wizard bisa punya baris input sendiri lewat One2many ke transient model lain.

```python
class LibraryImportWizard(models.TransientModel):
    _name = 'library.import.wizard'
    _description = 'Import Books Wizard'

    line_ids = fields.One2many(
        'library.import.line.wizard',
        'wizard_id',
        string='Import Lines'
    )

    def action_import(self):
        self.ensure_one()
        self.env['library.book'].create([
            {'name': line.name, 'author': line.author, 'isbn': line.isbn}
            for line in self.line_ids
        ])
        return {'type': 'ir.actions.act_window_close'}


class LibraryImportLineWizard(models.TransientModel):
    _name = 'library.import.line.wizard'
    _description = 'Import Line Wizard'

    wizard_id = fields.Many2one('library.import.wizard', ondelete='cascade')
    name = fields.Char(string='Title', required=True)
    author = fields.Char(string='Author')
    isbn = fields.Char(string='ISBN')
```

`create` menerima list of dict, jadi semua buku dibuat sekaligus dalam satu panggilan.

```xml
<record id="view_library_import_wizard" model="ir.ui.view">
    <field name="name">library.import.wizard.form</field>
    <field name="model">library.import.wizard</field>
    <field name="arch" type="xml">
        <form string="Import Books">
            <group>
                <field name="line_ids">
                    <list editable="bottom">
                        <field name="name"/>
                        <field name="author"/>
                        <field name="isbn"/>
                    </list>
                </field>
            </group>
            <footer>
                <button name="action_import" string="Import" class="btn-primary" type="object"/>
                <button string="Cancel" special="cancel"/>
            </footer>
        </form>
    </field>
</record>
```

Perhatikan: list inline di dalam field memakai tag `<list>`, bukan `<tree>`.

---

## 5. Wizard dengan Confirmation Dialog

Untuk konfirmasi sederhana ("yakin?"), kamu tidak selalu butuh wizard: atribut `confirm` di button sudah menampilkan dialog konfirmasi bawaan, misalnya `<button name="action_archive" type="object" string="Archive" confirm="Yakin mau mengarsipkan?"/>`.

Wizard konfirmasi dipakai bila pesannya dinamis atau butuh input tambahan:

```python
class LibraryDeleteWizard(models.TransientModel):
    _name = 'library.delete.wizard'
    _description = 'Delete Confirmation Wizard'

    message = fields.Text(readonly=True)

    @api.model
    def default_get(self, fields_list):
        res = super().default_get(fields_list)
        count = len(self.env.context.get('active_ids', []))
        res['message'] = f'Are you sure you want to delete {count} book(s)?'
        return res

    def action_confirm_delete(self):
        active_ids = self.env.context.get('active_ids', [])
        records = self.env['library.book'].browse(active_ids)
        records.unlink()
        return {'type': 'ir.actions.act_window_close'}
```

View dan action-nya mengikuti pola yang sama dengan wizard pinjam buku: tampilkan `message` (readonly) di body dan dua tombol di footer.

---

## 6. Multi-step Wizard

Wizard multi-step memakai satu record transient yang sama, dengan field `step` untuk menentukan bagian form yang tampil. Setiap pindah step, wizard dibuka ulang dengan `res_id` record yang sama supaya data yang sudah diisi tidak hilang.

```python
class LibraryMultiStepWizard(models.TransientModel):
    _name = 'library.multistep.wizard'
    _description = 'Multi-step Wizard'

    step = fields.Integer(string='Step', default=1)
    name = fields.Char(string='Title')
    author = fields.Char(string='Author')
    category_id = fields.Many2one('library.category', string='Category')

    def _reopen(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'res_model': self._name,
            'res_id': self.id,
            'view_mode': 'form',
            'target': 'new',
        }

    def next_step(self):
        self.ensure_one()
        self.step += 1
        return self._reopen()

    def prev_step(self):
        self.ensure_one()
        self.step -= 1
        return self._reopen()

    def action_finish(self):
        self.ensure_one()
        self.env['library.book'].create({
            'name': self.name,
            'author': self.author,
            'category_id': self.category_id.id,
        })
        return {'type': 'ir.actions.act_window_close'}
```

```xml
<form string="Add Book">
    <field name="step" invisible="1"/>
    <group invisible="step != 1">
        <field name="name"/>
        <field name="author"/>
    </group>
    <group invisible="step != 2">
        <field name="category_id"/>
    </group>
    <footer>
        <button name="prev_step" string="Back" type="object" invisible="step == 1"/>
        <button name="next_step" string="Next" type="object" class="btn-primary" invisible="step == 2"/>
        <button name="action_finish" string="Finish" type="object" class="btn-primary" invisible="step != 2"/>
        <button string="Cancel" special="cancel"/>
    </footer>
</form>
```

Field yang dipakai di ekspresi `invisible` (di sini `step`) harus ada di view, makanya `step` ditaruh dengan `invisible="1"`.

---

## 7. Redirect setelah Wizard

Selain menutup dialog, wizard bisa mengarahkan user ke record yang baru dibuat:

```python
def action_confirm_loan(self):
    self.ensure_one()

    loan = self.env['library.loan'].create({
        'book_id': self.book_id.id,
        'partner_id': self.partner_id.id,
    })

    # Redirect ke form loan
    return {
        'name': 'Loan',
        'type': 'ir.actions.act_window',
        'res_model': 'library.loan',
        'res_id': loan.id,
        'view_mode': 'form',
        'target': 'current',
    }
```

---

## 8. Contoh Lengkap: Wizard Pinjam Buku

### `wizard/library_loan_wizard.py`

```python
from odoo import models, fields, api
from odoo.exceptions import UserError


class LibraryLoanWizard(models.TransientModel):
    _name = 'library.loan.wizard'
    _description = 'Loan Book Wizard'

    book_id = fields.Many2one('library.book', string='Book', required=True)
    partner_id = fields.Many2one('res.partner', string='Borrower', required=True)
    loan_days = fields.Integer(string='Loan Days', default=14, required=True)

    @api.model
    def default_get(self, fields_list):
        res = super().default_get(fields_list)
        if self.env.context.get('active_model') == 'library.book' and 'book_id' in fields_list:
            res['book_id'] = self.env.context.get('active_id')
        return res

    def action_confirm_loan(self):
        self.ensure_one()
        if self.book_id.state != 'available':
            raise UserError('Buku ini sedang tidak tersedia!')

        self.env['library.loan'].create({
            'book_id': self.book_id.id,
            'partner_id': self.partner_id.id,
            'loan_days': self.loan_days,
        })

        self.book_id.write({'state': 'borrowed'})
        return {'type': 'ir.actions.act_window_close'}
```

### `wizard/library_loan_wizard_views.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_library_loan_wizard" model="ir.ui.view">
        <field name="name">library.loan.wizard.form</field>
        <field name="model">library.loan.wizard</field>
        <field name="arch" type="xml">
            <form>
                <group>
                    <group>
                        <field name="book_id" readonly="1"/>
                    </group>
                    <group>
                        <field name="partner_id"/>
                        <field name="loan_days"/>
                    </group>
                </group>
                <footer>
                    <button name="action_confirm_loan" string="Confirm" class="btn-primary" type="object"/>
                    <button string="Cancel" special="cancel"/>
                </footer>
            </form>
        </field>
    </record>

    <record id="action_library_loan_wizard" model="ir.actions.act_window">
        <field name="name">Loan Book</field>
        <field name="res_model">library.loan.wizard</field>
        <field name="view_mode">form</field>
        <field name="target">new</field>
    </record>
</odoo>
```

### `__manifest__.py` (bagian data)

```python
'data': [
    'security/ir.model.access.csv',          # untuk model biasa (library.book, dst.)
    'wizard/library_loan_wizard_views.xml',
],
```

### Access Rights untuk Model Wizard

Pada versi modern Odoo, `TransientModel` umumnya tidak butuh baris di `ir.model.access.csv`: record wizard hanya dibuat dan dipakai oleh user yang membukanya. Namun yang tetap berlaku adalah hak akses ke **model lain** yang disentuh wizard (misalnya `library.loan` dan `library.book`), karena wizard berjalan dengan hak akses user yang menekan tombol. Jika kamu mendapat error "access" saat memakai wizard, periksa hak akses model target dulu.

> **Beda di Odoo 19:** Tidak ada perubahan konsep wizard yang terverifikasi di Odoo 19. Yang perlu diingat sama dengan Odoo 18: tag daftar adalah `<list>` dan kondisi tampilan memakai `invisible="expr"` (bukan `attrs`).

---

## Ringkasan

- Wizard = `models.TransientModel` + form view berbentuk dialog (`target="new"`); recordnya sementara dan dibersihkan otomatis.
- Tombol wizard ditaruh di `<footer>`; `special="cancel"` menutup dialog, dan `{'type': 'ir.actions.act_window_close'}` menutup dialog setelah proses selesai.
- Wizard dibuka lewat button `type="action"` (memanggil action XML) atau `type="object"` (method yang me-return dict action).
- Nilai awal diisi lewat context `default_<field>` atau override `default_get`; record aktif ada di `active_id`, `active_ids`, dan `active_model`.
- Untuk memproses banyak record, ambil `active_ids` dari context; `binding_model_id` memunculkan wizard di menu Action.
- Multi-step wizard membuka ulang record transient yang sama (`res_id`) dengan field `step`; setelah selesai, wizard bisa menutup dialog atau me-redirect ke record lain.

## Latihan

1. Buat wizard `library.loan.wizard` seperti di Bagian 2: dibuka dari button di form buku, `book_id` terisi otomatis lewat context `default_book_id`, lalu "Confirm" membuat record loan dan menutup dialog.
2. Tambahkan wizard "Return Books" yang muncul di menu Action pada list view loan (pakai `binding_model_id`), memproses semua loan terpilih dari `active_ids`.
3. Ubah wizard pinjam buku agar menolak (dengan `UserError`) buku yang statusnya bukan `available`, lalu setelah sukses me-redirect user ke form loan yang baru dibuat.

## Lanjut ke

Bab 10: Multi-Model Module (studi kasus Library), yaitu menggabungkan model, view, security, data, inheritance, dan wizard menjadi satu module utuh.
