# Bab 11: QWeb Reports (PDF)

> **Tahap:** 3 Fitur Lanjutan | **Prasyarat:** Bab 4, 5, 10 | **Estimasi:** ± 3 jam | **Versi:** Odoo 18 (catatan Odoo 19)

Report di Odoo dibuat dari template QWeb yang di-render ke HTML, lalu dikonversi ke PDF oleh wkhtmltopdf. Di bab ini kita membuat report untuk model `library.loan` dari modul `library_management` (Bab 10).

## Tujuan Belajar

Setelah bab ini kamu bisa:

- Membuat report action (`ir.actions.report`) dan template QWeb untuk mencetak PDF dari sebuah record.
- Memakai directive QWeb dasar (`t-field`, `t-out`, `t-if`, `t-foreach`, `t-set`, `t-att-*`) di dalam report.
- Mengatur ukuran dan orientasi kertas lewat `report.paperformat`.
- Menyuplai data tambahan ke template dengan parser `AbstractModel`, dan memanggil report dari tombol Python.
- Mendiagnosis report kosong, CSS yang tidak muncul, dan masalah page break.

---

## 1. Struktur File Report

```
library_management/
├── report/
│   ├── __init__.py             # import loan_report (parser, bagian 6)
│   ├── report_paperformats.xml # ukuran kertas custom
│   ├── report_actions.xml      # action yang memicu report
│   └── report_templates.xml    # template QWeb
```

Tambahkan di `__manifest__.py`. Urutan penting: paperformat harus dimuat sebelum action yang merujuknya lewat `ref`.

```python
'data': [
    # ... security, data, views (lihat Bab 10)
    'report/report_paperformats.xml',
    'report/report_actions.xml',
    'report/report_templates.xml',
],
```

---

## 2. Report Action

```xml
<!-- report/report_actions.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Muncul di menu Print (ikon gear/Action) pada form dan list view -->
    <record id="action_report_loan_receipt" model="ir.actions.report">
        <field name="name">Loan Receipt</field>
        <field name="model">library.loan</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">library_management.report_loan_receipt</field>
        <field name="report_file">library_management.report_loan_receipt</field>
        <field name="print_report_name">'Loan Receipt - %s' % object.name</field>
        <field name="binding_model_id" ref="model_library_loan"/>
        <field name="binding_type">report</field>
    </record>
</odoo>
```

| Field | Fungsi |
|-------|--------|
| `report_type` | `qweb-pdf` (PDF) atau `qweb-html` (tampil di browser) |
| `report_name` | `<module>.<id template>`; harus cocok dengan `id` template QWeb |
| `report_file` | Biasanya diisi sama dengan `report_name` |
| `print_report_name` | Ekspresi Python untuk nama file PDF. Variabel `object` = record yang dicetak |
| `binding_model_id` | Model yang menampilkan report ini di menu Print |
| `binding_type` | `report` agar muncul di menu Print |
| `paperformat_id` | Ukuran kertas custom (bagian 5). Kosong = format default perusahaan |

Tanpa `binding_model_id`, report tetap bisa dipanggil dari kode (bagian 7), tapi tidak muncul di menu Print.

---

## 3. Template QWeb Report

