# Bab 8: Model Inheritance & Override

> **Tahap:** 2 Inti Pengembangan | **Prasyarat:** Bab 3, 4, 5 (dan Bab 7 untuk contoh sequence) | **Estimasi:** ± 3 jam | **Versi:** Odoo 18 (catatan Odoo 19)

## Tujuan Belajar

Setelah bab ini kamu bisa:
- Membedakan 3 jenis inheritance Odoo (extension, prototype, delegation) dan memilih yang tepat.
- Menambah field dan meng-override method (`create`, `write`, `unlink`, display name) model yang sudah ada dengan `super()`.
- Memodifikasi view module lain lewat `inherit_id` dan XPath.
- Meng-override record data (action, menu) dari module lain lewat XML ID.
- Menyusun module extension kecil yang meng-extend `res.partner`.

---

## Ringkasan 3 Jenis Inheritance

Odoo punya 3 jenis inheritance. Memahami perbedaannya sangat penting.

| Jenis | `_inherit` | `_name` | Efek |
|-------|-----------|---------|------|
| Class Inheritance (Extension) | Ya | Tidak (atau sama) | Menambah/mengubah model yang sudah ada |
| Prototype Inheritance | Ya | Ya (baru) | Copy model ke model baru |
| Delegation Inheritance | Tidak | Ya (baru) | Komposisi, link ke model lain via `_inherits` |

---

## 1. Class Inheritance (Extension)

**Paling sering digunakan.** Menambah field, method, atau mengubah behavior model yang sudah ada **tanpa** membuat table baru.

### 1.1 Menambah Field ke Model yang Sudah Ada

```python
# models/res_partner.py
from odoo import models, fields


class ResPartner(models.Model):
    _inherit = 'res.partner'

    # Menambah field baru ke res.partner
    membership_number = fields.Char(string='Membership Number')
    membership_date = fields.Date(string='Membership Date')
    is_library_member = fields.Boolean(string='Library Member', default=False)
    book_ids = fields.One2many('library.book', 'partner_id', string='Borrowed Books')
```

**Penting:** Tidak ada `_name` baru. Field-field ini langsung masuk ke table `res_partner` yang sudah ada.

> Contoh ini mengasumsikan model `library.book` punya field `partner_id` (Many2one ke `res.partner`), seperti di studi kasus Library (Bab 10).

### 1.2 Override Attribute Field

Cukup deklarasi ulang nama field yang sama. Attribute yang tidak kamu tulis tetap memakai nilai aslinya.

```python
class ResPartner(models.Model):
    _inherit = 'res.partner'

    # Hanya mengubah attribute; tipe field & attribute lain tidak berubah
    email = fields.Char(tracking=True)   # perubahan email sekarang di-track
```

Hati-hati: mengubah attribute seperti `required=True` pada field milik model inti (misalnya `phone` di `res.partner`) akan memengaruhi seluruh Odoo, termasuk data import dan module lain. Lakukan hanya jika memang yakin.

### 1.3 Menambah Opsi Selection (`selection_add`)

Mendeklarasikan ulang field Selection **tanpa** `selection_add` akan mengganti seluruh daftar opsi. Untuk menambah opsi, pakai `selection_add`:

```python
class SaleOrder(models.Model):
    _inherit = 'sale.order'

    state = fields.Selection(
        selection_add=[
            ('waiting_approval', 'Waiting Approval'),
            ('approved', 'Approved'),
        ],
        ondelete={
            'waiting_approval': 'set default',
            'approved': 'set default',
        },
    )
```

**`ondelete`** menentukan apa yang terjadi pada record yang memakai opsi tambahan itu jika module kamu di-uninstall (opsi tersebut hilang dari selection). Sebaiknya selalu kamu isi untuk setiap opsi baru di `selection_add`, supaya uninstall module tidak merusak data.

| Nilai `ondelete` | Efek pada record yang memakai opsi itu |
|------------------|----------------------------------------|
| `'set default'` | Set ke default value field |
| `'set null'` | Set ke kosong |
| `'set <nilai>'` | Set ke opsi lain tertentu, misal `'set draft'` |
| `'cascade'` | **Hapus record** (hati-hati, bisa menghapus data penting seperti order) |

### 1.4 Override Method dengan `super()`

