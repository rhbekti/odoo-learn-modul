# Bab 14: Internationalization (i18n) & Multi-Company

> **Tahap:** 3 Fitur Lanjutan | **Prasyarat:** Bab 4, 6, 13 | **Estimasi:** ± 3 jam | **Versi:** Odoo 18 (catatan Odoo 19)

Topik ini sering dibutuhkan di proyek nyata tapi jarang diajarkan: bagaimana module Odoo diterjemahkan ke banyak bahasa, dan bagaimana data/behavior dipisahkan antar company dalam satu database (multi-company). Contoh memakai module `library_management` dari Bab 10.

## Tujuan Belajar

Setelah bab ini kamu bisa:

- Membungkus string Python dan JavaScript dengan `_()` / `_t()` supaya bisa diterjemahkan.
- Menandai field dengan `translate=True` dan memahami di mana terjemahannya disimpan.
- Meng-export `.pot`/`.po` dan meng-import terjemahan lewat CLI.
- Menambahkan `company_id`, record rule multi-company, dan field `company_dependent` pada model.
- Membedakan rule global vs per-group dan variabel eval rule (`company_id`, `company_ids`, `user`, `time`).
- Memakai `_check_company_auto` dan `check_company=True` agar relasi tidak lintas company.
- Memakai `with_company()` dengan benar dan menguji isolasi data antar company (satu vs banyak company).
- Menjelaskan inter-company transactions dan bedanya dengan record rule, serta mengaktifkannya lewat UI.

---

## Bagian 1: Internationalization (i18n)

### Aturan Dasar: Tulis Sumber dalam Bahasa Inggris

Konvensi Odoo: string di kode (Python, XML, JS) ditulis dalam bahasa Inggris. Bahasa lain (termasuk Indonesia) disediakan lewat file `.po`. Itu sebabnya contoh di bab ini memakai string sumber berbahasa Inggris.

### Membungkus String Python dengan `_()`

Semua teks yang ditampilkan ke user (pesan error, notifikasi) harus dibungkus `_()` agar bisa diterjemahkan.

```python
from odoo import models, _
from odoo.exceptions import UserError

class LibraryLoan(models.Model):
    _inherit = 'library.loan'

    def action_confirm(self):
        for loan in self:
            if loan.state != 'draft':
                # Pesan error dibungkus _(); argumen lewat placeholder %(name)s
                raise UserError(_('Loan %(name)s is no longer in draft.', name=loan.name))
            loan.state = 'active'
        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {'message': _('Loan confirmed successfully.')},
        }
```

> **Jangan** pakai f-string atau `.format()` di dalam `_()`. Odoo mengekstrak string literal saat export; string yang sudah ter-interpolasi bukan literal dan tidak akan cocok dengan entri di `.po`.

```python
# BAD: string sudah ter-interpolasi sebelum masuk _()
raise UserError(_(f'Loan {loan.name} is no longer in draft.'))

# GOOD
raise UserError(_('Loan %(name)s is no longer in draft.', name=loan.name))
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

Template OWL (XML) otomatis ikut diekstrak untuk teks statis; `_t()` dipakai untuk string yang dibuat di kode JS.

### Field yang Diterjemahkan: `translate=True`

```python
class LibraryBookCategory(models.Model):
    _name = 'library.book.category'

    # translate=True: field ini punya nilai berbeda per bahasa
    name = fields.Char(string='Category Name', translate=True)
    description = fields.Text(translate=True)
```

Catatan penyimpanan: sejak Odoo 16, tabel `ir.translation` sudah dihapus. Terjemahan field disimpan langsung di kolom field itu sendiri (tipe `jsonb`, satu key per bahasa), sedangkan terjemahan string kode/view dibaca dari file `.po` module. Jadi tidak ada lagi query ke `ir.translation`.

### Struktur File Terjemahan

```
addons/library_management/
└── i18n/
    ├── library_management.pot   # Template: hasil ekstraksi semua string
    ├── id.po                    # Terjemahan Bahasa Indonesia
    └── fr.po                    # Terjemahan Bahasa Perancis
