# Bab 12: QWeb Reports (PDF)

Report di Odoo menggunakan QWeb template yang di-render ke HTML lalu dikonversi ke PDF menggunakan wkhtmltopdf.

## Struktur Report

```
library_management/
├── report/
│   ├── __init__.py           # (kosong, atau import parser)
│   ├── report_templates.xml  # QWeb template untuk layout report
│   └── report_actions.xml    # Action yang trigger report
```

Tambahkan di `__manifest__.py`:

```python
'data': [
    'report/report_actions.xml',
    'report/report_templates.xml',
],
```

---

## Report Action

```xml
<!-- report/report_actions.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Report action: muncul di menu Print pada form/tree view -->
    <record id="action_report_loan_receipt" model="ir.actions.report">
        <field name="name">Loan Receipt</field>
        <field name="model">library.loan</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">library_management.report_loan_receipt</field>
        <field name="report_file">library_management.report_loan_receipt</field>
        <field name="binding_model_id" ref="model_library_loan"/>
        <field name="binding_type">report</field>
    </record>

    <!-- Report yang bisa diakses dari tree view (multi-record) -->
    <record id="action_report_member_card" model="ir.actions.report">
        <field name="name">Member Card</field>
        <field name="model">library.member</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">library_management.report_member_card</field>
        <field name="report_file">library_management.report_member_card</field>
        <field name="binding_model_id" ref="model_library_member"/>
        <field name="binding_type">report</field>
        <field name="paperformat_id" ref="paperformat_member_card"/>
    </record>
</odoo>
```

**Field penting:**

| Field | Fungsi |
|-------|--------|
| `report_type` | `qweb-pdf` (PDF) atau `qweb-html` (browser) |
| `report_name` | Harus cocok dengan `t-name` di template |
| `binding_model_id` | Model yang bisa print report ini |
| `binding_type` | `report` (muncul di Print menu) |
| `paperformat_id` | Custom ukuran kertas |

---

## QWeb Template (Layout Report)

```xml
<!-- report/report_templates.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Template utama report -->
    <template id="report_loan_receipt">
        <!-- t-call layout standar Odoo: header, footer, page number -->
        <t t-call="web.html_container">
            <!-- Loop setiap record yang di-print -->
            <t t-foreach="docs" t-as="loan">
                <t t-call="web.external_layout">
                    <div class="page">
                        <!-- Judul -->
                        <h2 class="text-center">Loan Receipt</h2>
                        <h3 class="text-center text-muted">
                            <span t-field="loan.name"/>
                        </h3>

                        <!-- Info header -->
                        <div class="row mt-4">
                            <div class="col-6">
                                <strong>Member:</strong>
                                <span t-field="loan.member_id.name"/><br/>
                                <strong>Member No:</strong>
                                <span t-field="loan.member_id.member_number"/><br/>
                                <strong>Membership:</strong>
                                <span t-field="loan.membership_type"/>
                            </div>
                            <div class="col-6 text-end">
                                <strong>Loan Date:</strong>
                                <span t-field="loan.loan_date"/><br/>
                                <strong>Due Date:</strong>
                                <span t-field="loan.due_date"/><br/>
                                <strong>Status:</strong>
                                <span t-field="loan.state"/>
                            </div>
                        </div>

                        <!-- Tabel detail buku -->
                        <table class="table table-sm mt-4">
                            <thead>
                                <tr>
                                    <th>#</th>
                                    <th>Book Title</th>
                                    <th>Barcode</th>
                                    <th>Notes</th>
                                </tr>
                            </thead>
                            <tbody>
                                <t t-foreach="loan.line_ids" t-as="line">
                                    <tr>
                                        <td><t t-out="line_index + 1"/></td>
                                        <td><span t-field="line.book_title"/></td>
                                        <td><span t-field="line.barcode"/></td>
                                        <td><span t-field="line.notes"/></td>
                                    </tr>
                                </t>
                            </tbody>
                        </table>

                        <!-- Summary -->
                        <div class="row mt-4">
                            <div class="col-6 offset-6 text-end">
                                <strong>Total Books: </strong>
                                <span t-field="loan.total_books"/>
                            </div>
                        </div>

                        <!-- Tanda tangan -->
                        <div class="row mt-5">
                            <div class="col-6 text-center">
                                <p>____________________</p>
                                <p>Librarian</p>
                            </div>
                            <div class="col-6 text-center">
                                <p>____________________</p>
                                <p><span t-field="loan.member_id.name"/></p>
                            </div>
                        </div>
                    </div>
                </t>
            </t>
        </t>
    </template>
</odoo>
```

