# Bab 21: Internationalization (i18n) & Multi-Company

Topik ini sering dibutuhkan di proyek nyata tapi jarang diajarkan: bagaimana module Odoo diterjemahkan ke banyak bahasa, dan bagaimana data/behavior dipisahkan antar company dalam satu database (multi-company).

---

## Bagian 1: Internationalization (i18n)

### Membungkus String dengan `_()`

Semua teks yang ditampilkan ke user (label, pesan error, notifikasi) harus dibungkus fungsi `_()` agar bisa diterjemahkan.

```python
from odoo import models, fields, api
from odoo.exceptions import UserError
from odoo.tools.translate import _

class LibraryLoan(models.Model):
    _name = 'library.loan'

    def action_confirm(self):
        for loan in self:
            if loan.state != 'draft':
                # SELALU bungkus pesan error dengan _()
                raise UserError(_('Loan %(name)s sudah tidak dalam status draft.', name=loan.name))
            loan.state = 'active'
        # Pesan sukses juga dibungkus _()
        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {'message': _('Loan berhasil dikonfirmasi.')},
        }
```

> ⚠️ **Jangan** pakai f-string atau `.format()` di dalam `_()` — argumen harus lewat `%(name)s` placeholder seperti contoh di atas. Kalau pakai f-string, string hasil interpolasi berubah setiap kali dan Odoo tidak bisa mencocokkannya dengan entri terjemahan di file `.po`.

```python
# BAD — string sudah ter-interpolasi sebelum masuk _(), tidak bisa diterjemahkan dengan benar
raise UserError(_(f'Loan {loan.name} sudah tidak dalam status draft.'))

# GOOD
raise UserError(_('Loan %(name)s sudah tidak dalam status draft.', name=loan.name))
```

### String di Sisi JavaScript (OWL)

```javascript
import { _t } from "@web/core/l10n/translation";

class LoanWidget extends Component {
    static template = "library_management.LoanWidget";

    get confirmLabel() {
        return _t("Confirm Loan");
    }
}
```

### Menandai Field untuk Diterjemahkan

```python
class LibraryBookCategory(models.Model):
    _name = 'library.book.category'

    # translate=True: field ini punya nilai berbeda per bahasa
    name = fields.Char(string='Category Name', translate=True)
    description = fields.Text(translate=True)
```

### Struktur File Terjemahan

```
addons/library_management/
└── i18n/
    ├── library_management.pot   # Template — hasil ekstraksi semua string _()
    ├── id.po                    # Terjemahan Bahasa Indonesia
    ├── fr.po                    # Terjemahan Bahasa Perancis
    └── en_US.po                 # (opsional) override string default
```

### Generate / Update File `.pot` dan `.po`

```bash
# Export .pot (template) dari dalam container, modul harus sudah ter-install
docker compose exec odoo odoo \
    --i18n-export=/mnt/extra-addons/library_management/i18n/library_management.pot \
    --modules=library_management \
    -d odoo --stop-after-init

# Export terjemahan untuk bahasa tertentu (misal Indonesia)
docker compose exec odoo odoo \
    --i18n-export=/mnt/extra-addons/library_management/i18n/id.po \
    --language=id_ID \
    --modules=library_management \
    -d odoo --stop-after-init

# Import file .po yang sudah diterjemahkan ke database
docker compose exec odoo odoo \
    --i18n-import=/mnt/extra-addons/library_management/i18n/id.po \
    --language=id_ID \
    -d odoo --stop-after-init
```

File `.po` berisi pasangan `msgid` (string asli) dan `msgstr` (terjemahan):

```po
#. module: library_management
#: model:ir.model.fields,field_description:library_management.field_library_loan__state
msgid "Loan %(name)s sudah tidak dalam status draft."
msgstr "Loan %(name)s is no longer in draft status."
```

### Install Bahasa & Load Translation Otomatis

```bash
# Install bahasa baru lewat CLI
docker compose exec odoo odoo -d odoo --load-language=id_ID --stop-after-init
```

Atau lewat UI: **Settings > Translations > Languages > Add a Language**, lalu di setiap module, Odoo otomatis memuat file `i18n/<lang>.po` miliknya saat module di-install/upgrade — tidak perlu `--i18n-import` manual kalau filenya sudah ada di folder `i18n/` module.

### Terjemahan di Record Data (XML)

```xml
<!-- Views/field tertentu bisa punya atribut terjemahan langsung -->
<record id="view_loan_form" model="ir.ui.view">
    <field name="arch" type="xml">
        <form>
            <field name="name" string="Loan Reference"/>
        </form>
    </field>
</record>
```

String `string="Loan Reference"` otomatis masuk ke `.pot` saat export — tidak perlu perlakuan khusus.

### Checklist i18n

```
[ ] Semua UserError / ValidationError dibungkus _()
[ ] Semua notifikasi UI dibungkus _()
[ ] Tidak ada f-string / .format() di dalam _()
[ ] Field Char/Text yang kontennya bergantung bahasa pakai translate=True
[ ] File i18n/<module>.pot sudah di-generate ulang sebelum release
[ ] String di JS (OWL) pakai _t() dari @web/core/l10n/translation
```

---

## Bagian 2: Multi-Company

### Field `company_id`

```python
class LibraryLoan(models.Model):
    _name = 'library.loan'

    company_id = fields.Many2one(
        'res.company', string='Company', required=True,
        default=lambda self: self.env.company,
    )
```

> Hampir semua model transaksional (bukan master data global) sebaiknya punya `company_id` supaya data antar company bisa dipisah.

### Record Rule Multi-Company

```xml
<record id="rule_loan_multi_company" model="ir.rule">
    <field name="name">Library Loan: multi-company</field>
    <field name="model_id" ref="model_library_loan"/>
    <field name="domain_force">
        ['|', ('company_id', '=', False), ('company_id', 'in', company_ids)]
    </field>
</record>
```

`company_ids` di sini adalah variabel bawaan Odoo saat evaluasi record rule — berisi daftar company yang sedang aktif untuk user (lihat **Settings > Companies** pada user, bagian "Allowed Companies").

### Company-Dependent Fields

Field yang nilainya bisa berbeda per company meskipun record-nya sama (misalnya akun akuntansi default):

```python
class LibraryConfig(models.Model):
    _name = 'library.config'

    # company_dependent: setiap company punya nilai sendiri untuk field ini
    default_loan_days = fields.Integer(
        string='Default Loan Duration (days)',
        company_dependent=True,
        default=14,
    )
```

### Switch Company di Context

```python
# Baca/tulis data seolah berjalan sebagai company lain
loan_other_company = self.env['library.loan'].with_company(other_company).create({
    'member_id': member.id,
})

# Bedakan dengan with_context(allowed_company_ids=...) yang hanya mengubah
# company mana yang TAMPIL, bukan company default record baru.
```

### Inter-Company Rules

Untuk model yang datanya memang harus dibagi antar company (misalnya kategori buku global), **jangan** tambahkan `company_id`, biarkan `company_id = False` supaya record itu terlihat di semua company (lihat domain rule di atas yang punya kondisi `('company_id', '=', False)`).

### Checklist Multi-Company

```
[ ] Model transaksional punya company_id dengan default self.env.company
[ ] Record rule pakai pola ['|', ('company_id', '=', False), ('company_id', 'in', company_ids)]
[ ] Master data global (tanpa company_id) sengaja dibiarkan company_id=False
[ ] Setting yang beda per company pakai company_dependent=True, bukan company_id manual
[ ] Testing dilakukan dengan >= 2 company aktif untuk pastikan data tidak bocor antar company
```