Aturan dasarnya: panggil `super()` (tanpa argumen, Python 3) supaya logika asli tetap jalan, lalu tambahkan logikamu sebelum dan/atau sesudahnya.

#### `create` (pakai `@api.model_create_multi`)

Sejak Odoo 12+ `create` menerima **list** of dict (`vals_list`), jadi override-nya memakai `@api.model_create_multi`.

```python
from odoo import models, fields, api


class ResPartner(models.Model):
    _inherit = 'res.partner'

    @api.model_create_multi
    def create(self, vals_list):
        # Sebelum create: manipulasi vals
        for vals in vals_list:
            if vals.get('is_library_member') and not vals.get('membership_number'):
                vals['membership_number'] = self.env['ir.sequence'].next_by_code('library.membership')

        # Panggil parent create
        records = super().create(vals_list)

        # Sesudah create: operasi pada record yang sudah dibuat
        for record in records.filtered('is_library_member'):
            record.message_post(body='New library member registered!')

        return records
```

> Sequence `library.membership` harus sudah didefinisikan di data file (lihat Bab 7). Kalau belum, `next_by_code` mengembalikan `False`.

`message_post` hanya ada jika model memakai `mail.thread` (`res.partner` sudah memakainya).

#### `write`

```python
    def write(self, vals):
        # Sebelum write
        old_states = {rec.id: rec.is_library_member for rec in self}

        result = super().write(vals)

        # Sesudah write: bandingkan sebelum dan sesudah
        for rec in self:
            if rec.is_library_member and not old_states.get(rec.id):
                rec.message_post(body='Became a library member!')

        return result
```

#### `unlink` dengan `@api.ondelete`

Untuk validasi sebelum delete, cara yang direkomendasikan adalah `@api.ondelete(at_uninstall=False)`. Dengan `at_uninstall=False`, pengecekan **tidak** ikut jalan saat module di-uninstall, jadi uninstall tidak terblokir oleh validasi bisnis.

```python
from odoo.exceptions import UserError


class ResPartner(models.Model):
    _inherit = 'res.partner'

    @api.ondelete(at_uninstall=False)
    def _unlink_except_borrowed_books(self):
        for rec in self:
            if rec.book_ids.filtered(lambda b: b.state == 'borrowed'):
                raise UserError(f'{rec.name} masih punya buku yang dipinjam!')
```

Meng-override `unlink()` lalu memanggil `super().unlink()` masih bisa dipakai untuk logika "sesudah/sebelum delete" lain, tetapi untuk validasi pencegahan delete, pakai `@api.ondelete`.

#### Display name (bukan lagi `name_get`)

`name_get()` sudah **deprecated sejak Odoo 17**. Display name sekarang adalah field computed `display_name`, jadi yang di-override adalah `_compute_display_name`:

```python
class ResPartner(models.Model):
    _inherit = 'res.partner'

    @api.depends('membership_number')
    def _compute_display_name(self):
        super()._compute_display_name()
        for record in self:
            if record.membership_number:
                record.display_name = f"[{record.membership_number}] {record.display_name}"
```

Pola ini sama dengan override compute method lain: panggil `super()` dulu, lalu modifikasi hasilnya. Tambahkan field yang kamu pakai ke `@api.depends`.

#### Override Computed Field

```python
class SaleOrderLine(models.Model):
    _inherit = 'sale.order.line'

    # Contoh ilustrasi: order_id.is_special_discount adalah field custom milikmu sendiri
    @api.depends('product_uom_qty', 'discount', 'price_unit', 'tax_id')
    def _compute_amount(self):
        # Panggil parent computation dulu
        super()._compute_amount()
        # Lalu modifikasi hasilnya
        for line in self:
            if line.order_id.is_special_discount:
                line.price_subtotal *= 0.9
```

Nama method compute dan `@api.depends`-nya bisa berbeda antar versi dan module. Selalu cek source module yang kamu inherit sebelum meng-override.

### 1.5 Pola Umum Override Method

**Pola 1: Validasi sebelum aksi**

```python
class SaleOrder(models.Model):
    _inherit = 'sale.order'

    def action_confirm(self):
        for order in self:
            if order.amount_total > 10000 and not order.approval_id:  # approval_id: field custom
                raise UserError('Order > 10.000 butuh approval!')
        return super().action_confirm()
```

**Pola 2: Aksi tambahan sesudah**

