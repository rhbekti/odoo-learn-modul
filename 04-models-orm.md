# Bab 4: Models & ORM

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
    states={'draft': [('readonly', False)]},
)
```

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

## Constraints

```python
# SQL constraint
_sql_constraints = [
    ('name_uniq', 'unique(name)', 'Name must be unique!'),
    ('price_positive', 'CHECK(price > 0)', 'Price must be positive!'),
]

# Python constraint
@api.constrains('date_to', 'date_from')
def _check_dates(self):
    for record in self:
        if record.date_to < record.date_from:
            raise ValidationError('End date must be after start date!')
```

## ORM Methods

```python
# Create
record = self.env['library.book'].create({
    'name': 'New Book',
    'price': 100.0,
})

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

## API Decorators

```python
@api.model          # Method tidak pakai recordset
@api.depends()      # Trigger recompute
@api.onchange()     # Trigger on UI change
@api.constrains()   # Validation constraint
@api.returns()      # Specify return model
@api.multi          # Default, recordset method

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

## Lifecycle Hooks

```python
class LibraryBook(models.Model):
    _name = 'library.book'

    @api.model
    def create(self, vals):
        # Before create
        vals['name'] = vals['name'].upper()
        record = super().create(vals)
        # After create
        return record

    def write(self, vals):
        # Before write
        result = super().write(vals)
        # After write
        return result

    def unlink(self):
        # Before delete
        return super().unlink()

    @api.model
    def search_read(self, domain=None, fields=None, offset=0, limit=None):
        return super().search_read(domain, fields, offset, limit)
```

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