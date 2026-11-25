# Bab 15: Database Views & Filtering Inherited Models

> **Tahap:** 4 Data & Analitik | **Prasyarat:** Bab 4, 5, 6, 10 | **Estimasi:** ± 3,5 jam | **Versi:** Odoo 18 (catatan Odoo 19)

Database view adalah virtual table yang dibuat dari query SQL. Berguna untuk reporting, analytics, atau menampilkan data agregat tanpa menyimpan data duplikat. Bab ini juga membahas cara membuat model "turunan" yang hanya menampilkan sebagian data model induk. Contoh memakai model dari module `library_management` (Bab 10): `library.loan`, `library.loan.line`, `library.book`, `library.book.copy`, `library.member`, `library.fine`.

## Tujuan Belajar

Setelah bab ini kamu bisa:

- Membuat model read-only berbasis SQL view (`_auto = False` + `init()`).
- Membuat materialized view dan me-refresh-nya lewat scheduled action (cron).
- Memilih salah satu dari tiga cara memfilter model turunan: SQL view, proxy model dengan override `_search`, atau record rule.
- Membuat view, action, dan hak akses read-only untuk model report.
- Menulis query SQL yang aman dari SQL injection dengan `odoo.tools.SQL` (parameter, `SQL.identifier()`, `join`) dan menjalankannya dengan `self.env.execute_query`.
- Mendiagnosis error umum pada SQL view (relation does not exist, GROUP BY).

---

## 1. Kapan Menggunakan SQL View

- Reporting kompleks dengan JOIN banyak table.
- Agregasi data (SUM, COUNT, AVG) yang sering diakses.
- Optimasi query yang lambat.
- Dashboard metrics yang tidak perlu CRUD.

## 2. SQL View Model (Read-Only)

### Contoh: Statistik Peminjaman

Di Bab 10, buku yang dipinjam tercatat di `library.loan.line` (satu loan bisa punya banyak baris). Karena itu report dibangun dari `library_loan_line` yang di-JOIN ke `library_loan` dan `library_book`.

```python
# models/library_loan_report.py
from odoo import models, fields, tools


class LibraryLoanReport(models.Model):
    _name = 'library.loan.report'
    _description = 'Library Loan Statistics'
    _auto = False  # ORM tidak membuat table; kita buat view sendiri
    _rec_name = 'member_id'
    _order = 'total_loans desc'

    member_id = fields.Many2one('library.member', string='Member', readonly=True)
    book_id = fields.Many2one('library.book', string='Book', readonly=True)
    category_id = fields.Many2one('library.book.category', string='Category', readonly=True)
    loan_date = fields.Date(string='Loan Date', readonly=True)
    total_loans = fields.Integer(string='Total Loans', readonly=True)
    active_loans = fields.Integer(string='Active Loans', readonly=True)
    returned_loans = fields.Integer(string='Returned', readonly=True)
    overdue_loans = fields.Integer(string='Overdue Loans', readonly=True)

    def init(self):
        # Dipanggil saat module install/upgrade
        tools.drop_view_if_exists(self.env.cr, self._table)
        self.env.cr.execute("""
            CREATE VIEW library_loan_report AS (
                SELECT
                    row_number() OVER () AS id,
                    l.member_id,
                    ln.book_id,
                    lb.category_id,
                    l.loan_date,
                    COUNT(ln.id) AS total_loans,
                    COUNT(CASE WHEN l.state = 'active' THEN 1 END) AS active_loans,
                    COUNT(CASE WHEN l.state = 'returned' THEN 1 END) AS returned_loans,
                    COUNT(CASE WHEN l.state = 'active'
                                AND l.due_date < CURRENT_DATE THEN 1 END) AS overdue_loans
                FROM library_loan_line ln
                JOIN library_loan l ON l.id = ln.loan_id
                JOIN library_book lb ON lb.id = ln.book_id
                GROUP BY l.member_id, ln.book_id, lb.category_id, l.loan_date
            )
        """)
```

Penjelasan:

- `_auto = False`: tidak membuat table; view kita definisikan sendiri via SQL. Wajib.
- `init()`: dipanggil saat install/upgrade; tempat membuat view.
- `tools.drop_view_if_exists(self.env.cr, self._table)`: hapus view lama sebelum membuat yang baru (`from odoo import tools`).
- `row_number() OVER () AS id`: setiap row harus punya kolom `id` integer unik. Kalau view sudah punya id alami (mis. `lb.id`), pakai itu.
- Nama view di SQL harus sama dengan `_table` (default: `_name` dengan titik jadi underscore).
- Status "overdue" tidak ada di `state` loan (Bab 10); kita hitung dari `due_date`.

### Hak Akses (CSV) untuk Model Report

Model baru tetap butuh akses, kalau tidak user mendapat error access rights. Karena read-only, beri hanya hak read:

```csv
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_loan_report_user,library.loan.report user,model_library_loan_report,group_library_user,1,0,0,0
```

### Query SQL Aman dengan `odoo.tools.SQL`

`init()` di atas aman karena seluruh query-nya string tetap yang kamu tulis sendiri. Masalah muncul begitu ada nilai dinamis (input user, parameter method, nama kolom dari luar) yang disisipkan ke dalam string SQL. Class `SQL` dari `odoo.tools` ada di Odoo 18 dan 19 dan dibuat untuk itu.

**Sebelum: f-string, rawan SQL injection**

```python
@api.model
def count_active_loans(self, member_name):
    # JANGAN: nilai member_name masuk mentah ke dalam teks SQL
    self.env.cr.execute(f"""
        SELECT COUNT(*)
          FROM library_loan l
          JOIN library_member lm ON lm.id = l.member_id
          JOIN res_partner rp ON rp.id = lm.partner_id
         WHERE rp.name = '{member_name}' AND l.state = 'active'
    """)
    return self.env.cr.fetchone()[0]
```

Kalau `member_name` berisi `x' OR '1'='1`, kondisi `WHERE` berubah makna dan semua loan aktif ikut terhitung. Dengan input yang lebih jahat, query bisa diubah total.

**Sesudah: `SQL()` dengan parameter**

```python
# models/library_loan_report.py  (tambahan di file yang sama)
from odoo import api, models, fields, tools
from odoo.tools import SQL


class LibraryLoanReport(models.Model):
    # ... _name, field, dan init() seperti di atas ...

    @api.model
    def count_active_loans(self, member_name):
        query = SQL("""
            SELECT COUNT(*)
              FROM library_loan l
              JOIN library_member lm ON lm.id = l.member_id
              JOIN res_partner rp ON rp.id = lm.partner_id
             WHERE rp.name = %s AND l.state = %s
        """, member_name, 'active')
        rows = self.env.execute_query(query)   # list of tuple
        return rows[0][0]
```

Nilai `member_name` dan `'active'` tidak pernah digabung ke teks SQL. `SQL` menyimpan kode (`query.code`, dengan `%s`) dan nilainya (`query.params`) terpisah, lalu driver database yang mengisi nilai dengan benar. Jaminan "aman" dari `SQL` berlaku selama argumen pertama adalah string literal di kode, bukan hasil f-string atau penggabungan string. Jangan menulis `SQL(f"... {x} ...")`.

Hal yang bisa dilakukan dengan `SQL`:

```python
# 1. Argumen bernama
SQL("l.state = %(state)s AND l.member_id = %(member)s", state='active', member=member.id)
# (pilih salah satu gaya: posisi %s ATAU bernama, tidak boleh dicampur)

# 2. Nama tabel/kolom dinamis: pakai SQL.identifier, bukan parameter nilai
SQL("SELECT %s FROM %s", SQL.identifier('l', 'due_date'), SQL.identifier('library_loan'))
# hasilnya: SELECT "l"."due_date" FROM "library_loan"

# 3. Menyusun fragmen: SQL boleh menjadi argumen SQL lain
conditions = [SQL("l.state = %s", 'active')]
if member_id:
    conditions.append(SQL("l.member_id = %s", member_id))
where = SQL(" AND ").join(conditions)          # separator.join(list)
query = SQL("SELECT l.id FROM library_loan l WHERE %s ORDER BY %s",
            where, SQL.identifier('l', 'due_date'))

# 4. Daftar nilai untuk IN: kirim tuple
SQL("l.state IN %s", ('active', 'returned'))   # tuple tidak boleh kosong
```