```

File `.po` berisi pasangan `msgid` (string asli) dan `msgstr` (terjemahan):

```po
#. module: library_management
#: code:addons/library_management/models/library_loan.py:0
msgid "Loan %(name)s is no longer in draft."
msgstr "Loan %(name)s sudah tidak berstatus draft."
```

### Export `.pot` dan `.po`

Modul harus sudah ter-install di database. Path `/mnt/extra-addons` mengikuti setup Docker di Bab 1; sesuaikan dengan mount milikmu.

```bash
# Export .pot (template, tanpa bahasa)
docker compose exec odoo odoo \
    --i18n-export=/mnt/extra-addons/library_management/i18n/library_management.pot \
    --modules=library_management \
    -d odoo --stop-after-init

# Export terjemahan untuk satu bahasa (misal Indonesia); bahasa harus sudah ter-install
docker compose exec odoo odoo \
    --i18n-export=/mnt/extra-addons/library_management/i18n/id.po \
    --modules=library_management \
    -l id_ID \
    -d odoo --stop-after-init
```

### Import `.po`

```bash
# Import file .po ke database (timpa terjemahan yang sudah ada dengan --i18n-overwrite)
docker compose exec odoo odoo \
    --i18n-import=/mnt/extra-addons/library_management/i18n/id.po \
    -l id_ID \
    --i18n-overwrite \
    -d odoo --stop-after-init
```

### Install Bahasa & Load Otomatis

```bash
# Install bahasa baru lewat CLI
docker compose exec odoo odoo -d odoo --load-language=id_ID --stop-after-init
```

Atau lewat UI: **Settings > Translations > Languages > Add a Language**. Untuk bahasa yang sudah ter-install, Odoo otomatis memuat `i18n/<lang>.po` milik tiap module saat module di-install atau di-upgrade (`-u`). `--i18n-import` manual hanya perlu kalau mau memuat ulang tanpa upgrade.

### Apa yang Otomatis Ikut Ter-export

Tidak perlu `_()` untuk teks di XML. Atribut seperti `string="Loan Reference"` di view, label field (`string=` di Python), dan nilai field `translate=True` pada record data (misalnya `name` menu) ikut masuk ke `.pot` secara otomatis. `_()` hanya dibutuhkan untuk string di kode Python.

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

### Gambaran: Tiga Lapis Isolasi

Multi-company di Odoo bukan satu fitur, melainkan tiga mekanisme yang bekerja bersama:

| Lapis | Pertanyaan | Mekanisme |
|-------|------------|-----------|
| Visibilitas | Record company mana yang boleh terlihat? | Field `company_id` + record rule (`ir.rule`) |
| Konsistensi | Apakah relasi antar record tidak lintas company? | `_check_company_auto` + `check_company=True` |
| Nilai per company | Apakah satu setting bisa beda per company? | `company_dependent=True` |

Ditambah satu hal di luar ketiganya: **inter-company transactions** (dokumen di satu company otomatis membuat dokumen pasangan di company lain), dibahas di akhir bagian ini.

### Field `company_id`

Tambahkan `company_id` pada model transaksional `library.loan`. Pada `library.member`, ada catatan khusus karena model itu memakai `_inherits` (lihat bawah).

```python
class LibraryLoan(models.Model):
    _name = 'library.loan'
    # ... field lain dari Bab 10 tidak berubah

    company_id = fields.Many2one(
        'res.company', string='Company', required=True,
        default=lambda self: self.env.company,
    )
