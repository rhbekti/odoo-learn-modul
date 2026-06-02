# Bab 9: Model Inheritance & Override

Odoo memiliki 3 jenis inheritance. Memahami perbedaannya sangat penting.

## Ringkasan 3 Jenis Inheritance

| Jenis | `_inherit` | `_name` | Efek |
|-------|-----------|---------|------|
| Class Inheritance (Extension) | Ya | Tidak (atau sama) | Menambah/mengubah model yang sudah ada |
| Prototype Inheritance | Ya | Ya (baru) | Copy model ke model baru |
| Delegation Inheritance | Tidak | Ya (baru) | Komposisi, link ke model lain via `_inherits` |

---

## 1. Class Inheritance (Extension)

**Paling sering digunakan.** Menambah field, method, atau mengubah behavior model yang sudah ada **tanpa** membuat table baru.

### Menambah Field ke Model yang Sudah Ada

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

### Override Method

```python
class ResPartner(models.Model):
    _inherit = 'res.partner'

    def name_get(self):
        result = []
        for record in self:
            name = record.name
            if record.membership_number:
                name = f"[{record.membership_number}] {name}"
            result.append((record.id, name))
        return result
```

### Override Method dengan super()

```python
class ResPartner(models.Model):
    _inherit = 'res.partner'

    @api.model
    def create(self, vals):
        # Sebelum create: manipulasi vals
        if vals.get('is_library_member') and not vals.get('membership_number'):
            vals['membership_number'] = self.env['ir.sequence'].next_by_code('library.membership')

        # Panggil parent create
        record = super().create(vals)

        # Sesudah create: operasi pada record yang sudah dibuat
        if record.is_library_member:
            record.message_post(body='New library member registered!')

        return record

    def write(self, vals):
        # Sebelum write
        old_states = {rec.id: rec.is_library_member for rec in self}

        result = super().write(vals)

        # Sesudah write: bandingkan sebelum dan sesudah
        for rec in self:
            if rec.is_library_member and not old_states.get(rec.id):
                rec.message_post(body='Became a library member!')

        return result

    def unlink(self):
        # Validasi sebelum delete
        for rec in self:
            if rec.book_ids.filtered(lambda b: b.state == 'borrowed'):
                raise UserError(f'{rec.name} masih punya buku yang dipinjam!')
        return super().unlink()
```

### Override Computed Field

```python
class SaleOrderLine(models.Model):
    _inherit = 'sale.order.line'

    # Override compute method dari field yang sudah ada
    @api.depends('product_uom_qty', 'discount', 'price_unit', 'tax_id')
    def _compute_amount(self):
        # Panggil parent computation dulu
        super()._compute_amount()
        # Lalu modifikasi hasilnya
        for line in self:
            if line.order_id.is_special_discount:
                line.price_subtotal *= 0.9
```

### Override Field Attributes

```python
class ResPartner(models.Model):
    _inherit = 'res.partner'

    # Override attribute field yang sudah ada
    # Cukup deklarasi ulang field dengan attribute yang mau diubah
    phone = fields.Char(required=True)  # phone jadi required
    email = fields.Char(tracking=True)  # email sekarang di-track perubahannya

    # Tambah selection ke field Selection yang sudah ada
    # CATATAN: ini MENGGANTI seluruh selection, bukan menambah
    # Untuk menambah, gunakan selection_add
```

### Menambah Selection Options (selection_add)

```python
class SaleOrder(models.Model):
    _inherit = 'sale.order'

    # Menambah option ke field selection yang sudah ada
    state = fields.Selection(
        selection_add=[
            ('waiting_approval', 'Waiting Approval'),  # option baru
            ('approved', 'Approved'),
        ],
        ondelete={
            'waiting_approval': 'set default',
            'approved': 'cascade',
        }
    )
```

**`ondelete`** wajib di Odoo 18: menentukan apa yang terjadi pada record jika module di-uninstall dan selection value hilang.

| ondelete value | Efek |
|---------------|------|
| `'set default'` | Set ke default value |
| `'cascade'` | Hapus record |
| `'set null'` | Set ke null/kosong |

### Inherit Multiple Models (Mixin)

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

**Kapan dipakai:** Ketika butuh model baru dengan struktur mirip model yang sudah ada, tapi independent (table terpisah).

---

## 3. Delegation Inheritance (_inherits)

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
- Membuat record `library.member` otomatis membuat record `res.partner`
- `member.name` langsung mengakses `partner_id.name` (transparent)
- Data `name`, `email`, `phone` disimpan di table `res_partner`
- Data `membership_number`, `membership_type` disimpan di table `library_member`

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

**Contoh nyata di Odoo:** `res.users` menggunakan `_inherits = {'res.partner': 'partner_id'}` — setiap user punya partner.

---

## Override Views dari Module Lain

### Menambah Field ke Form View yang Sudah Ada

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

### XPath Positions

| Position | Efek |
|----------|------|
| `after` | Sisipkan setelah element |
| `before` | Sisipkan sebelum element |
| `inside` | Sisipkan di dalam element (di akhir) |
| `replace` | Ganti element |
| `attributes` | Ubah attribute element |