```python
class StockPicking(models.Model):
    _inherit = 'stock.picking'

    def button_validate(self):
        result = super().button_validate()
        # Setelah validasi picking, update library stock
        for picking in self:
            for move in picking.move_ids:
                if move.product_id.is_library_book:           # field custom
                    self._update_book_availability(move)      # method custom
        return result
```

**Pola 3: Replace sepenuhnya (hati-hati!)**

```python
class SaleOrder(models.Model):
    _inherit = 'sale.order'

    def _compute_tax_totals(self):
        # TIDAK panggil super() — replace sepenuhnya.
        # Hanya lakukan ini jika benar-benar perlu! Module lain yang meng-override
        # method yang sama bisa ikut terlewat.
        for order in self:
            order.tax_totals = self._custom_tax_calculation(order)   # method custom
```

### 1.6 Inherit Mixin (Multiple Inheritance)

Model baru bisa "mewarisi" beberapa mixin sekaligus lewat `_inherit` berupa list. Ini yang membuat model punya chatter, activity, dan sebagainya.

```python
class LibraryBook(models.Model):
    _name = 'library.book'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _description = 'Library Book'

    name = fields.Char(required=True, tracking=True)
    state = fields.Selection([
        ('available', 'Available'),
        ('borrowed', 'Borrowed'),
    ], default='available', tracking=True)
```

**Mixin yang sering dipakai:**

| Mixin | Fungsi |
|-------|--------|
| `mail.thread` | Chatter (log messages, followers) |
| `mail.activity.mixin` | Activity scheduling |
| `portal.mixin` | Portal access untuk customer |
| `image.mixin` | Auto-resize image fields |
| `utm.mixin` | UTM tracking (campaign, source, medium) |
| `rating.mixin` | Customer rating/review |

---

## 2. Prototype Inheritance

Meng-copy seluruh field dan method dari model lain ke model **baru**. Jarang digunakan.

```python
class LibraryBookCopy(models.Model):
    _name = 'library.book.copy'
    _inherit = 'library.book'  # COPY semua dari library.book
    _description = 'Book Copy'

    # Model baru dengan table sendiri (library_book_copy)
    # Semua field dari library.book ter-copy ke sini
    # Bisa tambah field baru
    copy_number = fields.Integer(string='Copy Number')
    condition = fields.Selection([
        ('good', 'Good'),
        ('fair', 'Fair'),
        ('poor', 'Poor'),
    ], default='good')
```

**Kapan dipakai:** ketika butuh model baru dengan struktur mirip model yang sudah ada, tapi independent (table terpisah). Yang ikut ter-copy hanya definisi Python (field dan method); view, action, menu, dan access rights **tidak** ikut, jadi harus dibuat lagi untuk model baru.

---

## 3. Delegation Inheritance (`_inherits`)

Komposisi: model baru "memiliki" model lain. Field parent bisa diakses langsung dari child, tapi disimpan di table parent.

```python
class LibraryMember(models.Model):
    _name = 'library.member'
    _inherits = {'res.partner': 'partner_id'}
    _description = 'Library Member'

    # Field ini WAJIB: link ke parent model
    partner_id = fields.Many2one('res.partner', required=True, ondelete='cascade')

    # Field tambahan khusus member
    membership_number = fields.Char(string='Membership Number')
    membership_type = fields.Selection([
        ('basic', 'Basic'),
        ('premium', 'Premium'),
    ], default='basic')
    expiry_date = fields.Date(string='Expiry Date')
```

**Cara kerja:**
- Membuat record `library.member` otomatis membuat record `res.partner`.
- `member.name` langsung mengakses `partner_id.name` (transparent).
- Data `name`, `email`, `phone` disimpan di table `res_partner`.
- Data `membership_number`, `membership_type` disimpan di table `library_member`.

```python
# Penggunaan:
member = self.env['library.member'].create({
    'name': 'John Doe',             # disimpan di res_partner
    'email': 'john@example.com',    # disimpan di res_partner
    'membership_number': 'M001',    # disimpan di library_member
    'membership_type': 'premium',   # disimpan di library_member
})

print(member.name)        # 'John Doe' — akses langsung tanpa .partner_id
print(member.partner_id)  # res.partner(1,)
```

**Contoh nyata di Odoo:** `res.users` menggunakan `_inherits = {'res.partner': 'partner_id'}`. Setiap user punya partner.