Catatan penting:

- `SQL.identifier(name)` hanya memeriksa bentuk nama (huruf/angka/underscore, di-kutip dengan `"`), bukan apakah tabel atau kolomnya ada. Kalau nama berasal dari input user, cocokkan dulu dengan daftar yang diizinkan (mis. `if col not in ('due_date', 'loan_date'): raise`).
- Nilai (string, angka, tanggal, tuple) lewat `%s`; nama tabel/kolom lewat `SQL.identifier`. Jangan tukar keduanya.
- `SQL(" AND ").join([])` menghasilkan SQL kosong, jadi pastikan list kondisi tidak kosong sebelum menaruhnya setelah `WHERE`.
- Untuk pola `LIKE`/`ILIKE`, kirim polanya sebagai parameter: `SQL("rp.name ILIKE %s", f"%{keyword}%")`. Jangan menulis tanda `%` literal di dalam teks SQL (lihat catatan Odoo 19 di bawah).

**Menjalankan query**

- `self.env.execute_query(query)` mengembalikan `list[tuple]` (list kosong kalau query tidak mengembalikan baris), dan sebelumnya otomatis me-flush field ORM yang ditandai di metadata `SQL` (parameter `to_flush=`, diisi objek field). Ada juga `self.env.execute_query_dict(query)` yang mengembalikan `list[dict]` berkunci nama kolom.
- `self.env.cr.execute(query)` juga menerima objek `SQL` (tanpa argumen `params` kedua), tapi tidak melakukan flush. Cocok untuk DDL di `init()` atau statement tanpa hasil.
- Kalau sebelum query kamu baru mengubah data lewat ORM (`create`/`write`) dan query membaca tabel yang sama, flush dulu (`self.env['library.loan'].flush_model()`) atau lewatkan fieldnya lewat `to_flush=`, supaya SQL melihat data terbaru. Lihat bagian invalidate/flush di Bab 4.

**Hubungan dengan `init()`**

Contoh `init()` di atas tetap benar dan tidak perlu diubah. Kalau kamu ingin nama view diambil dari `self._table` tanpa menempelkan string, pakai `SQL.identifier`:

```python
def init(self):
    tools.drop_view_if_exists(self.env.cr, self._table)
    self.env.cr.execute(SQL("""
        CREATE VIEW %s AS (
            SELECT row_number() OVER () AS id,
                   l.member_id,
                   COUNT(ln.id) AS total_loans
              FROM library_loan_line ln
              JOIN library_loan l ON l.id = ln.loan_id
             GROUP BY l.member_id
        )
    """, SQL.identifier(self._table)))
```

(Versi ringkas, hanya untuk memperlihatkan polanya; kolom lain tetap seperti di contoh lengkap.) Lihat juga `tools.drop_view_if_exists` di kode sumber Odoo: ia sendiri memakai `SQL("DROP VIEW %s CASCADE", SQL.identifier(viewname))`.

> **Beda di Odoo 19:** `SQL` dan `execute_query` dipakai sama di 18 dan 19 (`from odoo.tools import SQL`; di 19 `Environment` dipindah ke `odoo/orm/environments.py`, tapi `self.env.execute_query` tetap). Bedanya ada di detail: (1) docstring 19.0 menyatakan karakter `%` selalu harus ditulis `%%` di teks SQL, bahkan tanpa parameter (`SQL("foo LIKE 'a%%'")`), sedangkan docstring 18.0 bilang `%%` tidak didukung; cara aman di kedua versi adalah mengirim pola `LIKE` sebagai parameter seperti di atas. (2) Di 19, objek `SQL` bisa di-hash, `to_flush` boleh berupa banyak field, dan membongkar objek (`code, params = query`) memunculkan `DeprecationWarning`; pakai `query.code` dan `query.params`.