### Contoh XPath Lengkap

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
            <attribute name="required">1</attribute>
            <attribute name="string">Phone Number</attribute>
        </xpath>

        <!-- 6. Hapus element (replace dengan kosong) -->
        <xpath expr="//field[@name='fax']" position="replace"/>

        <!-- 7. Tambah page baru di notebook -->
        <xpath expr="//notebook" position="inside">
            <page string="Library" name="library">
                <group>
                    <field name="book_ids"/>
                </group>
            </page>
        </xpath>

        <!-- 8. Tambah button di header -->
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

### Override Tree View

```xml
<record id="view_partner_tree_inherit_library" model="ir.ui.view">
    <field name="name">res.partner.tree.inherit.library</field>
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

### Override Search View

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

### View Priority (Urutan Inheritance)

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

---

## Override Data Records dari Module Lain

### Override Record yang Sudah Ada (via XML ID)

```xml
<!-- Override action window dari module lain -->
<record id="base.action_partner_form" model="ir.actions.act_window">
    <field name="name">Partners & Members</field>
    <field name="context">{'default_is_library_member': True}</field>
</record>
```

Selama XML ID sama (`base.action_partner_form`), record di-update bukan di-create ulang.

### Override Menu

```xml
<!-- Ubah nama menu yang sudah ada -->
<record id="contacts.menu_contacts" model="ir.ui.menu">
    <field name="name">Contacts & Members</field>
</record>
```

### Override Server Action

```xml
<record id="base.action_partner_form" model="ir.actions.act_window">
    <field name="domain">[('is_library_member', '=', True)]</field>
    <field name="context">{'default_is_library_member': True}</field>
</record>
```

---

## Override Method: Pattern Umum

### Pattern 1: Validasi Sebelum Aksi

```python
class SaleOrder(models.Model):
    _inherit = 'sale.order'

    def action_confirm(self):
        for order in self:
            if order.amount_total > 10000 and not order.approval_id:
                raise UserError('Order > 10.000 butuh approval!')
        return super().action_confirm()
```

### Pattern 2: Modifikasi Values Sebelum Create/Write

```python
class SaleOrder(models.Model):
    _inherit = 'sale.order'

    @api.model
    def create(self, vals):
        if vals.get('partner_id'):
            partner = self.env['res.partner'].browse(vals['partner_id'])
            if partner.is_library_member:
                vals['note'] = f"Library Member: {partner.membership_number}"
        return super().create(vals)
```

### Pattern 3: Aksi Tambahan Sesudah

```python
class StockPicking(models.Model):
    _inherit = 'stock.picking'

    def button_validate(self):
        result = super().button_validate()
        # Setelah validasi picking, update library stock
        for picking in self:
            for move in picking.move_ids:
                if move.product_id.is_library_book:
                    self._update_book_availability(move)
        return result
```

### Pattern 4: Completely Replace (Hati-hati!)

```python
class SaleOrder(models.Model):
    _inherit = 'sale.order'

    def _compute_tax_totals(self):
        # TIDAK panggil super() — replace sepenuhnya
        # Hanya lakukan ini jika benar-benar perlu!
        for order in self:
            order.tax_totals = self._custom_tax_calculation(order)
```

---

## Contoh Lengkap: Extend res.partner

### Struktur Module

```
library_member/
├── __init__.py
├── __manifest__.py
├── models/
│   ├── __init__.py
│   └── res_partner.py
├── views/
│   └── res_partner_views.xml
└── security/
    └── ir.model.access.csv
```

### __manifest__.py

```python
{
    'name': 'Library Member',
    'version': '1.0.0',
    'depends': ['base', 'contacts', 'mail'],
    'data': [
        'security/ir.model.access.csv',
        'views/res_partner_views.xml',
    ],
    'installable': True,
}
```

### models/res_partner.py

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

    @api.model
    def create(self, vals):
        if vals.get('is_library_member') and not vals.get('membership_number'):
            vals['membership_number'] = self.env['ir.sequence'].next_by_code('library.membership')
        return super().create(vals)

    def action_view_books(self):
        return {
            'name': 'Borrowed Books',
            'type': 'ir.actions.act_window',
            'res_model': 'library.book',
            'view_mode': 'tree,form',
            'domain': [('partner_id', '=', self.id)],
        }
```

### views/res_partner_views.xml

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
                        <tree>
                            <field name="name"/>
                            <field name="isbn"/>
                            <field name="state"/>
                        </tree>
                    </field>
                </page>
            </xpath>
        </field>
    </record>
</odoo>
```

---

## Tips & Gotchas

1. **`_inherit` tanpa `_name`** = extend model yang ada (SATU table)
2. **`_inherit` dengan `_name` baru** = copy model (table BARU)
3. **`_inherits`** (pakai s) = delegation/komposisi (DUA table, linked)
4. **Selalu panggil `super()`** kecuali benar-benar ingin replace
5. **`super()` tanpa argument** — Odoo 18 sudah pakai Python 3, tidak perlu `super(ClassName, self)`
6. **Override field:** cukup deklarasi ulang nama field yang sama, attribute yang tidak diset tetap pakai nilai aslinya
7. **Jangan lupa `depends`** di `__manifest__.py` — module yang model-nya kamu inherit harus ada di depends
8. **Odoo 18:** `attrs` diganti jadi attribute langsung (`invisible="condition"`, `readonly="condition"`) — tidak pakai dict `attrs` lagi