```

Tambahkan juga ke form view `view_library_loan_form` (Bab 10), di dekat `member_id`. Atribut `groups="base.group_multi_company"` menyembunyikan field ini kalau database hanya punya satu company:

```xml
<field name="member_id"/>
<field name="company_id" groups="base.group_multi_company"/>
```

`self.env.company` adalah company yang sedang aktif di company switcher (company paling atas yang dicentang).

**Kasus `library.member`.** Model ini memakai `_inherits = {'res.partner': 'partner_id'}`, sehingga field `company_id` milik `res.partner` sudah ikut terwarisi dan bisa dipakai di domain rule, tanpa kamu menulis field baru. Nilainya tidak otomatis `self.env.company`: kalau dikosongkan, member dianggap global (terlihat di semua company). Itu sering memang yang diinginkan untuk keanggotaan lintas cabang. Kalau ingin member terkunci per company, isi `company_id` saat membuat member (mis. lewat `default_company_id` di context action atau di view). Menimpa field itu dengan definisi baru di `library.member` mungkin saja, tetapi hindari kecuali kamu paham dampaknya pada partner di baliknya.

### Record Rule Multi-Company

```xml
<!-- security/ir_rule.xml -->
<odoo>
    <data noupdate="1">
        <record id="rule_loan_multi_company" model="ir.rule">
            <field name="name">Library Loan: multi-company</field>
            <field name="model_id" ref="model_library_loan"/>
            <field name="domain_force">
                ['|', ('company_id', '=', False), ('company_id', 'in', company_ids)]
            </field>
        </record>

        <record id="rule_member_multi_company" model="ir.rule">
            <field name="name">Library Member: multi-company</field>
            <field name="model_id" ref="model_library_member"/>
            <field name="domain_force">
                ['|', ('company_id', '=', False), ('company_id', 'in', company_ids)]
            </field>
        </record>
    </data>
</odoo>
```

Karena tidak ada field `groups`, kedua rule ini bersifat global dan berlaku untuk semua user, termasuk Manager. Ingat dari Bab 6: rule dalam `noupdate="1"` tidak ter-update saat upgrade, jadi kalau kamu mengubah `domain_force` di database yang sudah ada, ubah juga lewat UI atau pakai teknik di Bab 7.

**Variabel yang tersedia saat evaluasi `domain_force`** (terverifikasi di `ir.rule._eval_context()`, kode 18.0, dan dokumentasi security 18.0):

| Variabel | Isi |
|----------|-----|
| `user` | user saat ini, sebagai recordset singleton |
| `company_id` | id company aktif (satu integer, bukan recordset) |
| `company_ids` | list id company yang sedang diaktifkan di company switcher (`env.companies.ids`) |
| `time` | modul `time` milik Python |

Perhatikan bahwa `company_ids` di rule berarti company yang **dicentang** di switcher, bukan semua company yang diizinkan untuk user. Docstring `_eval_context` di kode sumber menyebut itu secara eksplisit, sedangkan kalimat di halaman dokumentasi security 18.0 ("all the companies to which the current user has access") lebih longgar dan bisa menyesatkan. Kalau yang kamu butuhkan adalah semua company yang diizinkan, pakai `user.company_ids.ids`, yaitu tab "Allowed Companies" di form user.

### Rule Global vs Rule Per-Group

Cara Odoo menggabungkan rule (dari `ir.rule._compute_domain`, kode 18.0):

- Rule **global** (field `groups` kosong) digabung dengan **AND**. Semua rule global harus terpenuhi.
- Rule **per-group** yang cocok dengan group user digabung dengan **OR** satu sama lain, lalu hasilnya di-AND dengan semua rule global.

Akibat praktisnya: rule multi-company sebaiknya dibuat **global**. Rule per-group hanya boleh memperluas akses di dalam batas yang sudah ditetapkan rule global, bukan melompati batas itu.

```
akses akhir = (global_1 AND global_2 AND ...) AND (group_a OR group_b OR ...)
```

Contoh dengan rule dari Bab 6 (user hanya melihat data miliknya, manager melihat semua `[(1, '=', 1)]`):

- Manager di company A memakai rule manager (`(1, '=', 1)`) dan tetap terkena rule multi-company global, jadi ia tidak melihat loan company B walau rule manager "boleh semuanya".
- Kalau kamu membuat rule multi-company **per-group** untuk `group_library_user`, lalu Manager punya rule per-group lain tanpa filter company, hasil OR membuat Manager melihat lintas company. Itu bug yang halus; hindari dengan menjadikan rule multi-company global.

### Data Global (Tanpa Company)

Untuk data yang memang dibagi ke semua company (misalnya kategori buku global), biarkan `company_id` kosong (`False`); record itu terlihat di semua company berkat kondisi `('company_id', '=', False)` di rule di atas. Konsekuensinya, field `company_id` pada model seperti ini jangan `required=True`. Pada `library.loan` di atas kita memakai `required=True`, jadi kondisi `False` di rule tidak pernah terpakai untuk loan, tetapi tetap berguna untuk `library.member` (company boleh kosong) dan menjaga pola rule tetap seragam.

### Menjaga Konsistensi Relasi: `_check_company_auto` dan `check_company`

Record rule hanya membatasi apa yang **terlihat**. Rule tidak mencegah loan company A menunjuk ke member milik company B, kalau user punya akses ke keduanya. Untuk itu Odoo menyediakan dua pengaturan yang bekerja berpasangan.

```python
class LibraryLoan(models.Model):
    _name = 'library.loan'
    _check_company_auto = True   # validasi konsistensi company saat create/write

    company_id = fields.Many2one(
        'res.company', string='Company', required=True,
        default=lambda self: self.env.company,
    )
    member_id = fields.Many2one(
        'library.member',
        string='Member',
        required=True,
        tracking=True,
        check_company=True,      # member harus company yang sama dengan loan (atau tanpa company)
    )