## 3. Materialized View (PostgreSQL)

Materialized view menyimpan hasil query secara fisik: cepat dibaca, tapi datanya hanya berubah saat di-refresh.

```python
# models/library_dashboard_stats.py
from odoo import models, fields, api, tools


class LibraryDashboardStats(models.Model):
    _name = 'library.dashboard.stats'
    _description = 'Library Dashboard Statistics (Materialized)'
    _auto = False
    _order = 'date desc'

    date = fields.Date(string='Date', readonly=True)
    total_books = fields.Integer(string='Total Books', readonly=True)
    active_loans = fields.Integer(string='Active Loans', readonly=True)
    loans_created = fields.Integer(string='Loans Created', readonly=True)
    loans_returned = fields.Integer(string='Loans Returned', readonly=True)
    fines_paid = fields.Float(string='Fines Paid', readonly=True)

    def init(self):
        # DROP eksplisit supaya jelas jenisnya; (di kode sumber 18.0 dan 19.0, tools.drop_view_if_exists
        # juga menangani materialized view)
        self.env.cr.execute("DROP MATERIALIZED VIEW IF EXISTS library_dashboard_stats CASCADE")
        self.env.cr.execute("""
            CREATE MATERIALIZED VIEW library_dashboard_stats AS (
                SELECT
                    (row_number() OVER (ORDER BY d.day))::int AS id,
                    d.day::date AS date,
                    (SELECT COUNT(*) FROM library_book WHERE active) AS total_books,
                    (SELECT COUNT(*) FROM library_loan WHERE state = 'active') AS active_loans,
                    (SELECT COUNT(*) FROM library_loan
                      WHERE loan_date = d.day::date) AS loans_created,
                    (SELECT COUNT(*) FROM library_loan
                      WHERE return_date = d.day::date) AS loans_returned,
                    (SELECT COALESCE(SUM(amount), 0) FROM library_fine
                      WHERE state = 'paid' AND payment_date = d.day::date) AS fines_paid
                FROM generate_series(
                    CURRENT_DATE - INTERVAL '30 days',
                    CURRENT_DATE,
                    INTERVAL '1 day'
                ) AS d(day)
            )
        """)
        # Index untuk performa baca
        self.env.cr.execute(
            "CREATE INDEX IF NOT EXISTS library_dashboard_stats_date_idx "
            "ON library_dashboard_stats (date)"
        )

    @api.model
    def refresh_stats(self):
        """Refresh materialized view; dipanggil manual atau oleh cron."""
        self.env.cr.execute("REFRESH MATERIALIZED VIEW library_dashboard_stats")
        return True
```

Perhatikan: kolom `id` harus integer (bukan tanggal), dan nilai per hari dihitung dengan subquery terpisah agar angka tidak berlipat akibat JOIN.

### Scheduled Action untuk Auto-Refresh

```xml
<!-- data/cron_refresh_stats.xml -->
<odoo>
    <data noupdate="1">
        <record id="cron_refresh_dashboard_stats" model="ir.cron">
            <field name="name">Refresh Library Dashboard Stats</field>
            <field name="model_id" ref="model_library_dashboard_stats"/>
            <field name="state">code</field>
            <field name="code">model.refresh_stats()</field>
            <field name="interval_number">1</field>
            <field name="interval_type">hours</field>
            <field name="active" eval="True"/>
        </record>
    </data>
</odoo>
```

### Regular View vs Materialized View

| Aspek | Regular View | Materialized View |
|-------|-------------|-------------------|
| Kecepatan | Lebih lambat (query dijalankan tiap akses) | Lebih cepat (hasil tersimpan) |
| Storage | Tidak memakai storage | Memakai storage |
| Kesegaran data | Selalu terbaru | Terbaru hanya sampai refresh terakhir |
| Cocok untuk | Data real-time | Dashboard, laporan berkala |

