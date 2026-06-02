# Bab 18: Tips, Best Practices & Common Patterns

## Naming Conventions

### Python

| Elemen | Convention | Contoh |
|--------|-----------|--------|
| Module name | `snake_case` | `library_management` |
| Model `_name` | `dot.notation` | `library.book.copy` |
| Class name | `CamelCase` | `LibraryBookCopy` |
| Field name | `snake_case` | `loan_date` |
| Method name | `snake_case` | `action_confirm` |
| Computed method | `_compute_xxx` | `_compute_total` |
| Onchange method | `_onchange_xxx` | `_onchange_partner_id` |
| Constraint method | `_check_xxx` | `_check_dates` |
| Cron method | `_cron_xxx` | `_cron_check_overdue` |
| Private method | `_xxx` | `_prepare_values` |

### XML

| Elemen | Convention | Contoh |
|--------|-----------|--------|
| View ID | `view_{model}_{type}` | `view_library_book_form` |
| Inherit View ID | `view_{model}_{type}_inherit_{module}` | `view_partner_form_inherit_library` |
| Action ID | `action_{model}` | `action_library_book` |
| Menu ID | `menu_{name}` | `menu_library_root` |
| Group ID | `group_{name}` | `group_library_manager` |
| Sequence ID | `seq_{name}` | `seq_library_loan` |

---

## Patterns yang Sering Dipakai

### 1. State Machine Pattern

```python
class LibraryLoan(models.Model):
    _name = 'library.loan'

    state = fields.Selection([
        ('draft', 'Draft'),
        ('confirmed', 'Confirmed'),
        ('active', 'Active'),
        ('returned', 'Returned'),
        ('cancel', 'Cancelled'),
    ], default='draft', required=True, tracking=True)

    # Transisi state: selalu validasi di method, bukan langsung write
    def action_confirm(self):
        for rec in self.filtered(lambda r: r.state == 'draft'):
            rec._validate_confirm()
            rec.state = 'confirmed'

    def action_activate(self):
        for rec in self.filtered(lambda r: r.state == 'confirmed'):
            rec.state = 'active'

    def action_return(self):
        for rec in self.filtered(lambda r: r.state == 'active'):
            rec.state = 'returned'

    def action_cancel(self):
        for rec in self.filtered(lambda r: r.state in ('draft', 'confirmed')):
            rec.state = 'cancel'

    def action_reset_draft(self):
        for rec in self.filtered(lambda r: r.state == 'cancel'):
            rec.state = 'draft'

    def _validate_confirm(self):
        self.ensure_one()
        if not self.line_ids:
            raise UserError('Minimal 1 buku harus dipilih!')
```

### 2. Header-Line Pattern

```python
# Header
class SaleOrder(models.Model):
    _name = 'sale.order'

    line_ids = fields.One2many('sale.order.line', 'order_id')
    amount_total = fields.Monetary(compute='_compute_amounts', store=True)

    @api.depends('line_ids.price_subtotal')
    def _compute_amounts(self):
        for order in self:
            order.amount_total = sum(order.line_ids.mapped('price_subtotal'))

# Line
class SaleOrderLine(models.Model):
    _name = 'sale.order.line'

    order_id = fields.Many2one('sale.order', required=True, ondelete='cascade')
    product_id = fields.Many2one('product.product', required=True)
    quantity = fields.Float(default=1.0)
    price_unit = fields.Float()
    price_subtotal = fields.Float(compute='_compute_subtotal', store=True)

    @api.depends('quantity', 'price_unit')
    def _compute_subtotal(self):
        for line in self:
            line.price_subtotal = line.quantity * line.price_unit
```

### 3. Sequence Number Pattern

```python
class LibraryLoan(models.Model):
    _name = 'library.loan'

    name = fields.Char(readonly=True, copy=False, default='New')

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', 'New') == 'New':
                vals['name'] = self.env['ir.sequence'].next_by_code('library.loan') or 'New'
        return super().create(vals_list)
```