```

Perilaku yang terverifikasi di `odoo/models.py` dan `odoo/fields.py` (18.0):

1. `_check_company_auto = True` membuat `create()` dan `write()` memanggil `_check_company()`. Saat `write`, pengecekan hanya dijalankan kalau field yang ditulis adalah `company_id` atau relasi ber-`check_company=True`.
2. `_check_company()` memeriksa setiap field relasi yang ber-`check_company=True`: record tujuannya harus ber-`company_id` sama dengan record asal atau kosong (`False`). Domain yang dipakai: `[('company_id', 'in', <company record> + [False])]`. Kalau tidak cocok, Odoo melempar `UserError` berisi "Incompatible companies on records".
3. `check_company=True` pada field juga menambahkan **domain otomatis** di UI (`_description_domain`): dropdown `member_id` hanya menawarkan member milik company loan tersebut atau yang tanpa company. Jadi user jarang sampai memicu error karena pilihan salahnya memang tidak ditampilkan.
4. Model yang punya field `check_company=True` harus punya `company_id` (atau `company_ids`); kalau tidak, Odoo hanya menulis warning di log dan melewatkan pengecekan.
5. Model tujuan relasi (di sini `library.member`) juga harus punya `company_id`, karena domain di atas memfilter field itu. Jangan pasang `check_company=True` ke model tujuan yang tidak punya `company_id`.

Satu catatan: kalau `company_id` pada loan diubah setelah ada `line_ids`, pengecekan hanya meliputi field relasi di loan itu sendiri. Relasi di `library.loan.line` (mis. `copy_id`) baru dicek kalau model line juga `_check_company_auto = True` dan punya `company_id`. Cara termudah: tambahkan `company_id = fields.Many2one(related='loan_id.company_id', store=True)` di line, lalu pakai rule global yang sama.

### Menguji Isolasi Data

Skenario uji minimal: buat dua company (mis. "Cabang A" dan "Cabang B") dan tiga user.

| User | Allowed Companies | Yang diharapkan |
|------|-------------------|-----------------|
| `user_a` | hanya Cabang A | hanya melihat loan Cabang A; company switcher tidak muncul |
| `user_b` | hanya Cabang B | hanya melihat loan Cabang B |
| `user_ab` | A dan B | switcher muncul; yang terlihat mengikuti centang di switcher |

Langkah uji:

1. Login sebagai `user_ab`, aktifkan hanya Cabang A di switcher, buat loan. Pastikan `company_id` terisi Cabang A secara otomatis.
2. Aktifkan hanya Cabang B, pastikan loan tadi tidak terlihat. Centang keduanya, loan itu terlihat lagi (karena `company_ids` berisi keduanya).
3. Coba pilih member milik Cabang B di loan Cabang A. Dropdown seharusnya tidak menawarkannya; kalau dipaksa lewat kode atau import, muncul error "Incompatible companies on records".
4. Login sebagai `user_a`, buka URL record loan Cabang B secara langsung. Hasil yang benar: pesan access error, bukan datanya.

Uji otomatis di kode (pola `TransactionCase` dengan `with_user` dan `with_context(allowed_company_ids=...)`):

```python
def test_loan_isolated_by_company(self):
    loan_a = self.env['library.loan'].with_company(self.company_a).create({...})
    user = self.user_a  # hanya allowed company A
    visible = self.env['library.loan'].with_user(user).search([])
    self.assertNotIn(loan_b, visible)