## 4. Filtering Data pada Inherited Models

### Use Case

Kita ingin model khusus "Premium Members" yang hanya menampilkan `library.member` dengan `membership_type = 'premium'` (nilai selection di Bab 10: `student`, `regular`, `premium`). Ada tiga pendekatan.

### Metode 1: SQL View dengan Filter (Read-Only)

Di Bab 10, `library.member` memakai `_inherits` ke `res.partner`, jadi nama, email, dan telepon ada di `res_partner`, bukan di `library_member`. View harus JOIN ke keduanya.

```python
# models/library_member_premium.py
from odoo import models, fields, tools


class LibraryMemberPremium(models.Model):
    _name = 'library.member.premium'
    _description = 'Premium Library Members'
    _auto = False
    _rec_name = 'name'
    _order = 'name'

    name = fields.Char(string='Name', readonly=True)
    email = fields.Char(string='Email', readonly=True)
    phone = fields.Char(string='Phone', readonly=True)
    member_number = fields.Char(string='Member No.', readonly=True)
    membership_type = fields.Selection([
        ('student', 'Student'),
        ('regular', 'Regular'),
        ('premium', 'Premium'),
    ], string='Type', readonly=True)
    join_date = fields.Date(string='Member Since', readonly=True)
    partner_id = fields.Many2one('res.partner', string='Partner', readonly=True)
    total_loans = fields.Integer(string='Total Loans', readonly=True)
    active_loans = fields.Integer(string='Active Loans', readonly=True)

    def init(self):
        tools.drop_view_if_exists(self.env.cr, self._table)
        self.env.cr.execute("""
            CREATE VIEW library_member_premium AS (
                SELECT
                    lm.id,
                    rp.name,
                    rp.email,
                    rp.phone,
                    lm.member_number,
                    lm.membership_type,
                    lm.join_date,
                    lm.partner_id,
                    COUNT(ll.id) AS total_loans,
                    COUNT(CASE WHEN ll.state = 'active' THEN 1 END) AS active_loans
                FROM library_member lm
                JOIN res_partner rp ON rp.id = lm.partner_id
                LEFT JOIN library_loan ll ON ll.member_id = lm.id
                WHERE lm.membership_type = 'premium'
                  AND rp.active = true
                GROUP BY lm.id, rp.name, rp.email, rp.phone,
                         lm.member_number, lm.membership_type,
                         lm.join_date, lm.partner_id
            )
        """)
```

Kelebihan: filter di level database, tidak bisa di-bypass lewat ORM, bisa menambah agregasi (`total_loans`). Kekurangan: read-only; field harus didefinisikan ulang.

### Metode 2: Proxy Model dengan Override `_search`

Model baru yang berbagi table dengan model induk, dan semua pencarian otomatis difilter. Cocok kalau kamu butuh create/write/delete.

```python
# models/library_member_premium.py
from odoo import models, api


class LibraryMemberPremium(models.Model):
    _name = 'library.member.premium'
    _description = 'Premium Library Members'
    _inherit = 'library.member'
    _table = 'library_member'  # pakai table yang sama dengan library.member
    _auto = False              # jangan buat/ubah table

    @api.model
    def _search(self, domain, *args, **kwargs):
        # Semua pencarian (search, search_read, search_count, ...) lewat sini
        domain = [('membership_type', '=', 'premium')] + list(domain or [])
        return super()._search(domain, *args, **kwargs)

    @api.model
    def default_get(self, fields_list):
        res = super().default_get(fields_list)
        res['membership_type'] = 'premium'
        return res

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            vals['membership_type'] = 'premium'
        return super().create(vals_list)

    def write(self, vals):
        # Jangan izinkan keluar dari tipe premium lewat model ini
        vals.pop('membership_type', None)
        return super().write(vals)
```

Catatan: signature `_search` di sini sengaja memakai `*args, **kwargs` supaya tetap jalan walau parameter di versi Odoo berbeda (di Odoo 17 ke atas parameter lama `access_rights_uid` sudah tidak dipakai; di Odoo 18 bentuknya `_search(self, domain, offset=0, limit=None, order=None)`).

