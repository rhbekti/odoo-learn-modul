# Bab 8: Wizards & Dialogs

## Apa itu Wizard?

Wizard adalah transient model yang collecting data dari user via popup dialog, lalu process data tersebut.

## Struktur Wizard

```
wizard_app/
├── models/
│   ├── __init__.py
│   └── wizard.py
├── views/
│   └── wizard_views.xml
└── wizard/
    └── __init__.py
```

## Transient Model

```python
from odoo import models, fields, api
from odoo.exceptions import UserError

class LibraryLoanWizard(models.TransientModel):
    _name = 'library.loan.wizard'
    _description = 'Loan Book Wizard'

    book_id = fields.Many2one('library.book', string='Book', required=True)
    partner_id = fields.Many2one('res.partner', string='Borrower', required=True)
    loan_days = fields.Integer(string='Loan Days', default=14, required=True)
    notes = fields.Text(string='Notes')

    @api.model
    def default_get(self, fields):
        res = super().default_get(fields)
        active_id = self._context.get('active_id')
        if active_id:
            res['book_id'] = active_id
        return res

    def action_confirm_loan(self):
        self.ensure_one()
        if not self.partner_id:
            raise UserError('Please select a borrower!')
        
        # Create loan record
        loan = self.env['library.loan'].create({
            'book_id': self.book_id.id,
            'partner_id': self.partner_id.id,
            'loan_days': self.loan_days,
            'notes': self.notes,
        })
        
        # Update book state
        self.book_id.write({'state': 'borrowed'})
        
        return {'type': 'ir.actions.act_window_close'}
```

## Wizard View (Dialog)

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

## Memanggil Wizard dari Button

```python
def action_loan_book(self):
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

# Di XML button
<button name="%(wizard_module_name.action_loan_wizard)d"
        string="Loan Book"
        type="action"/>
```

## Wizard dengan Multi Records

```python
class LibraryReturnWizard(models.TransientModel):
    _name = 'library.return.wizard'
    _description = 'Return Books Wizard'

    return_date = fields.Date(string='Return Date', required=True)
    penalty = fields.Float(string='Penalty Fee', default=0)

    def action_return_books(self):
        active_ids = self._context.get('active_ids', [])
        loans = self.env['library.loan'].browse(active_ids)
        
        for loan in loans:
            loan.write({
                'return_date': self.return_date,
                'penalty': self.penalty,
                'state': 'returned',
            })
            # Update book state
            loan.book_id.write({'state': 'available'})
        
        return {'type': 'ir.actions.act_window_close'}
```

## Wizard dengan Selection

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
        active_ids = self._context.get('active_ids', [])
        records = self.env['library.book'].browse(active_ids)
        
        if self.action_type == 'mark_available':
            records.write({'state': 'available'})
        elif self.action_type == 'mark_unavailable':
            records.write({'state': 'borrowed'})
        elif self.action_type == 'archive':
            records.write({'active': False})
        
        return {'type': 'ir.actions.act_window_close'}
```

## Wizard View dengan One2many

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
        for line in self.line_ids:
            self.env['library.book'].create({
                'name': line.name,
                'author': line.author,
                'isbn': line.isbn,
            })
        return {'type': 'ir.actions.act_window_close'}

class LibraryImportLineWizard(models.TransientModel):
    _name = 'library.import.line.wizard'
    _description = 'Import Line Wizard'

    wizard_id = fields.Many2one('library.import.wizard')
    name = fields.Char(string='Title', required=True)
    author = fields.Char(string='Author')
    isbn = fields.Char(string='ISBN')
```

```xml
<record id="view_library_import_wizard" model="ir.ui.view">
    <field name="name">library.import.wizard.form</field>
    <field name="model">library.import.wizard</field>
    <field name="arch" type="xml">
        <form string="Import Books">
            <group>
                <field name="line_ids">
                    <tree editable="bottom">
                        <field name="name"/>
                        <field name="author"/>
                        <field name="isbn"/>
                    </tree>
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

## Wizard dengan Confirmation Dialog

```python
class LibraryDeleteWizard(models.TransientModel):
    _name = 'library.delete.wizard'
    _description = 'Delete Confirmation Wizard'

    message = fields.Text(readonly=True)

    @api.model
    def default_get(self, fields):
        res = super().default_get(fields)
        active_ids = self._context.get('active_ids', [])
        count = len(active_ids)
        res['message'] = f'Are you sure you want to delete {count} book(s)?'
        return res

    def action_confirm_delete(self):
        active_ids = self._context.get('active_ids', [])
        records = self.env['library.book'].browse(active_ids)
        records.unlink()
        return {'type': 'ir.actions.act_window_close'}
```

## Multi-step Wizard

```python
class LibraryMultiStepWizard(models.TransientModel):
    _name = 'library.multistep.wizard'
    _description = 'Multi-step Wizard'

    step = fields.Integer(string='Step', default=1)
    name = fields.Char(string='Title')
    author = fields.Char(string='Author')
    category_id = fields.Many2one('library.category', string='Category')

    def next_step(self):
        self.write({'step': self.step + 1})
        return {'type': 'ir.actions.act_window_reload'}

    def prev_step(self):
        self.write({'step': self.step - 1})
        return {'type': 'ir.actions.act_window_reload'}

    def action_finish(self):
        self.env['library.book'].create({
            'name': self.name,
            'author': self.author,
            'category_id': self.category_id.id,
        })
        return {'type': 'ir.actions.act_window_close'}
```

## Redirect setelah Wizard

```python
def action_confirm_loan(self):
    self.ensure_one()
    
    loan = self.env['library.loan'].create({
        'book_id': self.book_id.id,
        'partner_id': self.partner_id.id,
    })
    
    # Redirect ke loan form
    return {
        'name': 'Loan',
        'type': 'ir.actions.act_window',
        'res_model': 'library.loan',
        'res_id': loan.id,
        'view_mode': 'form',
        'target': 'current',
    }
```

## Complete Wizard Structure

### models/wizard.py

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
    def default_get(self, fields):
        res = super().default_get(fields)
        active_id = self._context.get('active_id')
        if active_id:
            res['book_id'] = active_id
        return res

    def action_confirm_loan(self):
        self.ensure_one()
        if not self.partner_id:
            raise UserError('Please select a borrower!')
        
        self.env['library.loan'].create({
            'book_id': self.book_id.id,
            'partner_id': self.partner_id.id,
            'loan_days': self.loan_days,
        })
        
        self.book_id.write({'state': 'borrowed'})
        return {'type': 'ir.actions.act_window_close'}
```

### views/wizard_views.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data>
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
    </data>
</odoo>
```

### __manifest__.py data section

```python
'data': [
    'security/ir.model.access.csv',
    'views/wizard_views.xml',
],
```