```xml
<!-- report/report_templates.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <template id="report_loan_receipt">
        <!-- Wrapper HTML dasar -->
        <t t-call="web.html_container">
            <!-- docs = recordset yang dicetak; satu iterasi = satu dokumen -->
            <t t-foreach="docs" t-as="loan">
                <!-- Layout standar: header/footer perusahaan, nomor halaman -->
                <t t-call="web.external_layout">
                    <div class="page">
                        <h2 class="text-center">Loan Receipt</h2>
                        <h3 class="text-center text-muted">
                            <span t-field="loan.name"/>
                        </h3>

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

                        <div class="row mt-4">
                            <div class="col-6 offset-6 text-end">
                                <strong>Total Books: </strong>
                                <span t-field="loan.total_books"/>
                            </div>
                        </div>

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

- `docs` adalah recordset yang dicetak (1 atau banyak record); `doc_ids` adalah daftar ID-nya.
- `web.html_container` membungkus HTML dasar; `web.external_layout` menambahkan header/footer perusahaan.
- `<div class="page">` menandai area isi halaman.
- `t-field` merender field lengkap dengan format sesuai tipenya (tanggal, angka, selection).
- Memanggil `web.external_layout` di dalam loop `docs` membuat setiap record punya header/footer sendiri.

---

## 4. Directive QWeb yang Sering Dipakai

### Output data

```xml
<!-- t-field: render field dengan format/widget sesuai tipe field -->
<span t-field="loan.loan_date"/>
<span t-field="loan.loan_date" t-options='{"widget": "date", "format": "dd MMMM yyyy"}'/>

<!-- Monetary: display_currency wajib diberikan -->
<span t-field="fine.amount"
      t-options='{"widget": "monetary", "display_currency": env.company.currency_id}'/>

<!-- t-out: evaluasi ekspresi Python, hasilnya di-escape HTML (aman dari XSS) -->
<span t-out="loan.total_books"/>
<span t-out="'%.2f' % fine.amount"/>
```

**`t-out` vs `t-esc` vs `t-raw`:**

- `t-out` adalah directive yang dianjurkan dokumentasi: ia meng-escape HTML. Nilai bertipe `markupsafe.Markup` tidak di-escape.
- `t-esc` adalah nama lama untuk perilaku yang sama. Dokumentasi menandainya deprecated, tapi kode lama yang memakainya masih kamu temui. Untuk kode baru, tulis `t-out`.
- `t-raw` (output tanpa escape) deprecated sejak Odoo 15. Gantinya: `t-out` dengan nilai `Markup`.

`t-field` dan `t-out` beda tugas: `t-field` untuk field milik record (format otomatis sesuai tipe field), `t-out` untuk ekspresi bebas.

### Kondisional

```xml
<span t-if="loan.state == 'active' and not loan.is_overdue" class="text-success">Active</span>
<span t-elif="loan.is_overdue" class="text-danger">Overdue!</span>
<span t-else="">Other</span>
```

### Loop

```xml
<t t-foreach="loan.line_ids" t-as="line">
    <tr>
        <!-- Variabel otomatis: <nama>_index, _size, _first, _last, _odd, _even -->
        <td t-out="line_index"/>   <!-- 0-based -->
        <td t-out="line_first"/>   <!-- True jika item pertama -->
        <td t-out="line_last"/>    <!-- True jika item terakhir -->
    </tr>
</t>
```

Saat meng-iterasi dict, `<nama>_value` berisi nilainya. Variabel otomatis memakai nama dari `t-as` (di sini `line`).

### Variabel

```xml
<!-- t-set dengan ekspresi -->
<t t-set="total_lines" t-value="len(loan.line_ids)"/>
<span>Total: <t t-out="total_lines"/></span>

<!-- t-set dengan isi markup -->
<t t-set="title">Loan Receipt #<t t-out="loan.name"/></t>
```

### Atribut dinamis

```xml
<!-- t-att-<nama>: nilai atribut dari ekspresi Python -->
<div t-att-class="'alert alert-danger' if loan.is_overdue else 'alert alert-info'"/>