Kelebihan: bisa CRUD, transparan untuk view dan action. Kekurangan: filter hanya berlaku lewat ORM (SQL langsung tidak ikut), dan model induk dengan `_inherits` seperti `library.member` perlu diuji menyeluruh sebelum dipakai di produksi. `sudo()` tidak meng-bypass override `_search`.

### Metode 3: Record Rule (Filter Berbasis Security)

Pakai model proxy yang sama (tanpa override `_search`), lalu batasi lewat rule:

```xml
<!-- security/ir_rule.xml -->
<odoo>
    <data noupdate="1">
        <record id="rule_library_member_premium_only" model="ir.rule">
            <field name="name">Premium Members Only</field>
            <field name="model_id" ref="model_library_member_premium"/>
            <field name="domain_force">[('membership_type', '=', 'premium')]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
        </record>
    </data>
</odoo>
```

Kelebihan: bisa CRUD, mudah dirawat, filter terlihat jelas di konfigurasi security. Kekurangan: `sudo()` mem-bypass record rule, dan tidak bisa menambah field agregat.

### Perbandingan

| Metode | CRUD | Bisa di-bypass | Agregasi | Cocok untuk |
|--------|------|----------------|----------|-------------|
| 1. SQL view | Tidak | Tidak (lewat ORM) | Ya | Reporting |
| 2. Proxy + `_search` | Ya | SQL langsung | Tidak | Filter tetap + CRUD |
| 3. Record rule | Ya | `sudo()` | Tidak | Pembatasan per group |

## 5. Contoh Lengkap: Buku yang Tersedia

Model untuk menampilkan buku yang punya minimal satu copy berstatus `available` (state copy di Bab 10: `available`, `borrowed`, `maintenance`, `lost`).

```python
# models/library_book_available.py
from odoo import models, fields, tools


class LibraryBookAvailable(models.Model):
    _name = 'library.book.available'
    _description = 'Available Books for Loan'
    _auto = False
    _rec_name = 'book_name'
    _order = 'available_copies desc, book_name'

    book_id = fields.Many2one('library.book', string='Book', readonly=True)
    book_name = fields.Char(string='Title', readonly=True)
    author = fields.Char(string='Author', readonly=True)
    isbn = fields.Char(string='ISBN', readonly=True)
    category_id = fields.Many2one('library.book.category', string='Category', readonly=True)
    total_copies = fields.Integer(string='Total Copies', readonly=True)
    available_copies = fields.Integer(string='Available', readonly=True)
    borrowed_copies = fields.Integer(string='Borrowed', readonly=True)
    lost_copies = fields.Integer(string='Lost', readonly=True)
    loan_count = fields.Integer(string='Times Borrowed', readonly=True)

    def init(self):
        tools.drop_view_if_exists(self.env.cr, self._table)
        self.env.cr.execute("""
            CREATE VIEW library_book_available AS (
                SELECT
                    lb.id,
                    lb.id AS book_id,
                    lb.name AS book_name,
                    lb.author,
                    lb.isbn,
                    lb.category_id,
                    COUNT(lbc.id) AS total_copies,
                    COUNT(CASE WHEN lbc.state = 'available' THEN 1 END) AS available_copies,
                    COUNT(CASE WHEN lbc.state = 'borrowed' THEN 1 END) AS borrowed_copies,
                    COUNT(CASE WHEN lbc.state = 'lost' THEN 1 END) AS lost_copies,
                    (SELECT COUNT(*) FROM library_loan_line ln
                      WHERE ln.book_id = lb.id) AS loan_count
                FROM library_book lb
                LEFT JOIN library_book_copy lbc ON lbc.book_id = lb.id
                WHERE lb.active = true
                GROUP BY lb.id, lb.name, lb.author, lb.isbn, lb.category_id
                HAVING COUNT(CASE WHEN lbc.state = 'available' THEN 1 END) > 0
            )
        """)

    def action_create_loan(self):
        """Buka wizard peminjaman (Bab 9) dengan buku terpilih."""
        self.ensure_one()
        return {
            'name': 'Create Loan',
            'type': 'ir.actions.act_window',
            'res_model': 'library.loan.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {'default_book_id': self.book_id.id},
        }
```

