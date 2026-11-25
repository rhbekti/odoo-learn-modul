# Bab 21: Tips, Best Practices & Checklist

> **Tahap:** 5 Profesional (bab penutup) | **Prasyarat:** Bab 4, 5, 6, 8, 10, 15, 20 | **Estimasi:** ± 2,5 jam | **Versi:** Odoo 18 (catatan Odoo 19)

## Tujuan Belajar

Setelah bab ini kamu bisa:
- Menerapkan konvensi penamaan dan urutan kode yang lazim di module Odoo.
- Mengenali dan memakai pola yang sering muncul: state machine, header-line, smart button, notifikasi.
- Menghindari anti-pattern umum: N+1, `sudo()` berlebihan, SQL injection, commit manual, `@api.depends` yang tidak lengkap, dan cache `@tools.ormcache` tanpa invalidasi.
- Memakai checklist sebelum deploy module dan menghubungkannya dengan checklist deployment di Bab 20 (termasuk cache, monitoring, dan rencana migrasi/upgrade).
- Memakai tabel perubahan versi dan peta kursus untuk kembali ke bab yang relevan.

> Bab ini merangkum dan merujuk materi sebelumnya; contoh memakai module `library_management` dari [Bab 10](10-multi-model-module.md).

---

## 1. Konvensi

Pedoman lengkapnya ada di Odoo coding guidelines (dokumentasi resmi, bagian Contributing). Ringkasan yang dipakai di kursus ini:

### Python

| Elemen | Convention | Contoh |
|--------|-----------|--------|
| Module | `snake_case` | `library_management` |
| Model `_name` | `dot.notation`, singular | `library.book.copy` |
| Class | `CamelCase` | `LibraryBookCopy` |
| Field, method | `snake_case` | `loan_date`, `action_confirm` |
| Compute | `_compute_xxx` | `_compute_total` |
| Onchange | `_onchange_xxx` | `_onchange_member_id` |
| Constraint | `_check_xxx` | `_check_dates` |
| Cron | `_cron_xxx` | `_cron_check_overdue` |
| Method internal | diawali `_` | `_prepare_values` |
| Tombol/action | `action_xxx` | `action_confirm` |

Kode Python mengikuti PEP 8. Satu model per file, nama file mengikuti nama model tanpa prefix module (`models/loan.py` untuk `library.loan`; Bab 10 memakai pola ini) dan setiap file harus di-import di `__init__.py`.

### Urutan isi class

Urutan yang direkomendasikan pedoman Odoo dalam satu model:

1. Atribut privat (`_name`, `_description`, `_inherit`, `_order`, ...)
2. Method default
3. Deklarasi field
4. Constraint (SQL dan `@api.constrains`)
5. Method compute, inverse, search
6. Method selection
7. Onchange
8. Override CRUD (`create`, `write`, `unlink`)
9. Method action (`action_xxx`)
10. Method bisnis lainnya

### XML

| Elemen | Convention | Contoh |
|--------|-----------|--------|
| View ID | `view_{model}_{type}` | `view_library_book_form` |
| Inherit view ID | `view_{model}_{type}_inherit_{module}` | `view_partner_form_inherit_library` |
| Action ID | `action_{model}` | `action_library_book` |
| Menu ID | `menu_{name}` | `menu_library_root` |
| Group ID | `group_{name}` | `group_library_manager` |
| Sequence ID | `seq_{name}` | `seq_library_loan` |

Pola ID di atas konsisten dengan Bab 10. Pedoman resmi Odoo menyarankan pola lain (nama model di depan, mis. `library_book_view_form`); yang terpenting konsisten di seluruh module.

---

## 2. Pola yang Sering Dipakai

### 2.1 State machine

Transisi state selalu lewat method yang memvalidasi, bukan `write({'state': ...})` dari mana-mana. Nama state di bawah mengikuti `library.loan` di Bab 10.

```python
class LibraryLoan(models.Model):
    _inherit = 'library.loan'

    def action_confirm(self):
        for loan in self.filtered(lambda r: r.state == 'draft'):
            loan._validate_confirm()
            loan.state = 'active'

    def action_return(self):
        for loan in self.filtered(lambda r: r.state == 'active'):
            loan.state = 'returned'

    def action_cancel(self):
        for loan in self.filtered(lambda r: r.state in ('draft', 'active')):
            loan.state = 'cancel'

    def _validate_confirm(self):
        self.ensure_one()
        if not self.line_ids:
            raise UserError(_('Minimal 1 buku harus dipilih.'))
```