### 4. Smart Button Pattern

```python
# Di model
class ResPartner(models.Model):
    _inherit = 'res.partner'

    loan_count = fields.Integer(compute='_compute_loan_count')

    def _compute_loan_count(self):
        loan_data = self.env['library.loan'].read_group(
            [('member_id.partner_id', 'in', self.ids)],
            ['member_id'],
            ['member_id'],
        )
        mapped = {d['member_id'][0]: d['member_id_count'] for d in loan_data}
        for partner in self:
            partner.loan_count = mapped.get(partner.id, 0)

    def action_view_loans(self):
        self.ensure_one()
        return {
            'name': 'Loans',
            'type': 'ir.actions.act_window',
            'res_model': 'library.loan',
            'view_mode': 'tree,form',
            'domain': [('member_id.partner_id', '=', self.id)],
            'context': {'default_member_id': self.id},
        }
```

```xml
<!-- Di view -->
<xpath expr="//div[@name='button_box']" position="inside">
    <button name="action_view_loans" type="object"
            class="oe_stat_button" icon="fa-book">
        <field name="loan_count" widget="statinfo" string="Loans"/>
    </button>
</xpath>
```

### 5. Domain Filter dari Context

```python
# Action yang membuka view dengan filter default
def action_view_overdue(self):
    return {
        'name': 'Overdue Loans',
        'type': 'ir.actions.act_window',
        'res_model': 'library.loan',
        'view_mode': 'tree,form',
        'domain': [('is_overdue', '=', True)],
        'context': {
            'search_default_group_member': 1,  # Auto-activate group by
            'default_state': 'active',          # Default value untuk form baru
        },
    }
```

### 6. Recordset Operations

```python
# Filter
active_loans = loan_ids.filtered(lambda l: l.state == 'active')
active_loans = loan_ids.filtered('is_active')  # shortcut untuk boolean

# Map
member_names = loan_ids.mapped('member_id.name')  # ['John', 'Jane', ...]
member_ids = loan_ids.mapped('member_id')          # recordset

# Sort
sorted_loans = loan_ids.sorted(key=lambda l: l.loan_date, reverse=True)
sorted_loans = loan_ids.sorted('loan_date', reverse=True)

# Set operations
all_books = set_a | set_b      # Union
common = set_a & set_b         # Intersection
only_a = set_a - set_b         # Difference

# Check existence
if loan.member_id:             # True jika ada relasi
    print(loan.member_id.name)

# Iterate
for loan in loans:
    print(loan.name)

# Slice (BUKAN query, di-slice di Python)
first_five = loans[:5]
```

### 7. Notification setelah Action

```python
def action_confirm(self):
    self.write({'state': 'confirmed'})

    # Notification kecil di pojok (toast)
    return {
        'type': 'ir.actions.client',
        'tag': 'display_notification',
        'params': {
            'title': 'Success',
            'message': f'{len(self)} loans confirmed.',
            'type': 'success',         # success, warning, danger, info
            'sticky': False,           # False = hilang otomatis
            'next': {'type': 'ir.actions.act_window_close'},
        },
    }
```

### 8. Conditional visibility di Odoo 18

```xml
<!-- Odoo 18: langsung pakai attribute, bukan attrs dict -->
<field name="price" invisible="state == 'draft'"/>
<field name="name" readonly="state != 'draft'"/>
<field name="partner_id" required="state == 'confirmed'"/>

<!-- Kondisi kompleks -->
<field name="discount"
       invisible="state == 'cancel' or not is_member"/>

<!-- Button conditional -->
<button name="action_confirm"
        string="Confirm"
        type="object"
        invisible="state != 'draft'"/>
```

**Odoo 18 vs Odoo <17:**
```xml
<!-- OLD (sebelum Odoo 17): pakai attrs dict -->
<field name="price" attrs="{'invisible': [('state', '=', 'draft')]}"/>

<!-- NEW (Odoo 17+): langsung di attribute -->
<field name="price" invisible="state == 'draft'"/>
```