> Yang didelegasikan hanya **field**. Method milik parent (`res.partner`) tidak otomatis menjadi method `library.member`.

---

## 4. Inherit View dari Module Lain

View module lain tidak boleh diedit langsung. Kamu membuat view baru yang `inherit_id` ke view induk, lalu memodifikasinya dengan XPath.

### 4.1 Contoh Paling Sederhana

```xml
<record id="view_partner_form_inherit_library" model="ir.ui.view">
    <field name="name">res.partner.form.inherit.library</field>
    <field name="model">res.partner</field>
    <field name="inherit_id" ref="base.view_partner_form"/>
    <field name="arch" type="xml">
        <!-- Tambah field setelah field tertentu -->
        <xpath expr="//field[@name='website']" position="after">
            <field name="is_library_member"/>
            <field name="membership_number"
                   invisible="not is_library_member"/>
        </xpath>
    </field>
</record>
```

Untuk target berupa field, ada bentuk singkat tanpa `xpath`: `<field name="website" position="after">...</field>`.

### 4.2 Posisi XPath

| Position | Efek |
|----------|------|
| `after` | Sisipkan setelah element |
| `before` | Sisipkan sebelum element |
| `inside` | Sisipkan di dalam element (di akhir) |
| `replace` | Ganti element (kosong = hapus element) |
| `attributes` | Ubah attribute element |

### 4.3 Contoh XPath Lengkap

Pastikan elemen target (`website`, `phone`, `notebook`, `header`, dst.) memang ada di view induk versi yang kamu pakai. Cek lewat developer mode (Edit View) dan sesuaikan `expr`-nya.

```xml
<record id="view_partner_form_inherit_library" model="ir.ui.view">
    <field name="name">res.partner.form.inherit.library</field>
    <field name="model">res.partner</field>
    <field name="inherit_id" ref="base.view_partner_form"/>
    <field name="arch" type="xml">

        <!-- 1. Tambah field setelah element -->
        <xpath expr="//field[@name='phone']" position="after">
            <field name="membership_number"/>
        </xpath>

        <!-- 2. Tambah field sebelum element -->
        <xpath expr="//field[@name='email']" position="before">
            <field name="is_library_member"/>
        </xpath>

        <!-- 3. Sisipkan di dalam group -->
        <xpath expr="//group[@name='sale']" position="inside">
            <field name="library_credit"/>
        </xpath>

        <!-- 4. Ganti element sepenuhnya -->
        <xpath expr="//field[@name='website']" position="replace">
            <field name="website" widget="url" placeholder="https://..."/>
        </xpath>

        <!-- 5. Ubah attributes saja -->
        <xpath expr="//field[@name='phone']" position="attributes">
            <attribute name="required">is_library_member</attribute>
            <attribute name="string">Phone Number</attribute>
        </xpath>

        <!-- 6. Hapus element (replace dengan kosong) -->
        <xpath expr="//field[@name='function']" position="replace"/>

        <!-- 7. Tambah page baru di notebook -->
        <xpath expr="//notebook" position="inside">
            <page string="Library" name="library">
                <group>
                    <field name="book_ids"/>
                </group>
            </page>
        </xpath>

        <!-- 8. Tambah button di header (jika view induk punya <header>) -->
        <xpath expr="//header" position="inside">
            <button name="action_register_member"
                    string="Register as Member"
                    type="object"
                    class="btn-primary"
                    invisible="is_library_member"/>
        </xpath>
    </field>
</record>
```

Field `library_credit` di contoh 3 dan method `action_register_member` di contoh 8 hanyalah ilustrasi; kamu harus mendefinisikannya sendiri di model.

### 4.4 Inherit List View

Tag view daftar adalah `<list>` (bukan `<tree>`), jadi XPath yang menargetkannya juga memakai `list`.

```xml
<record id="view_partner_list_inherit_library" model="ir.ui.view">
    <field name="name">res.partner.list.inherit.library</field>
    <field name="model">res.partner</field>
    <field name="inherit_id" ref="base.view_partner_tree"/>
    <field name="arch" type="xml">
        <xpath expr="//field[@name='email']" position="after">
            <field name="is_library_member"/>
            <field name="membership_number"/>
        </xpath>
    </field>
</record>
```