Dengan `filtered`, tombol yang ditekan pada banyak record sekaligus tidak merusak record yang state-nya tidak cocok. Tampilan tombol per state diatur di view dengan `invisible="state != 'draft'"` (Bab 5).

### 2.2 Header-line

Satu header punya banyak line; total di header dihitung dari line. Contoh dari Bab 10 (`library.loan` dan `library.loan.line`):

```python
class LibraryLoan(models.Model):
    _inherit = 'library.loan'

    line_ids = fields.One2many('library.loan.line', 'loan_id')
    total_books = fields.Integer(compute='_compute_totals', store=True)

    @api.depends('line_ids')
    def _compute_totals(self):
        for loan in self:
            loan.total_books = len(loan.line_ids)


class LibraryLoanLine(models.Model):
    _inherit = 'library.loan.line'

    loan_id = fields.Many2one('library.loan', required=True, ondelete='cascade')
```

`ondelete='cascade'` pada Many2one di line membuat line ikut terhapus saat header dihapus.

### 2.3 Nomor urut otomatis

```python
@api.model_create_multi
def create(self, vals_list):
    for vals in vals_list:
        if vals.get('name', 'New') == 'New':
            vals['name'] = self.env['ir.sequence'].next_by_code('library.loan') or 'New'
    return super().create(vals_list)
```

Sequence-nya didefinisikan di XML (Bab 7).

### 2.4 Smart button

Contoh menambahkan jumlah peminjaman ke `res.partner` (warisan model: Bab 8).

```python
class ResPartner(models.Model):
    _inherit = 'res.partner'

    loan_count = fields.Integer(compute='_compute_loan_count')

    def _compute_loan_count(self):
        rows = self.env['library.loan']._read_group(
            [('member_id.partner_id', 'in', self.ids)],
            groupby=['member_id'],
            aggregates=['__count'],
        )
        counts = {member.partner_id.id: count for member, count in rows}
        for partner in self:
            partner.loan_count = counts.get(partner.id, 0)

    def action_view_loans(self):
        self.ensure_one()
        return {
            'name': _('Loans'),
            'type': 'ir.actions.act_window',
            'res_model': 'library.loan',
            'view_mode': 'list,form',
            'domain': [('member_id.partner_id', '=', self.id)],
        }
```

```xml
<!-- Di form view yang mewarisi form partner -->
<xpath expr="//div[@name='button_box']" position="inside">
    <button name="action_view_loans" type="object"
            class="oe_stat_button" icon="fa-book">
        <field name="loan_count" widget="statinfo" string="Loans"/>
    </button>
</xpath>
```

Satu query agregasi untuk semua partner di recordset, bukan satu query per partner.

### 2.5 Membuka view dengan filter dan default dari context

```python
def action_view_active(self):
    return {
        'name': _('Active Loans'),
        'type': 'ir.actions.act_window',
        'res_model': 'library.loan',
        'view_mode': 'list,form',
        'domain': [('state', '=', 'active')],
        'context': {
            'search_default_group_member': 1,  # aktifkan filter/group di search view bernama group_member
            'default_state': 'draft',          # default untuk record baru dari view ini
        },
    }
```

`search_default_<nama>` hanya bekerja jika search view punya filter dengan `name` yang sama (Bab 5).

### 2.6 Operasi recordset

```python
# filtered: ambil subset
active = loans.filtered(lambda l: l.state == 'active')
overdue = loans.filtered('is_overdue')           # shortcut untuk field boolean

# mapped: ambil nilai/relasi
names = loans.mapped('member_id.name')           # list nama
members = loans.mapped('member_id')              # recordset library.member

# sorted
newest = loans.sorted('loan_date', reverse=True)

# operasi set pada recordset
all_loans = loans_a | loans_b    # gabungan
common = loans_a & loans_b       # irisan
only_a = loans_a - loans_b       # selisih

# browse: recordset dari id yang sudah diketahui
loans = self.env['library.loan'].browse([1, 2, 3])

# slice dilakukan di Python (hasil sudah ada di memori), bukan query baru
first_five = loans[:5]
```

Recordset kosong bernilai `False`, jadi `if loan.member_id:` aman untuk mengecek relasi terisi. Untuk menghitung, pakai `search_count(domain)` daripada `len(search(domain))` karena tidak memuat record.

### 2.7 Notifikasi setelah action

```python
def action_confirm(self):
    self.write({'state': 'active'})
    return {
        'type': 'ir.actions.client',
        'tag': 'display_notification',
        'params': {
            'title': _('Success'),
            'message': _('%s loans confirmed.', len(self)),
            'type': 'success',      # success, warning, danger, info
            'sticky': False,        # False = hilang sendiri
            'next': {'type': 'ir.actions.act_window_close'},
        },
    }
```