---

## Anti-Patterns (Hindari!)

### 1. N+1 Query Problem

```python
# BAD: 1 query per record
for loan in loans:
    member = self.env['library.member'].search([('id', '=', loan.member_id.id)])
    print(member.name)

# GOOD: Odoo auto-prefetch
for loan in loans:
    print(loan.member_id.name)  # Odoo prefetch semua member dalam 1 query
```

### 2. Search di dalam Loop

```python
# BAD
for book in books:
    copies = self.env['library.book.copy'].search_count([('book_id', '=', book.id)])

# GOOD: read_group
copy_counts = self.env['library.book.copy'].read_group(
    [('book_id', 'in', books.ids)],
    ['book_id'],
    ['book_id'],
)
```

### 3. Sudo tanpa Alasan

```python
# BAD: bypass security tanpa alasan
books = self.env['library.book'].sudo().search([])

# GOOD: hanya sudo jika memang perlu bypass
# Contoh: cron job yang jalan sebagai system user
@api.model
def _cron_check_overdue(self):
    loans = self.sudo().search([('state', '=', 'active'), ('due_date', '<', today)])
```

### 4. Hardcode ID

```python
# BAD: hardcode database ID
category = self.env['library.book.category'].browse(1)

# GOOD: gunakan XML ID
category = self.env.ref('library_management.category_fiction')

# GOOD: atau search
category = self.env['library.book.category'].search([('name', '=', 'Fiction')], limit=1)
```

### 5. Commit di Tengah Method

```python
# BAD: commit manual (bisa corrupt data jika error setelahnya)
def action_process(self):
    for record in self:
        record.state = 'done'
        self.env.cr.commit()  # JANGAN!

# GOOD: biarkan Odoo handle transaction
def action_process(self):
    self.write({'state': 'done'})
    # Odoo auto-commit di akhir HTTP request
```

### 6. Create di dalam Compute

```python
# BAD: side effect di compute (create record baru)
@api.depends('line_ids')
def _compute_total(self):
    for rec in self:
        rec.total = sum(rec.line_ids.mapped('amount'))
        # JANGAN create/write record lain di sini!
        # self.env['library.log'].create({...})

# GOOD: compute hanya menghitung, side effect di action/write
```

---

## Checklist Sebelum Deploy Module

```
[ ] Semua model punya ir.model.access.csv
[ ] Semua field yang dipakai di view sudah didefinisikan di model
[ ] Semua XML ID yang direferensikan sudah ada
[ ] __manifest__.py: depends lengkap
[ ] __manifest__.py: data files urutan benar
[ ] __init__.py: semua module ter-import
[ ] Sequence sudah didefinisikan (jika pakai auto-number)
[ ] Test sudah jalan semua (--test-enable)
[ ] Tidak ada print() / breakpoint() yang tertinggal
[ ] Tidak ada sudo() yang tidak perlu
[ ] Tidak ada hardcode ID
[ ] Security groups sudah benar
[ ] Views sudah di-test di browser (form, tree, search)
[ ] Report PDF sudah di-test print
```

---

## Odoo 18 Perubahan dari Versi Sebelumnya

| Fitur | Odoo <= 16 | Odoo 17+ / 18 |
|-------|-----------|---------------|
| Visibility control | `attrs="{'invisible': [...]}"` | `invisible="expression"` |
| Readonly control | `attrs="{'readonly': [...]}"` | `readonly="expression"` |
| Required control | `attrs="{'required': [...]}"` | `required="expression"` |
| Create method | `@api.model def create(self, vals)` | `@api.model_create_multi def create(self, vals_list)` |
| Asset declaration | Template inherit | `assets` key di manifest |
| URL structure | `/web#action=...` | `/odoo/action-...` |
| JS framework | OWL 1.x | OWL 2.x |
| Form button | `states="draft"` | `invisible="state != 'draft'"` |