<!-- t-attf-<nama>: string template, sisipan ekspresi dengan {{ ... }} -->
<tr t-attf-class="row {{ 'table-danger' if loan.is_overdue else '' }}"/>
```

---

## 5. Custom Paper Format

`report.paperformat` mengatur ukuran, margin, dan orientasi. Letakkan di file yang dimuat sebelum action.

```xml
<!-- report/report_paperformats.xml -->
<odoo>
    <!-- Kartu anggota ukuran custom -->
    <record id="paperformat_member_card" model="report.paperformat">
        <field name="name">Member Card Format</field>
        <field name="format">custom</field>
        <field name="page_width">90</field>     <!-- mm -->
        <field name="page_height">55</field>    <!-- mm -->
        <field name="margin_top">5</field>
        <field name="margin_bottom">5</field>
        <field name="margin_left">5</field>
        <field name="margin_right">5</field>
        <field name="dpi">150</field>
    </record>

    <!-- A4 landscape untuk katalog -->
    <record id="paperformat_landscape_a4" model="report.paperformat">
        <field name="name">A4 Landscape</field>
        <field name="format">A4</field>
        <field name="orientation">Landscape</field>
        <field name="margin_top">20</field>
        <field name="margin_bottom">20</field>
        <field name="margin_left">10</field>
        <field name="margin_right">10</field>
    </record>
</odoo>
```

Hubungkan lewat `paperformat_id` di report action:

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
```

(Template `report_book_catalog` dibuat dengan pola yang sama seperti bagian 3.)

| Format | Ukuran |
|--------|--------|
| `A4` | 210 x 297 mm |
| `A5` | 148 x 210 mm |
| `Letter` | 216 x 279 mm |
| `Legal` | 216 x 356 mm |
| `custom` | Isi manual lewat `page_width` dan `page_height` (mm) |

---

## 6. Data Tambahan dengan Parser `AbstractModel`

Kalau template butuh data yang bukan field langsung dari record (statistik, agregasi), buat model abstrak sebagai parser.

```python
# report/loan_report.py
from odoo import api, models


class LoanStatisticsReport(models.AbstractModel):
    _name = 'report.library_management.report_loan_statistics'
    _description = 'Loan Statistics Report'

    @api.model
    def _get_report_values(self, docids, data=None):
        loans = self.env['library.loan'].browse(docids)

        total_fines = sum(
            self.env['library.fine'].search([
                ('loan_id', 'in', docids),
            ]).mapped('amount')
        )
        top_books = self.env['library.book'].search(
            [], order='total_copies desc', limit=5
        )

        return {
            'doc_ids': docids,
            'doc_model': 'library.loan',
            'docs': loans,
            'data': data,
            'total_fines': total_fines,
            'top_books': top_books,
            'company': self.env.company,
        }
```

Daftarkan di `report/__init__.py` (`from . import loan_report`) dan di `library_management/__init__.py` (`from . import report`).

**Aturan nama:** `_name` harus `report.<report_name>`, yaitu `report.library_management.report_loan_statistics` untuk `report_name = library_management.report_loan_statistics`. Odoo mencocokkan keduanya otomatis.

Action dan template-nya:

```xml
<record id="action_report_loan_statistics" model="ir.actions.report">
    <field name="name">Loan Statistics</field>
    <field name="model">library.loan</field>
    <field name="report_type">qweb-pdf</field>
    <field name="report_name">library_management.report_loan_statistics</field>
    <field name="report_file">library_management.report_loan_statistics</field>
</record>

<template id="report_loan_statistics">
    <t t-call="web.html_container">
        <t t-call="web.external_layout">
            <div class="page">
                <h2>Loan Statistics</h2>
                <p>Total Fines: <t t-out="total_fines"/></p>
                <h4>Books with Most Copies</h4>
                <t t-foreach="top_books" t-as="book">
                    <p><t t-out="book.name"/> - <t t-out="book.total_copies"/> copies</p>
                </t>
            </div>
        </t>
    </t>
</template>
```

---

## 7. Mencetak dari Python (Tombol)

```python
def action_print_receipt(self):
    return self.env.ref('library_management.action_report_loan_receipt').report_action(self)

# Dengan data tambahan; muncul di parser sebagai argumen `data`
def action_print_statistics(self):
    data = {'date_from': '2026-01-01', 'date_to': '2026-12-31'}
    return self.env.ref(
        'library_management.action_report_loan_statistics'
    ).report_action(self, data=data)
```