**Konsep penting:**
- `docs` — recordset yang di-print (bisa 1 atau banyak record)
- `t-call="web.html_container"` — wrapper HTML dasar
- `t-call="web.external_layout"` — layout dengan header/footer perusahaan
- `t-field` — render field dengan formatting otomatis (tanggal, angka, dll)
- `t-out` — output value Python langsung (untuk ekspresi)
- Setiap iterasi `docs` menghasilkan **halaman baru** di PDF

---

## QWeb Directives Lengkap

### Output Data

```xml
<!-- t-field: render field dengan widget/format otomatis -->
<span t-field="loan.loan_date"/>
<span t-field="loan.loan_date" t-options='{"widget": "date", "format": "dd MMMM yyyy"}'/>

<!-- t-field dengan monetary widget -->
<span t-field="fine.amount" t-options='{"widget": "monetary", "display_currency": fine.currency_id}'/>

<!-- t-out: render ekspresi Python (raw output) -->
<span t-out="loan.total_books"/>
<span t-out="'%.2f' % loan.amount"/>

<!-- t-esc: sama seperti t-out tapi HTML-escaped (aman dari XSS) -->
<span t-esc="loan.member_id.name"/>
```

### Kondisional

```xml
<!-- t-if / t-elif / t-else -->
<span t-if="loan.state == 'active'" class="text-success">Active</span>
<span t-elif="loan.state == 'overdue'" class="text-danger">Overdue!</span>
<span t-else="">Other</span>

<!-- Pada attribute -->
<tr t-att-class="'table-danger' if line.is_overdue else ''">
```

### Loop

```xml
<!-- t-foreach / t-as -->
<t t-foreach="loan.line_ids" t-as="line">
    <tr>
        <!-- Variabel otomatis: -->
        <td t-out="line_index"/>      <!-- index (0-based) -->
        <td t-out="line_size"/>       <!-- total items -->
        <td t-out="line_first"/>      <!-- True jika item pertama -->
        <td t-out="line_last"/>       <!-- True jika item terakhir -->
        <td t-out="line_odd"/>        <!-- True jika index ganjil -->
        <td t-out="line_even"/>       <!-- True jika index genap -->
        <td t-out="line_value"/>      <!-- value jika iterasi dict -->
    </tr>
</t>
```

### Set Variable

```xml
<!-- t-set: define variable -->
<t t-set="total" t-value="sum(line.amount for line in loan.line_ids)"/>
<span>Total: <t t-out="total"/></span>

<!-- String value -->
<t t-set="title">Loan Receipt #<t t-out="loan.name"/></t>
```

### Dynamic Attributes

```xml
<!-- t-att-{name}: set attribute dinamis -->
<div t-att-class="'alert alert-danger' if loan.is_overdue else 'alert alert-info'"/>
<img t-att-src="'/web/image/library.book/%d/cover_image' % book.id"/>

<!-- t-attf-{name}: format string untuk attribute -->
<div t-attf-class="row #{loan.state == 'overdue' and 'bg-danger' or ''}"/>
```

---

## Custom Paper Format

```xml
<record id="paperformat_member_card" model="report.paperformat">
    <field name="name">Member Card Format</field>
    <field name="format">custom</field>
    <field name="page_width">90</field>     <!-- mm -->
    <field name="page_height">55</field>    <!-- mm -->
    <field name="margin_top">5</field>
    <field name="margin_bottom">5</field>
    <field name="margin_left">5</field>
    <field name="margin_right">5</field>
    <field name="orientation">Landscape</field>
    <field name="dpi">150</field>
</record>
```

**Format standar:**

| Format | Ukuran |
|--------|--------|
| `A4` | 210 x 297 mm (default) |
| `A5` | 148 x 210 mm |
| `Letter` | 216 x 279 mm |
| `Legal` | 216 x 356 mm |
| `custom` | Set manual via `page_width` & `page_height` |

---

## Report dengan Custom Data (AbstractModel Parser)

Ketika butuh data yang tidak langsung dari record (statistik, aggregasi, dll).