> XML ID view bawaan (misalnya `base.view_partner_tree`) bisa tetap memakai kata "tree" di namanya; yang berubah adalah tag di dalam `arch`-nya, yaitu `<list>`.

### 4.5 Inherit Search View

```xml
<record id="view_partner_search_inherit_library" model="ir.ui.view">
    <field name="name">res.partner.search.inherit.library</field>
    <field name="model">res.partner</field>
    <field name="inherit_id" ref="base.view_res_partner_filter"/>
    <field name="arch" type="xml">
        <xpath expr="//filter[@name='type_company']" position="after">
            <separator/>
            <filter name="library_member"
                    string="Library Members"
                    domain="[('is_library_member', '=', True)]"/>
        </xpath>
    </field>
</record>
```

### 4.6 Priority View

```xml
<!-- priority lebih rendah = diproses lebih dulu -->
<record id="view_partner_form_inherit_library" model="ir.ui.view">
    <field name="name">res.partner.form.inherit.library</field>
    <field name="model">res.partner</field>
    <field name="inherit_id" ref="base.view_partner_form"/>
    <field name="priority">20</field>  <!-- default 16 -->
    <field name="arch" type="xml">
        <!-- ... -->
    </field>
</record>
```

> **Beda di Odoo 19:** Untuk view, tidak ada perubahan konsep dibanding Odoo 18. Tag tetap `<list>` dan `attrs=`/`states=` tetap tidak dipakai (sudah dihapus sejak Odoo 17); gunakan `invisible="expr"`, `readonly="expr"`, `required="expr"`, dan `column_invisible` di list.

---

## 5. Override Data Records dari Module Lain

Selama XML ID sama (`module.xml_id`), record di-update, bukan di-create ulang. Ini berlaku untuk action, menu, dan record data lain.

### Override Action

```xml
<!-- Override action window dari module lain -->
<record id="base.action_partner_form" model="ir.actions.act_window">
    <field name="name">Partners &amp; Members</field>
    <field name="context">{'default_is_library_member': True}</field>
</record>
```

Kamu juga bisa menimpa field lain seperti `domain`, tapi berhati-hatilah: `domain` yang terlalu ketat akan menyembunyikan data dari semua pengguna action itu.

### Override Menu

```xml
<!-- Ubah nama menu yang sudah ada -->
<record id="contacts.menu_contacts" model="ir.ui.menu">
    <field name="name">Contacts &amp; Members</field>
</record>
```

Catatan: di XML, karakter `&` harus ditulis `&amp;`. Module yang kamu override harus ada di `depends` (di contoh ini `base` dan `contacts`).

---

## 6. Contoh Lengkap: Extend `res.partner`

### Struktur Module

```
library_member/
├── __init__.py
├── __manifest__.py
├── data/
│   └── library_sequence.xml      # sequence 'library.membership' (lihat Bab 7)
├── models/
│   ├── __init__.py
│   └── res_partner.py
└── views/
    └── res_partner_views.xml
```

Karena module ini hanya meng-extend model yang sudah ada (tanpa model baru), tidak perlu file `ir.model.access.csv` tambahan.

### `__manifest__.py`

```python
{
    'name': 'Library Member',
    'version': '1.0.0',
    # 'library' = ganti dengan nama module yang mendefinisikan model library.book
    'depends': ['base', 'contacts', 'mail', 'library'],
    'data': [
        'data/library_sequence.xml',
        'views/res_partner_views.xml',
    ],
    'installable': True,
}
```

### `models/res_partner.py`

```python
from odoo import models, fields, api


class ResPartner(models.Model):
    _inherit = 'res.partner'

    is_library_member = fields.Boolean(default=False)
    membership_number = fields.Char(string='Membership No.')
    membership_date = fields.Date(string='Member Since')
    book_ids = fields.One2many('library.book', 'partner_id', string='Borrowed Books')
    book_count = fields.Integer(compute='_compute_book_count', string='Books Borrowed')

    @api.depends('book_ids')
    def _compute_book_count(self):
        for partner in self:
            partner.book_count = len(partner.book_ids)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('is_library_member') and not vals.get('membership_number'):
                vals['membership_number'] = self.env['ir.sequence'].next_by_code('library.membership')
        return super().create(vals_list)

    def action_view_books(self):
        self.ensure_one()
        return {
            'name': 'Borrowed Books',
            'type': 'ir.actions.act_window',
            'res_model': 'library.book',
            'view_mode': 'list,form',
            'domain': [('partner_id', '=', self.id)],
        }
```