```

### Inter-Company Rules (Transaksi Antar Company)

Jangan campur dengan record rule. Perbedaannya:

| | Record rule (`ir.rule`) | Inter-company transactions |
|---|---|---|
| Tujuan | Membatasi record mana yang bisa diakses | Membuat dokumen pasangan di company lain |
| Contoh | User Cabang A tidak melihat loan Cabang B | Faktur penjualan di Company A otomatis membuat vendor bill di Company B |
| Dikonfigurasi di | `security/ir_rule.xml` (kode) | Settings (UI), per company |
| Berlaku untuk model | Model apa saja | Dokumen penjualan, pembelian, dan akuntansi |

Konsep menurut dokumentasi resmi Odoo 18 (halaman Multi-company): satu company dalam database bisa menjual atau membeli barang/jasa ke company lain dalam database yang sama, dan dokumen pasangannya dibuat serta disinkronkan otomatis. Cara mengaktifkan di UI:

1. Pilih company terkait di company selector.
2. Buka **Settings**, bagian **Companies**, aktifkan **Inter-Company Transactions**, lalu Save.
3. Pilih opsi pasangan untuk company tersebut: **Generate Bills and Refunds** (invoice/credit note terkonfirmasi membuat bill/refund), **Generate Sales Orders** (sales order terkonfirmasi di company lawan membuat quotation), atau **Generate Purchase Orders** (purchase order terkonfirmasi membuat RFQ, memakai warehouse yang dipilih di **Use Warehouse**). Opsi **Create and validate** membuat dokumen yang langsung tervalidasi, bukan draft.

Syarat dari dokumentasi: produk harus dibagi (shared) antar company yang terlibat, dan fiscal position serta lokalisasi harus dikonfigurasi benar.

**Batas pembahasan di sini.** Detail implementasinya sengaja tidak dibahas: nama modul teknis, field di `res.company`, dan method yang bisa di-override belum bisa diverifikasi dari sumber yang kami akses. Halaman dokumentasi 18.0 tidak menyebut nama modul, dan manifest dengan nama-nama yang lazim ditebak (`account_inter_company_rules`, `sale_purchase_inter_company_rules`, `inter_company_rules`) tidak ditemukan di repo komunitas `odoo/odoo` branch 18.0 (HTTP 404), sehingga fitur ini kemungkinan dikirim di luar repo komunitas. Jadi bab ini tidak memberi contoh kode ekstensi; pakai fitur ini lewat UI, dan kalau kamu butuh memperluasnya, baca kode modul di instalasi Odoo-mu sendiri. Modul pihak ketiga seperti OCA `purchase_sale_inter_company` adalah add-on terpisah, bukan fitur inti.

> **Beda di Odoo 19:** Menurut dokumentasi 19.0, pengaturan inter-company punya opsi tambahan **Synchronize Stock Moves** dan pilihan **Validated** untuk memvalidasi dokumen otomatis (menggantikan "Create and validate"). Pengaturannya juga bisa dibuka di Settings > Users & Companies > Companies (tab Inter-Company Transactions muncul di Developer mode). Nama opsi di UI bisa berubah antar versi; cek halaman dokumentasi versi tujuanmu.

### Company-Dependent Fields

Field yang nilainya bisa berbeda per company meskipun record-nya sama:

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

Nilai yang dibaca/ditulis mengikuti company aktif di environment (`self.env.company`).

### Berpindah Company di Kode: `with_company()`

```python
# Jalankan operasi seolah company aktifnya other_company
loan_other = self.env['library.loan'].with_company(other_company).create({
    'member_id': member.id,
})
```

`with_company()` mengubah `env.company` sehingga default `company_id` record baru dan nilai `company_dependent` ikut company tersebut. Sebaliknya, `with_context(allowed_company_ids=[...])` mengatur daftar company yang aktif (`env.companies`), yaitu company mana yang boleh terlihat, bukan sekadar company default record baru.

> **Beda di Odoo 19:** Untuk string Python, dokumentasi terbaru menampilkan `self.env._("...")` sebagai cara utama dan `from odoo.tools import _` sebagai API lama. Di bab ini kita memakai `from odoo import _` yang berlaku di Odoo 18. Cek ketersediaan `self.env._` di versi yang kamu pakai sebelum mengandalkannya.

### Checklist Multi-Company

```
[ ] Model transaksional punya company_id dengan default self.env.company
[ ] Record rule pakai pola ['|', ('company_id', '=', False), ('company_id', 'in', company_ids)]
[ ] Rule multi-company dibuat GLOBAL (tanpa groups), bukan per-group
[ ] _check_company_auto = True + check_company=True pada Many2one ke model ber-company_id
[ ] Field company_id di form view memakai groups="base.group_multi_company"
[ ] Inter-company transactions: dipakai lewat Settings, tidak dikacaukan dengan record rule
[ ] Master data global sengaja dibiarkan company_id=False (field tidak required)
[ ] Setting yang beda per company pakai company_dependent=True, bukan company_id manual
[ ] Testing dilakukan dengan >= 2 company aktif untuk pastikan data tidak bocor antar company
```

---

## Ringkasan

- String Python dibungkus `_()` dengan placeholder `%(name)s`; JS memakai `_t()`. Jangan pakai f-string/`.format()` di dalamnya.
- Tulis string sumber dalam bahasa Inggris; terjemahan ada di `i18n/<lang>.po`, template di `.pot`.
- `translate=True` menyimpan nilai per bahasa di kolom field (jsonb); tabel `ir.translation` sudah tidak ada sejak Odoo 16.
- CLI: `--i18n-export` + `--modules` (+ `-l` untuk `.po`), `--i18n-import` + `-l` (+ `--i18n-overwrite`), `--load-language`.
- `company_id` dengan `default=lambda self: self.env.company` plus record rule berbasis `company_ids` memisahkan data antar company.
- `company_dependent=True` untuk nilai yang beda per company; `with_company()` untuk berpindah company di kode.
- Di `domain_force`, `company_ids` berisi company yang dicentang di switcher (bukan semua yang diizinkan); `user.company_ids` untuk yang diizinkan.
- Rule global digabung AND, rule per-group digabung OR lalu di-AND dengan rule global. Buat rule multi-company sebagai rule global.
- Record rule mengatur visibilitas; `_check_company_auto = True` + `check_company=True` menjaga relasi tidak lintas company dan menyaring dropdown di UI.
- Inter-company transactions adalah fitur Settings yang membuat dokumen pasangan (bill, SO, PO) di company lain, bukan record rule. Detail implementasi teknisnya belum terverifikasi di bab ini.

## Latihan

1. Tambahkan `_()` pada semua `UserError` di model `library.loan` milikmu, lalu export `library_management.pot` dan cek bahwa string-nya muncul.
2. Buat `i18n/id.po` dari hasil export, terjemahkan 3 string, lalu import dengan `--i18n-overwrite` dan ganti bahasa user ke Indonesia untuk memastikan hasilnya tampil.
3. Buat 2 company, tambahkan `company_id` + record rule pada `library.loan`, lalu login sebagai user dengan satu company saja dan pastikan loan company lain tidak terlihat.
4. Tambahkan `_check_company_auto = True` dan `check_company=True` pada `member_id`, lalu coba menautkan loan Cabang A ke member Cabang B. Catat perbedaan perilaku di UI (dropdown tersaring) dan lewat kode (`UserError`).
5. Ubah rule loan menjadi per-group (isi `groups`) lalu amati apa yang terjadi pada Manager. Kembalikan ke rule global dan jelaskan alasannya dengan rumus AND/OR.
6. Aktifkan Inter-Company Transactions di dua company (opsi Generate Bills and Refunds), posting invoice dari company A ke company B sebagai customer, dan cek bahwa vendor bill muncul di company B. Fitur ini bergantung pada edisi/modul yang terpasang di instalasimu.

## Lanjut ke

Bab 15: Database Views & Filtering untuk membuat model reporting berbasis SQL.