```python
# report/loan_report.py
from odoo import api, models

class LoanStatisticsReport(models.AbstractModel):
    _name = 'report.library_management.report_loan_statistics'
    _description = 'Loan Statistics Report'

    @api.model
    def _get_report_values(self, docids, data=None):
        loans = self.env['library.loan'].browse(docids)

        # Hitung statistik
        total_fines = sum(
            self.env['library.fine'].search([
                ('loan_id', 'in', docids),
            ]).mapped('amount')
        )

        most_borrowed = self.env['library.book'].search(
            [], order='total_copies desc', limit=5
        )

        return {
            'doc_ids': docids,
            'doc_model': 'library.loan',
            'docs': loans,
            'total_fines': total_fines,
            'most_borrowed': most_borrowed,
            'company': self.env.company,
        }
```

**Penting:** Nama `_name` harus `report.<module_name>.<template_id>` — Odoo mencocokkan ini secara otomatis dengan `report_name` di action.

Lalu di template bisa pakai variabel custom:

```xml
<template id="report_loan_statistics">
    <t t-call="web.html_container">
        <t t-call="web.external_layout">
            <div class="page">
                <h2>Loan Statistics</h2>
                <p>Total Fines: <t t-out="total_fines"/></p>
                <h4>Most Borrowed Books</h4>
                <t t-foreach="most_borrowed" t-as="book">
                    <p><t t-out="book.name"/> - <t t-out="book.total_copies"/> copies</p>
                </t>
            </div>
        </t>
    </t>
</template>
```

---

## Print Report dari Python (Button)

```python
def action_print_receipt(self):
    return self.env.ref('library_management.action_report_loan_receipt').report_action(self)

# Print dengan data tambahan
def action_print_statistics(self):
    data = {
        'date_from': '2026-01-01',
        'date_to': '2026-12-31',
    }
    return self.env.ref(
        'library_management.action_report_loan_statistics'
    ).report_action(self, data=data)
```

---

## Styling Report dengan CSS

```xml
<template id="report_loan_receipt">
    <t t-call="web.html_container">
        <t t-foreach="docs" t-as="loan">
            <t t-call="web.external_layout">
                <!-- CSS khusus report -->
                <style>
                    .loan-header { background-color: #f8f9fa; padding: 15px; }
                    .loan-title { font-size: 24px; font-weight: bold; }
                    .overdue-badge { color: red; font-weight: bold; }
                    table.loan-table th { background-color: #343a40; color: white; }
                </style>

                <div class="page">
                    <div class="loan-header text-center">
                        <span class="loan-title" t-field="loan.name"/>
                    </div>
                    <!-- ... -->
                </div>
            </t>
        </t>
    </t>
</template>
```

---

## Report Landscape

```xml
<record id="action_report_book_catalog" model="ir.actions.report">
    <field name="name">Book Catalog</field>
    <field name="model">library.book</field>
    <field name="report_type">qweb-pdf</field>
    <field name="report_name">library_management.report_book_catalog</field>
    <field name="report_file">library_management.report_book_catalog</field>
    <field name="binding_model_id" ref="model_library_book"/>
    <field name="binding_type">report</field>
    <field name="paperformat_id" ref="paperformat_landscape_a4"/>
</record>

<record id="paperformat_landscape_a4" model="report.paperformat">
    <field name="name">A4 Landscape</field>
    <field name="format">A4</field>
    <field name="orientation">Landscape</field>
    <field name="margin_top">20</field>
    <field name="margin_bottom">20</field>
    <field name="margin_left">10</field>
    <field name="margin_right">10</field>
</record>
```

---

## Troubleshooting Report

**Report kosong / blank:**
- Pastikan `report_name` di action cocok dengan `t-name` (atau `id`) di template
- Pastikan file XML sudah masuk di `__manifest__.py` `data`

**wkhtmltopdf error:**
```bash
# Cek versi (harus 0.12.6+)
wkhtmltopdf --version

# Install di Docker
apt-get install -y wkhtmltopdf
```

**CSS tidak muncul:**
- Report PDF tidak support semua CSS (no flexbox, limited grid)
- Gunakan `float`, `table`, dan Bootstrap classes
- Hindari `position: fixed/absolute` di body content

**Page break:**
```xml
<!-- Force page break sebelum element -->
<div style="page-break-before: always;"/>

<!-- Hindari page break di tengah element -->
<div style="page-break-inside: avoid;">
    <!-- content yang harus tetap satu halaman -->
</div>
```