### View, Action, dan Menu

```xml
<!-- views/library_book_available_views.xml -->
<odoo>
    <record id="view_library_book_available_list" model="ir.ui.view">
        <field name="name">library.book.available.list</field>
        <field name="model">library.book.available</field>
        <field name="arch" type="xml">
            <list string="Available Books" create="false" edit="false" delete="false">
                <field name="book_name"/>
                <field name="author"/>
                <field name="category_id"/>
                <field name="available_copies"/>
                <field name="borrowed_copies"/>
                <field name="total_copies"/>
                <field name="loan_count"/>
                <button name="action_create_loan" string="Loan"
                        type="object" class="btn-primary" icon="fa-book"/>
            </list>
        </field>
    </record>

    <record id="view_library_book_available_search" model="ir.ui.view">
        <field name="name">library.book.available.search</field>
        <field name="model">library.book.available</field>
        <field name="arch" type="xml">
            <search>
                <field name="book_name"/>
                <field name="author"/>
                <field name="category_id"/>
                <filter name="high_availability" string="High Availability"
                        domain="[('available_copies', '&gt;=', 3)]"/>
                <filter name="popular" string="Popular"
                        domain="[('loan_count', '&gt;=', 5)]"/>
                <group expand="0" string="Group By">
                    <filter name="group_category" string="Category"
                            context="{'group_by': 'category_id'}"/>
                    <filter name="group_author" string="Author"
                            context="{'group_by': 'author'}"/>
                </group>
            </search>
        </field>
    </record>

    <record id="action_library_book_available" model="ir.actions.act_window">
        <field name="name">Available Books</field>
        <field name="res_model">library.book.available</field>
        <field name="view_mode">list</field>
        <field name="context">{'search_default_high_availability': 1}</field>
    </record>

    <menuitem id="menu_library_book_available"
              name="Available Books"
              parent="menu_library_root"
              action="action_library_book_available"
              sequence="15"/>
</odoo>
```

Catatan: `view_mode` hanya berisi `list` karena kita tidak membuat form view untuk model report. Tombol baris (`<button>`) di list memanggil method `action_create_loan` pada record terpilih. Jangan lupa baris akses read-only di `ir.model.access.csv` (lihat bagian 2).

## 6. Performance Tips

### Index pada View

View biasa tidak bisa diberi index (index hanya untuk table dan materialized view). Kalau view lambat, pastikan kolom yang dipakai di JOIN/WHERE pada table sumber sudah ber-index, atau pakai materialized view lalu beri index seperti di bagian 3.

### Cek Rencana Query

```sql
-- Jalankan di psql
EXPLAIN ANALYZE SELECT * FROM library_loan_report WHERE member_id = 1;
```

## 7. Best Practices

```
DO
- Selalu _auto = False dan semua field readonly=True
- Pastikan ada kolom id integer unik (row_number() OVER () atau id asli)
- Pakai COALESCE untuk menangani NULL pada agregat
- Pakai LEFT JOIN untuk relasi opsional
- GROUP BY semua kolom non-agregat
- Drop view lama sebelum CREATE (tools.drop_view_if_exists)
- Beri hak akses read-only di ir.model.access.csv
- Beri create="false" edit="false" delete="false" di list view

DON'T
- Jangan buat computed field di model SQL view (kolomnya sudah dari SQL)
- Jangan harap bisa create/write/unlink pada SQL view
- Jangan hardcode rentang tanggal; pakai CURRENT_DATE - INTERVAL '30 days'
- Jangan JOIN tanpa memikirkan duplikasi baris (angka agregat bisa berlipat)
```

## 8. Troubleshooting

### Error: "relation does not exist"