### 2.8 Kondisi tampilan di view

Sejak `attrs` dan `states` dihapus, kondisi ditulis sebagai ekspresi langsung (detail di [Bab 5](05-views-xml.md)):

```xml
<field name="price" invisible="state == 'draft'"/>
<field name="name" readonly="state != 'draft'"/>
<field name="partner_id" required="state == 'active'"/>
<field name="discount" invisible="state == 'cancel' or not is_member"/>
```

---

## 3. Anti-Pattern (Hindari)

### 3.1 Query di dalam loop (N+1)

Membaca field relasi di loop atas satu recordset aman, karena Odoo melakukan prefetch. Yang bermasalah adalah `search`/`search_count`/`create`/`write` per record.

```python
# BURUK: satu query per buku
for book in books:
    n = self.env['library.book.copy'].search_count([('book_id', '=', book.id)])

# BAIK: satu query agregasi
rows = self.env['library.book.copy']._read_group(
    [('book_id', 'in', books.ids)],
    groupby=['book_id'],
    aggregates=['__count'],
)
copy_counts = {book.id: count for book, count in rows}
```

Begitu juga untuk tulis: kumpulkan dulu lalu satu `records.write({...})` atau `create(vals_list)` untuk banyak record. Detail optimasi ada di [Bab 20](20-deployment-performance.md).

### 3.2 `sudo()` tanpa alasan

```python
# BURUK: melewati access rights tanpa alasan
books = self.env['library.book'].sudo().search([])

# BAIK: biarkan hak akses user bekerja
books = self.env['library.book'].search([])
```

`sudo()` sah dipakai untuk operasi yang memang sengaja melewati hak user, mis. membuat record denda dari aksi anggota yang tidak punya hak create `library.fine`. Dalam kasus itu, batasi cakupannya sekecil mungkin dan tulis komentar alasannya:

```python
# sudo: anggota boleh memicu denda, tapi tidak boleh membuat library.fine langsung
self.env['library.fine'].sudo().create(vals)
```

### 3.3 Hardcode ID

```python
# BURUK: ID database berbeda di tiap instalasi
category = self.env['library.book.category'].browse(1)

# BAIK: XML ID dari data file (Bab 7)
category = self.env.ref('library_management.category_fiction')
```

### 3.4 Commit manual

```python
# BURUK: jika error terjadi sesudahnya, data setengah tersimpan
def action_process(self):
    for record in self:
        record.state = 'active'
        self.env.cr.commit()

# BAIK: biarkan Odoo mengelola transaksi (commit saat request selesai tanpa error)
def action_process(self):
    self.write({'state': 'active'})
```

### 3.5 Side effect di compute

Method compute hanya menghitung. Jangan `create`/`write` record lain di dalamnya; letakkan di action, `create`, atau `write`.

### 3.6 `@api.depends` tidak lengkap

```python
# BURUK: depends kurang, nilai stored jadi basi
@api.depends('line_ids')
def _compute_total(self):
    for order in self:
        order.total = sum(order.line_ids.mapped('price'))   # price tidak ada di depends

# BAIK: sebutkan semua field yang dibaca, termasuk lewat relasi
@api.depends('line_ids.price', 'line_ids.quantity')
def _compute_total(self):
    for order in self:
        order.total = sum(l.price * l.quantity for l in order.line_ids)
```

Aturan ringkas:
- Daftarkan semua field yang dibaca, termasuk path relasi (`line_ids.price`).
- Isi nilai untuk **setiap** record di `self` pada semua cabang `if`.
- Method compute selalu di-loop (`for rec in self`).
- Field yang bergantung pada waktu sekarang (mis. "hari ini") jangan di-`store`.

### 3.7 SQL injection

```python
# BURUK: nilai disisipkan ke string SQL
self.env.cr.execute(f"SELECT id FROM library_book WHERE name = '{name}'")
self.env.cr.execute("SELECT id FROM library_book WHERE name = '%s'" % name)
```

Cara yang benar di Odoo 18 adalah menyusun query dengan `odoo.tools.SQL` (nilai sebagai parameter, nama tabel/kolom lewat `SQL.identifier()`) dan menjalankannya dengan `self.env.execute_query`. Contoh dan penjelasan lengkapnya ada di [Bab 15, subbagian "Query SQL Aman dengan `odoo.tools.SQL`"](15-database-views-filtering.md), jadi tidak diulang di sini. Aturan praktisnya: jangan pernah menyambung string dari input user, jangan mengambil nama tabel/kolom dari input user, dan pakai ORM (`search`, `_read_group`) dulu; SQL mentah hanya bila perlu.