Untuk tombolnya, lihat `type="object"` di Bab 5.

---

## 8. Styling dan Bahasa

CSS khusus report boleh ditaruh di dalam template, dan class Bootstrap bawaan (`row`, `col-6`, `text-end`, `table`) bisa dipakai:

```xml
<style>
    .loan-header { background-color: #f8f9fa; padding: 15px; }
    table.loan-table th { background-color: #343a40; color: white; }
</style>
<div class="page">
    <div class="loan-header text-center">
        <span t-field="loan.name"/>
    </div>
</div>
```

Untuk mencetak dalam bahasa si anggota, bungkus isi dengan `with_context(lang=...)`:

```xml
<t t-set="loan" t-value="loan.with_context(lang=loan.member_id.partner_id.lang)"/>
```

Pola ini mengandalkan field `partner_id` pada `library.member`. Terjemahan string template dibahas di Bab 14.

---

## 9. Troubleshooting

**Report kosong atau blank**
- Pastikan `report_name` cocok dengan `id` template (format `modul.id_template`).
- Pastikan file XML sudah masuk di `data` pada manifest, lalu upgrade modul.
- Pastikan template memanggil `web.html_container` dan memakai `docs`.

**wkhtmltopdf error atau header/footer hilang**
```bash
wkhtmltopdf --version
```
Dokumentasi Odoo 18 menyebut wkhtmltopdf tidak diinstal lewat pip dan harus dipasang manual dalam versi 0.12.6 agar header dan footer didukung. Paket `wkhtmltopdf` dari repositori distro sering berbeda build, jadi periksa versinya. Image Docker resmi Odoo sudah membawa wkhtmltopdf (Bab 1).

**CSS tidak muncul**
- Mesin render PDF tidak mendukung semua CSS modern; flexbox dan grid sebaiknya dihindari. Pakai `table`, `float`, dan class Bootstrap bawaan.
- Hindari `position: fixed/absolute` di isi halaman.

**Page break**
```xml
<!-- Paksa halaman baru -->
<div style="page-break-before: always;"/>

<!-- Jaga blok tetap satu halaman -->
<div style="page-break-inside: avoid;">
    <!-- isi yang tidak boleh terpotong -->
</div>
```

---

> **Beda di Odoo 19:** Report action, template QWeb, `t-out`, dan paperformat di bab ini kami pakai apa adanya dan tidak kami temukan perubahan sintaks yang terverifikasi antara 18 dan 19. Kalau ragu, cek halaman Reports di dokumentasi 19 sebelum menyalin kode.

## Ringkasan

- Report = `ir.actions.report` (action) + `<template>` QWeb (isi); `report_name` harus cocok dengan id template.
- `binding_model_id` memunculkan report di menu Print; tanpa itu, panggil lewat `report_action()`.
- Kerangka template: `web.html_container`, loop `docs`, `web.external_layout`, lalu `<div class="page">`.
- Pakai `t-field` untuk field record dan `t-out` untuk ekspresi; `t-esc` dan `t-raw` sudah deprecated.
- Ukuran kertas diatur lewat `report.paperformat` yang dimuat sebelum action.
- Data tambahan datang dari model abstrak `report.<report_name>` dengan `_get_report_values`.

## Latihan

1. Buat report "Member Card" untuk `library.member` (nama, `member_number`, `membership_type`) dengan paperformat `paperformat_member_card`. Cetak dari menu Print di form anggota dan periksa nama file PDF-nya.
2. Tambahkan `print_report_name` ke report Loan Receipt agar nama file berbentuk `Loan Receipt - <nomor loan>.pdf`, lalu uji dengan mencetak dua loan sekaligus dari list view.
3. Buat parser `report.library_management.report_overdue_loans` yang mengirim daftar loan berstatus `active` dengan `due_date` lewat hari ini ke template, lalu tampilkan sebagai tabel.

## Lanjut ke

Bab 12: Controllers & Routing (`12-controllers-routing.md`).