### `views/res_partner_views.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_partner_form_inherit_library" model="ir.ui.view">
        <field name="name">res.partner.form.inherit.library</field>
        <field name="model">res.partner</field>
        <field name="inherit_id" ref="base.view_partner_form"/>
        <field name="arch" type="xml">
            <!-- Tambah smart button -->
            <xpath expr="//div[@name='button_box']" position="inside">
                <button name="action_view_books"
                        type="object"
                        class="oe_stat_button"
                        icon="fa-book"
                        invisible="not is_library_member">
                    <field name="book_count" widget="statinfo" string="Books"/>
                </button>
            </xpath>

            <!-- Tambah fields -->
            <xpath expr="//field[@name='website']" position="after">
                <field name="is_library_member"/>
                <field name="membership_number"
                       invisible="not is_library_member"/>
                <field name="membership_date"
                       invisible="not is_library_member"/>
            </xpath>

            <!-- Tambah tab di notebook -->
            <xpath expr="//notebook" position="inside">
                <page string="Library" name="library"
                      invisible="not is_library_member">
                    <field name="book_ids">
                        <list>
                            <field name="name"/>
                            <field name="isbn"/>
                            <field name="state"/>
                        </list>
                    </field>
                </page>
            </xpath>
        </field>
    </record>
</odoo>
```

---

## Tips & Gotchas

1. **`_inherit` tanpa `_name`** = extend model yang ada (SATU table).
2. **`_inherit` dengan `_name` baru** = copy model (table BARU).
3. **`_inherits`** (pakai s) = delegation/komposisi (DUA table, linked).
4. **Selalu panggil `super()`** kecuali benar-benar ingin replace.
5. **`super()` tanpa argument.** Odoo 18 dan 19 berjalan di Python 3 (minimal 3.10), tidak perlu `super(ClassName, self)`. `@api.multi` juga sudah tidak ada sejak Odoo 11.
6. **Override field:** cukup deklarasi ulang nama field yang sama; attribute yang tidak diset tetap memakai nilai aslinya.
7. **Jangan lupa `depends`** di `__manifest__.py`: module yang model/view-nya kamu inherit harus ada di `depends`.
8. **`attrs` dan `states` di view sudah dihapus** (sejak Odoo 17). Pakai attribute langsung: `invisible="condition"`, `readonly="condition"`, `required="condition"`.
9. **Display name:** override `_compute_display_name`, bukan `name_get()`.

---

## Ringkasan

- Extension (`_inherit` saja) menambah/mengubah model yang ada di table yang sama; ini jenis yang paling sering dipakai.
- Prototype (`_inherit` + `_name` baru) meng-copy definisi ke table baru; delegation (`_inherits`) menyimpan data di dua table yang saling terhubung.
- Saat override method, panggil `super()`; `create` memakai `@api.model_create_multi`, validasi delete memakai `@api.ondelete(at_uninstall=False)`, dan display name lewat `_compute_display_name`.
- `selection_add` perlu `ondelete` per opsi baru agar uninstall module aman; hindari `'cascade'` untuk data penting.
- View module lain diubah lewat `inherit_id` + XPath (`after`, `before`, `inside`, `replace`, `attributes`); tag daftar adalah `<list>`.
- Record data (action, menu) bisa di-override dengan XML ID yang sama, dan module targetnya harus ada di `depends`.

## Latihan

1. Buat module `library_member` seperti Contoh Lengkap: tambahkan field `is_library_member` dan `membership_number` ke `res.partner`, lalu tampilkan keduanya di form partner lewat XPath (field kedua hanya muncul saat `is_library_member` dicentang).
2. Override `_compute_display_name` di `res.partner` agar partner yang punya `membership_number` tampil sebagai `[M001] Nama`. Cek hasilnya di field Many2one pada form lain.
3. Tambahkan validasi dengan `@api.ondelete(at_uninstall=False)` yang menolak penghapusan partner yang masih punya buku berstatus `borrowed`, lalu coba hapus partner tersebut untuk memastikan error `UserError` muncul.

## Lanjut ke

Bab 9: Wizards & Dialogs, yaitu membuat popup dialog untuk mengumpulkan input user sebelum memproses data.