### 3.8 Cache registry tanpa invalidasi

`@tools.ormcache` mempercepat lookup, tetapi tanpa `self.env.registry.clear_cache()` saat data sumbernya berubah (create/write/unlink, atau SQL mentah), hasilnya basi. Jangan juga mengembalikan recordset dari method ber-cache. Detail, perbedaan dengan `invalidate_model()`/`invalidate_recordset()`, dan perilaku multi-worker ada di [Bab 20, bagian 11](20-deployment-performance.md).

---

## 4. Checklist Sebelum Deploy Module

```
[ ] Semua model punya baris di ir.model.access.csv (Bab 6)
[ ] Field yang dipakai di view sudah didefinisikan di model (Bab 5)
[ ] Semua XML ID yang direferensikan sudah ada
[ ] __manifest__.py: depends lengkap, urutan file data benar (Bab 3, 7)
[ ] __init__.py: semua file/folder ter-import
[ ] Sequence terdefinisi jika memakai nomor otomatis
[ ] Test lulus semua (Bab 17)
[ ] Tidak ada print() / breakpoint() tertinggal
[ ] Tidak ada sudo() yang tidak perlu, tidak ada hardcode ID
[ ] SQL mentah disusun dengan odoo.tools.SQL, tanpa menyambung string (Bab 15)
[ ] Method @tools.ormcache punya invalidasi dan tidak mengembalikan recordset (Bab 20, bagian 11)
[ ] Rename field/model/XML ID punya migration script, dan version manifest dinaikkan (Bab 20, bagian 14)
[ ] Group dan record rule benar (Bab 6)
[ ] View dicek di browser (form, list, search); report PDF dicoba cetak (Bab 11)
```

Lanjutkan dengan checklist infrastruktur di [Bab 20, bagian 10](20-deployment-performance.md): backup, staging, `workers`, `proxy_mode`, HTTPS, `dbfilter`/`list_db`, `admin_passwd`, log, serta monitoring query lambat (bagian 12) dan rencana upgrade (bagian 14).

---

## 5. Perubahan Versi yang Perlu Diingat

| Area | Lama | Odoo 18 / 19 | Bab |
|------|------|--------------|-----|
| View list | `<tree>` | `<list>` (juga `view_mode='list,form'`) | 5 |
| Kondisi tampilan | `attrs="{'invisible': [...]}"`, `states="draft"` | `invisible="expr"`, `readonly="expr"`, `required="expr"` (`attrs`/`states` dihapus sejak 17) | 5 |
| Chatter di form | tiga field dalam `<div class="oe_chatter">` | `<chatter/>` | 5 |
| Template kanban | `kanban-box` | `card` | 5 |
| Nama record | `name_get()` (deprecated sejak 17) | override `_compute_display_name` | 4, 8 |
| Create | `create(self, vals)` | `@api.model_create_multi` + `create(self, vals_list)` | 4 |
| Agregasi | `read_group` (hasil list dict) | `_read_group` (list tuple); di 19 hanya `_read_group` terdokumentasi | 4 |
| Agregat field | `group_operator` | `aggregator` | 4 |
| Constraint/index deklaratif | `_sql_constraints` | di Odoo 19: `models.Constraint`/`Index`/`UniqueIndex` terdokumentasi | 4 |
| Domain di Python | list tuple | di Odoo 19: `odoo.fields.Domain` terdokumentasi | 4 |
| URL backend | `/web#action=...` | `/odoo/action-...` | - |
| Cache dengan context | `@tools.ormcache_context(..., keys=(...))` | di Odoo 19 deprecated; pakai `@tools.ormcache` dengan `self.env.context.get(...)` | 20 |

> **Beda di Odoo 19:** tag `<list>`, `<chatter/>`, kanban `card`, dan atribut inline berlaku sama di 18 dan 19. Hal yang baru terdokumentasi di 19: `models.Constraint`/`Index`/`UniqueIndex`, `odoo.fields.Domain`, dan hanya `_read_group` untuk agregasi. PostgreSQL minimum 13 (18: 12), Python minimum 3.10 pada keduanya.

---

## 6. Peta Seluruh Kursus

