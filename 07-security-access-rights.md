# Bab 7: Security & Access Rights

## ir.model.access.csv

File ini define access control untuk model.

```
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_library_book_user,library.book user,model_library_book,base.group_user,1,1,1,1
access_library_book_manager,library.book manager,model_library_book,library_app.library_manager,1,1,1,1
access_library_book_viewer,library.book viewer,model_library_book,library_app.library_viewer,1,0,0,0
```

Format kolom:

| Kolom | Fungsi |
|-------|--------|
| id | Unique identifier |
| name | Display name |
| model_id:id | Model reference (model_nama_model) |
| group_id:id | Group reference, kosong untuk global |
| perm_read | Create (1=yes, 0=no) |
| perm_write | Write/Update (1=yes, 0=no) |
| perm_create | Create new record (1=yes, 0=no) |
| perm_unlink | Delete record (1=yes, 0=no) |

## Record Rules

Record rules batasi records yang bisa diakses user.

```xml
<!-- security/ir.model.access.csv -->
<!-- Sudah ada di atas -->

<!-- security/ir_rule.xml -->
<data noupdate="1">
    <record id="library_book_rule_user" model="ir.rule">
        <field name="name">Library Book: User can only read</field>
        <field name="model_id" ref="model_library_book"/>
        <field name="domain_force">[('partner_id', '=', user.partner_id.id)]</field>
        <field name="groups" eval="[(4, ref('base.group_user'))]"/>
    </record>

    <record id="library_book_rule_manager" model="ir.rule">
        <field name="name">Library Book: Manager can do all</field>
        <field name="model_id" ref="model_library_book"/>
        <field name="domain_force">[(1, '=', 1)]</field>
        <field name="groups" eval="[(4, ref('library_app.library_manager'))]"/>
    </record>
</data>
```

**domain_force syntax:**

| Syntax | Fungsi |
|--------|--------|
| `[(1, '=', 1)]` | Allow all records |
| `[('field', '=', value)]` | Filter specific value |
| `[('field', 'in', user.ids)]` | Filter based on user |
| `[(0, '=', 1)]` | Deny all records |

## Groups

Define custom group di security/groups.xml.

```xml
<data>
    <record id="library_viewer" model="res.groups">
        <field name="name">Library / Viewer</field>
        <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
    </record>

    <record id="library_user" model="res.groups">
        <field name="name">Library / User</field>
        <field name="implied_ids" eval="[(4, ref('library_viewer'))]"/>
    </record>

    <record id="library_manager" model="res.groups">
        <field name="name">Library / Manager</field>
        <field name="implied_ids" eval="[(4, ref('library_user'))]"/>
    </record>
</data>
```

## Record Security dengan Python

```python
from odoo import models
from odoo.exceptions import AccessError, ValidationError

class LibraryBook(models.Model):
    _name = 'library.book'

    def write(self, vals):
        # Check permission
        if not self.user_has_groups('library_app.library_manager'):
            if 'price' in vals:
                raise AccessError('Only manager can change price!')
        return super().write(vals)

    @api.model
    def _check_general_access(self):
        if not self.user_has_groups('base.group_user'):
            raise AccessError('Access denied!')

    def unlink(self):
        if self.state == 'done':
            if not self.user_has_groups('library_app.library_manager'):
                raise ValidationError('Cannot delete done records!')
        return super().unlink()
```

## Field Access Rules

Set field-level security dengan attribute.

```python
class LibraryBook(models.Model):
    _name = 'library.book'

    name = fields.Char(groups='base.group_user')
    price = fields.Float(groups='library_app.library_manager')
    cost = fields.Float(groups='library_app.library_manager')
    
    internal_notes = fields.Text(
        groups='library_app.library_manager',
        help='Internal notes only visible to managers'
    )
```

## Menu Security

Tampilkan/hide menu berdasarkan group.

```xml
<menuitem id="menu_library_admin"
          name="Admin Settings"
          parent="menu_library_root"
          action="act_library_admin"
          groups="library_app.library_manager"/>
```

## Button Security

```xml
<form>
    <header>
        <button name="action_approve"
                string="Approve"
                class="btn-primary"
                type="object"
                groups="library_app.library_manager"/>
        
        <button name="action_delete"
                string="Delete"
                type="object"
                groups="base.group_system"/>
    </header>
</form>
```

## Record Rule untuk Active Records

```xml
<record id="library_book_active_rule" model="ir.rule">
    <field name="name">Library Book: User only see active</field>
    <field name="model_id" ref="model_library_book"/>
    <field name="domain_force">
        ['|', ('active', '=', True), ('partner_id', '=', user.partner_id.id)]
    </field>
    <field name="groups" eval="[(4, ref('base.group_user'))]"/>
</record>
```

## Super Admin Access

```python
# Bypass all security
def action_special(self):
    # Run as superuser
    return self.sudo().search([])
    
    # Or with specific user
    return self.with_user(self.env.ref('base.user_admin')).read(['name'])
```

## Access Wizard (Mengatur Access dari UI)

1. Activate developer mode
2. Settings > Users & Companies > Groups
3. Pilih group yang mau di-aturnya
4. Edit tab "Access Rights"

## Debug Access Issues

```python
# Check current user permissions
user = request.env.user
print(f"User: {user.name}")
print(f"Groups: {user.groups_id.mapped('name')}")
print(f"Has manager: {user.has_group('library_app.library_manager')}")

# Check model access
model = request.env['library.book']
print(f"Can read: {model.check_access_rights('read')}")
print(f"Can write: {model.check_access_rights('write')}")
```

## Complete security structure

```
library_app/
├── __manifest__.py
├── security/
│   ├── ir.model.access.csv
│   ├── ir.rule.xml
│   └── groups.xml
├── models/
│   └── book.py
└── views/
    └── views.xml
```

### security/ir.model.access.csv

```
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_library_book_user,library.book user,model_library_book,base.group_user,1,1,1,0
access_library_book_manager,library.book manager,model_library_book,library_app.library_manager,1,1,1,1
```

### security/groups.xml

```xml
<data>
    <record id="library_manager" model="res.groups">
        <field name="name">Library / Manager</field>
        <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
    </record>
</data>
```