View belum dibuat. Upgrade module supaya `init()` dijalankan:

```bash
docker compose exec odoo odoo -d odoo -u library_management --stop-after-init
```

### Error: "column must appear in the GROUP BY clause"

```sql
-- BAD: field3 tidak di-agregat dan tidak di-group
SELECT field1, field2, field3, SUM(field4) FROM t GROUP BY field1, field2

-- GOOD
SELECT field1, field2, field3, SUM(field4) FROM t GROUP BY field1, field2, field3
```

### View Tidak Berubah Setelah Query Diubah

`init()` hanya jalan saat install/upgrade. Jalankan upgrade module (perintah di atas). Kalau upgrade gagal karena view lain bergantung padanya, drop manual di psql: `DROP VIEW IF EXISTS library_loan_report CASCADE;` lalu upgrade lagi.

## Checklist

```
[ ] _auto = False untuk model SQL view
[ ] Nama view di SQL sama dengan _table
[ ] Semua field readonly=True
[ ] init() membuat view; drop view lama dulu
[ ] Ada kolom id integer unik
[ ] GROUP BY semua kolom non-agregat; COALESCE untuk NULL
[ ] Hak akses read-only di ir.model.access.csv
[ ] <list create="false" edit="false" delete="false"> dan view_mode memakai list
[ ] Query dites dengan EXPLAIN ANALYZE
```

> **Beda di Odoo 19:** Untuk agregasi lewat ORM, `read_group` terdokumentasi di Odoo 18, sedangkan di Odoo 19 yang terdokumentasi hanya `_read_group`. Contoh `_search` di bab ini memakai domain berbentuk list seperti di Odoo 18; uji ulang override `_search` saat upgrade ke 19.

## Ringkasan

- SQL view = model dengan `_auto = False` dan `init()` yang menjalankan `CREATE VIEW`; semua field `readonly=True`.
- View wajib punya kolom `id` integer unik; pakai `row_number() OVER ()` kalau hasil digroup.
- Materialized view cepat dibaca tapi harus di-refresh (cron memanggil `REFRESH MATERIALIZED VIEW`); drop-nya memakai `DROP MATERIALIZED VIEW`.
- Untuk filter model turunan: SQL view (read-only, agregasi), proxy model + `_search` (CRUD), atau record rule (CRUD, per group).
- Nilai dinamis di SQL jangan lewat f-string: pakai `SQL("... %s", nilai)`, `SQL.identifier()` untuk nama tabel/kolom, `SQL(" AND ").join([...])` untuk fragmen, dan jalankan dengan `self.env.execute_query()`.
- Model report tetap butuh baris `ir.model.access.csv` (read-only) dan view dengan `<list>`.
- Hati-hati JOIN yang melipatgandakan baris dan bentuk `GROUP BY`.

## Latihan

1. Buat model `library.loan.report` bagian 2, install, lalu buat list view dan menu-nya. Cek bahwa kolom `overdue_loans` terisi untuk loan aktif yang lewat jatuh tempo.
2. Buat materialized view `library.dashboard.stats` dan cron refresh-nya; ubah interval jadi 1 menit untuk uji, lalu kembalikan.
3. Implementasikan "Premium Members" dengan Metode 1 dan Metode 2, lalu bandingkan: coba buat record baru dan lihat metode mana yang mengizinkannya.
4. Tambahkan `count_active_loans(member_name)` dengan `SQL()` di `library.loan.report`. Panggil dari `odoo shell` dengan nama biasa, lalu dengan `"x' OR '1'='1"`; pastikan hasilnya 0 (nama itu dicari apa adanya). Ulangi dengan versi f-string pada database uji dan amati bedanya.
5. Buat versi dengan filter opsional: `member_id` dan `state` hanya dipakai kalau diisi, disusun dari list fragmen `SQL` dan `SQL(" AND ").join(...)`, dijalankan dengan `self.env.execute_query_dict`.

## Lanjut ke

Bab 16: Contoh Praktis Views, untuk melihat berbagai jenis view dipakai dalam skenario nyata.