| Tahap | Bab | Topik |
|-------|-----|-------|
| 1 Persiapan | [01](01-docker-setup.md), [02](02-install-config.md), [03](03-module-structure.md) | Docker, konfigurasi, struktur module |
| 2 Inti Pengembangan | [04](04-models-orm.md), [05](05-views-xml.md), [06](06-security-access-rights.md), [07](07-data-files-sequences.md), [08](08-inheritance-override.md), [09](09-wizards-dialogs.md), [10](10-multi-model-module.md) | Model/ORM, view, security, data, inheritance, wizard, studi kasus Library |
| 3 Fitur Lanjutan | [11](11-qweb-reports.md), [12](12-controllers-routing.md), [13](13-owl-javascript.md), [14](14-i18n-multi-company.md) | Report, controller, OWL, i18n & multi-company |
| 4 Data & Analitik | [15](15-database-views-filtering.md), [16](16-contoh-praktis-views.md) | Database view, filtering, contoh praktis |
| 5 Profesional | [17](17-testing.md), [18](18-debugging-troubleshooting.md), [19](19-external-api.md), [20](20-deployment-performance.md), [21](21-tips-best-practices.md) | Testing, debugging, API eksternal, deployment, best practices |

Butuh sesuatu cepat? Konvensi: bab ini. Query lambat dan monitoring (`pg_stat_statements`, log worker): [Bab 20, bagian 12](20-deployment-performance.md). Cache ORM (`@tools.ormcache`): [Bab 20, bagian 11](20-deployment-performance.md). Install tanpa Docker: [Bab 20, bagian 13](20-deployment-performance.md). Upgrade antar versi dan migration script: [Bab 20, bagian 14](20-deployment-performance.md). SQL aman (`odoo.tools.SQL`): [Bab 15](15-database-views-filtering.md). Error aneh: Bab 18. Hak akses: Bab 6. Override method: Bab 8.

---

## Ringkasan

- Ikuti konvensi penamaan dan urutan isi class; satu model per file, konsisten antar module.
- Pola andalan: state machine lewat method `action_*`, header-line, smart button berbasis `_read_group`, notifikasi `display_notification`.
- Hindari query dalam loop; gunakan `filtered`/`mapped`/`sorted`, batch `write`/`create`, dan `search_count`.
- `sudo()` hanya dengan alasan yang jelas dan cakupan sempit; jangan hardcode ID dan jangan `cr.commit()` manual.
- `@api.depends` harus lengkap (termasuk path relasi); compute tidak boleh punya side effect.
- Semua SQL mentah disusun dengan `odoo.tools.SQL` (Bab 15), bukan penyambungan string, untuk mencegah SQL injection.
- Method `@tools.ormcache` harus punya invalidasi (`registry.clear_cache()`); jangan campur dengan `invalidate_model()`/`invalidate_recordset()` yang mengurus cache record (Bab 20, bagian 11).
- Ukur dulu dengan `pg_stat_statements`/slow query log sebelum optimasi, dan rencanakan upgrade versi mayor dengan salinan database serta migration script (Bab 20, bagian 12 dan 14).
- Pakai checklist module (bab ini) bersama checklist deployment (Bab 20) sebelum rilis.

## Latihan

1. Ambil satu model dari Bab 10 dan periksa dengan checklist bagian 4; catat tiga hal yang belum memenuhi dan perbaiki.
2. Cari satu method yang memanggil `search()` atau `search_count()` di dalam loop (di modulmu sendiri, atau tulis contohnya), lalu ubah menjadi satu `_read_group`.
3. Tulis `@api.depends` yang benar untuk compute yang membaca `line_ids.price` dan `line_ids.quantity`, lalu buktikan di `odoo shell` bahwa mengubah `quantity` memperbarui total (ingat `env.cr.commit()` jika ingin menyimpan).
4. Ambil satu method yang menyusun SQL dengan penyambungan string (tulis contohnya jika belum ada), lalu tulis ulang dengan `odoo.tools.SQL` mengikuti Bab 15.
5. Pilih satu lookup konfigurasi di modulmu, beri `@tools.ormcache`, lalu lengkapi invalidasinya di `create`/`write`/`unlink` dengan `self.env.registry.clear_cache()` (Bab 20, bagian 11).
6. Tulis rencana upgrade satu halaman untuk modulmu dari Odoo 18 ke 19: daftar perubahan yang kena (rujuk tabel bagian 5), migration script yang dibutuhkan, dan langkah ujinya di salinan database (Bab 20, bagian 14).

## Langkah Selanjutnya

Kamu sudah melewati seluruh jalur kursus. Langkah berikutnya: bangun module sendiri dari kebutuhan nyata, tulis test-nya (Bab 17), deploy ke staging memakai Bab 20, lalu terus merujuk dokumentasi resmi Odoo 18/19 dan coding guidelines untuk detail yang tidak dibahas di sini.
