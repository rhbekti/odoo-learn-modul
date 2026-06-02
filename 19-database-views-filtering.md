# Bab 19: Database Views & Filtering Inherited Models

## Database Views di Odoo 18

Database views adalah virtual tables yang dibuat dari query SQL. Berguna untuk reporting, analytics, atau menampilkan data agregat tanpa menyimpan data duplikat.

---

## 1. SQL View Model (Read-Only)

### Kapan Menggunakan SQL Views

- **Reporting kompleks** dengan JOIN banyak table
- **Agregasi data** (SUM, COUNT, AVG) yang sering diakses
- **Performance optimization** untuk query yang lambat
- **Dashboard metrics** yang tidak perlu CRUD

### Contoh: Library Loan Statistics View

```python
# models/library_loan_report.py
from odoo import models, fields, tools

class LibraryLoanReport(models.Model):
    _name = 'library.loan.report'
    _description = 'Library Loan Statistics'
    _auto = False  # Tidak buat table otomatis
    _rec_name = 'member_id'
    _order = 'total_loans desc'

    # Fields dari SQL view (read-only)
    member_id = fields.Many2one('library.member', string='Member', readonly=True)
    book_id = fields.Many2one('library.book', string='Book', readonly=True)
    category_id = fields.Many2one('library.book.category', string='Category', readonly=True)
    total_loans = fields.Integer(string='Total Loans', readonly=True)
    active_loans = fields.Integer(string='Active Loans', readonly=True)
    overdue_loans = fields.Integer(string='Overdue Loans', readonly=True)
    total_fines = fields.Float(string='Total Fines', readonly=True)
    loan_date = fields.Date(string='Loan Date', readonly=True)
    state = fields.Selection([
        ('draft', 'Draft'),
        ('active', 'Active'),
        ('returned', 'Returned'),
        ('overdue', 'Overdue'),
    ], string='Status', readonly=True)

    def init(self):
        """
        Method init() dipanggil saat module install/upgrade.
        Di sini kita define SQL query untuk create view.
        """
        tools.drop_view_if_exists(self.env.cr, self._table)
        query = """
            CREATE OR REPLACE VIEW library_loan_report AS (
                SELECT
                    row_number() OVER () AS id,
                    ll.member_id,
                    ll.book_id,
                    lb.category_id,
                    ll.loan_date,
                    ll.state,
                    COUNT(ll.id) AS total_loans,
                    COUNT(CASE WHEN ll.state = 'active' THEN 1 END) AS active_loans,
                    COUNT(CASE WHEN ll.state = 'overdue' THEN 1 END) AS overdue_loans,
                    COALESCE(SUM(lf.amount), 0) AS total_fines
                FROM
                    library_loan ll
                LEFT JOIN
                    library_book lb ON ll.book_id = lb.id
                LEFT JOIN
                    library_fine lf ON ll.id = lf.loan_id
                GROUP BY
                    ll.member_id,
                    ll.book_id,
                    lb.category_id,
                    ll.loan_date,
                    ll.state
            )
        """
        self.env.cr.execute(query)
```

**Penjelasan:**
- `_auto = False` — tidak buat table, kita define sendiri via SQL
- `init()` — method khusus untuk create/replace view
- `row_number() OVER () AS id` — generate ID unik untuk setiap row
- `tools.drop_view_if_exists()` — hapus view lama sebelum create baru

---

## 2. Materialized View (PostgreSQL)

Materialized view menyimpan hasil query secara fisik, lebih cepat tapi perlu refresh manual.

```python
# models/library_dashboard_stats.py
from odoo import models, fields, tools, api

class LibraryDashboardStats(models.Model):
    _name = 'library.dashboard.stats'
    _description = 'Library Dashboard Statistics (Materialized)'
    _auto = False
    _order = 'date desc'

    date = fields.Date(string='Date', readonly=True)
    total_books = fields.Integer(string='Total Books', readonly=True)
    total_members = fields.Integer(string='Total Members', readonly=True)
    active_loans = fields.Integer(string='Active Loans', readonly=True)
    books_borrowed_today = fields.Integer(string='Borrowed Today', readonly=True)
    books_returned_today = fields.Integer(string='Returned Today', readonly=True)
    revenue_today = fields.Float(string='Revenue Today', readonly=True)

    def init(self):
        tools.drop_view_if_exists(self.env.cr, self._table)
        query = """
            CREATE MATERIALIZED VIEW library_dashboard_stats AS (
                SELECT
                    d.date::date AS id,
                    d.date::date AS date,
                    (SELECT COUNT(*) FROM library_book WHERE active = true) AS total_books,
                    (SELECT COUNT(*) FROM library_member WHERE active = true) AS total_members,
                    (SELECT COUNT(*) FROM library_loan WHERE state = 'active') AS active_loans,
                    COUNT(CASE WHEN ll.loan_date::date = d.date THEN 1 END) AS books_borrowed_today,
                    COUNT(CASE WHEN ll.return_date::date = d.date THEN 1 END) AS books_returned_today,
                    COALESCE(SUM(CASE WHEN lf.date::date = d.date THEN lf.amount ELSE 0 END), 0) AS revenue_today
                FROM
                    generate_series(
                        CURRENT_DATE - INTERVAL '30 days',
                        CURRENT_DATE,
                        '1 day'::interval
                    ) AS d(date)
                LEFT JOIN
                    library_loan ll ON ll.loan_date::date = d.date OR ll.return_date::date = d.date
                LEFT JOIN
                    library_fine lf ON lf.date::date = d.date
                GROUP BY
                    d.date
            )
        """
        self.env.cr.execute(query)
        # Create index untuk performance
        self.env.cr.execute("CREATE INDEX IF NOT EXISTS library_dashboard_stats_date_idx ON library_dashboard_stats (date)")

    @api.model
    def refresh_stats(self):
        """
        Refresh materialized view.
        Bisa dipanggil manual atau via cron job.
        """
        self.env.cr.execute("REFRESH MATERIALIZED VIEW library_dashboard_stats")
        return True
```

**Scheduled Action untuk Auto-Refresh:**

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
            <field name="numbercall">-1</field>
            <field name="active">True</field>
        </record>
    </data>
</odoo>
```

---

## 3. Best Practices untuk Database Views

### ✅ DO

```python
# 1. Selalu gunakan row_number() untuk generate ID
SELECT row_number() OVER () AS id, ...

# 2. Gunakan COALESCE untuk handle NULL
COALESCE(SUM(amount), 0) AS total

# 3. Index pada field yang sering di-filter
CREATE INDEX idx_name ON view_name (field_name)

# 4. Drop view sebelum create
tools.drop_view_if_exists(self.env.cr, self._table)

# 5. Gunakan LEFT JOIN untuk relasi optional
LEFT JOIN table2 ON table1.id = table2.foreign_id

# 6. Group by semua non-aggregate fields
GROUP BY field1, field2, field3
```

### ❌ DON'T

```python
# 1. JANGAN lupa _auto = False
_auto = False  # WAJIB!

# 2. JANGAN buat computed field di SQL view model
# (sudah read-only, tidak perlu compute)

# 3. JANGAN gunakan search() untuk update
# SQL views adalah READ-ONLY

# 4. JANGAN lupa readonly=True di semua field
field_name = fields.Char(readonly=True)

# 5. JANGAN hardcode date range, gunakan parameter
# BAD: WHERE date > '2024-01-01'
# GOOD: WHERE date > CURRENT_DATE - INTERVAL '30 days'
```

---

## 4. Filtering Data pada Inherited Models

### Use Case: Inherit Model tapi Filter Data Tertentu

Skenario: Kita ingin membuat model khusus untuk "Premium Members" yang inherit dari `library.member` tapi hanya menampilkan member dengan tipe premium.

### Metode 1: Domain Default (_domain)

```python
# models/library_member_premium.py
from odoo import models, fields, api

class LibraryMemberPremium(models.Model):
    _name = 'library.member.premium'
    _description = 'Premium Library Members'
    _inherit = 'library.member'
    _table = 'library_member'  # Gunakan table yang sama
    _auto = False  # Tidak buat table baru

    # Override default domain
    def _search(self, domain, offset=0, limit=None, order=None, access_rights_uid=None):
        """
        Override _search untuk inject domain filter otomatis.
        Semua query ke model ini akan auto-filter membership_type = 'premium'.
        """
        # Tambahkan filter premium ke domain
        domain = domain or []
        domain = ['&', ('membership_type', '=', 'premium')] + domain
        return super()._search(domain, offset=offset, limit=limit, order=order, access_rights_uid=access_rights_uid)

    @api.model
    def search_read(self, domain=None, fields=None, offset=0, limit=None, order=None):
        """Override search_read juga untuk konsistensi."""
        domain = domain or []
        domain = ['&', ('membership_type', '=', 'premium')] + domain
        return super().search_read(domain, fields, offset, limit, order)
```

**Kelebihan:**
- Semua operasi search otomatis ter-filter
- Tidak perlu ubah views atau actions
- Transparent untuk user

**Kekurangan:**
- Masih bisa bypass dengan `sudo()` atau direct SQL
- Lebih kompleks untuk maintain

---

### Metode 2: SQL View dengan Filter (Recommended)

```python
# models/library_member_premium.py
from odoo import models, fields, tools

class LibraryMemberPremium(models.Model):
    _name = 'library.member.premium'
    _description = 'Premium Library Members'
    _auto = False
    _rec_name = 'name'
    _order = 'name'

    # Copy fields dari library.member yang diperlukan
    name = fields.Char(string='Name', readonly=True)
    email = fields.Char(string='Email', readonly=True)
    phone = fields.Char(string='Phone', readonly=True)
    membership_number = fields.Char(string='Membership Number', readonly=True)
    membership_type = fields.Selection([
        ('regular', 'Regular'),
        ('premium', 'Premium'),
        ('vip', 'VIP'),
    ], string='Type', readonly=True)
    membership_date = fields.Date(string='Member Since', readonly=True)
    active = fields.Boolean(string='Active', readonly=True)
    partner_id = fields.Many2one('res.partner', string='Partner', readonly=True)
    
    # Computed fields khusus
    total_loans = fields.Integer(string='Total Loans', readonly=True)
    active_loans = fields.Integer(string='Active Loans', readonly=True)

    def init(self):
        tools.drop_view_if_exists(self.env.cr, self._table)
        query = """
            CREATE OR REPLACE VIEW library_member_premium AS (
                SELECT
                    lm.id,
                    lm.name,
                    lm.email,
                    lm.phone,
                    lm.membership_number,
                    lm.membership_type,
                    lm.membership_date,
                    lm.active,
                    lm.partner_id,
                    COUNT(ll.id) AS total_loans,
                    COUNT(CASE WHEN ll.state = 'active' THEN 1 END) AS active_loans
                FROM
                    library_member lm
                LEFT JOIN
                    library_loan ll ON ll.member_id = lm.id
                WHERE
                    lm.membership_type = 'premium'
                    AND lm.active = true
                GROUP BY
                    lm.id,
                    lm.name,
                    lm.email,
                    lm.phone,
                    lm.membership_number,
                    lm.membership_type,
                    lm.membership_date,
                    lm.active,
                    lm.partner_id
            )
        """
        self.env.cr.execute(query)
```

**Kelebihan:**
- Filter di level database, sangat cepat
- Tidak bisa di-bypass
- Bisa tambahkan agregasi (total_loans, dll)

**Kekurangan:**
- Read-only, tidak bisa create/write/delete
- Perlu define ulang fields yang diperlukan

---

### Metode 3: Record Rules (Security-Based Filter)

```python
# models/library_member_premium.py
from odoo import models, fields

class LibraryMemberPremium(models.Model):
    _name = 'library.member.premium'
    _description = 'Premium Library Members'
    _inherit = 'library.member'
    _table = 'library_member'  # Gunakan table yang sama
```

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

**Kelebihan:**
- Bisa CRUD (create, write, delete)
- Filter via security rules
- Mudah maintain

**Kekurangan:**
- Bisa di-bypass dengan `sudo()`
- Tidak bisa tambahkan computed fields agregat

---

### Metode 4: Proxy Model dengan Property

```python
# models/library_member_premium.py
from odoo import models, fields, api

class LibraryMemberPremium(models.Model):
    _name = 'library.member.premium'
    _description = 'Premium Library Members'
    _inherit = 'library.member'
    _table = 'library_member'

    # Override default_get untuk set default filter
    @api.model
    def default_get(self, fields_list):
        res = super().default_get(fields_list)
        res['membership_type'] = 'premium'
        return res

    # Override create untuk force premium type
    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            vals['membership_type'] = 'premium'
        return super().create(vals_list)

    # Override write untuk prevent changing type
    def write(self, vals):
        if 'membership_type' in vals and vals['membership_type'] != 'premium':
            vals.pop('membership_type')
        return super().write(vals)

    # Override search untuk auto-filter
    @api.model
    def _search(self, domain, offset=0, limit=None, order=None, access_rights_uid=None):
        domain = domain or []
        domain = ['&', ('membership_type', '=', 'premium')] + domain
        return super()._search(domain, offset, offset, limit, order, access_rights_uid)
```

---

## 5. Contoh Lengkap: Library Book Available View

Model khusus untuk menampilkan buku yang tersedia (available copies > 0).

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
    popularity_score = fields.Float(string='Popularity', readonly=True)

    def init(self):
        tools.drop_view_if_exists(self.env.cr, self._table)
        query = """
            CREATE OR REPLACE VIEW library_book_available AS (
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
                    COALESCE(
                        (SELECT COUNT(*) FROM library_loan WHERE book_id = lb.id) * 1.0 / 
                        NULLIF(EXTRACT(days FROM (CURRENT_DATE - lb.create_date)), 0),
                        0
                    ) AS popularity_score
                FROM
                    library_book lb
                LEFT JOIN
                    library_book_copy lbc ON lbc.book_id = lb.id
                WHERE
                    lb.active = true
                GROUP BY
                    lb.id,
                    lb.name,
                    lb.author,
                    lb.isbn,
                    lb.category_id,
                    lb.create_date
                HAVING
                    COUNT(CASE WHEN lbc.state = 'available' THEN 1 END) > 0
            )
        """
        self.env.cr.execute(query)

    def action_create_loan(self):
        """
        Action untuk buka wizard peminjaman.
        Bisa dipanggil dari tree view.
        """
        self.ensure_one()
        return {
            'name': 'Create Loan',
            'type': 'ir.actions.act_window',
            'res_model': 'library.loan.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_book_id': self.book_id.id,
            },
        }
```

**View untuk Available Books:**

```xml
<!-- views/library_book_available_views.xml -->
<odoo>
    <!-- Tree View -->
    <record id="view_library_book_available_tree" model="ir.ui.view">
        <field name="name">library.book.available.tree</field>
        <field name="model">library.book.available</field>
        <field name="arch" type="xml">
            <tree string="Available Books" create="false" edit="false" delete="false">
                <field name="book_name"/>
                <field name="author"/>
                <field name="category_id"/>
                <field name="available_copies"/>
                <field name="borrowed_copies"/>
                <field name="total_copies"/>
                <field name="popularity_score" widget="progressbar"/>
                <button name="action_create_loan" 
                        string="Loan" 
                        type="object" 
                        class="btn-primary"
                        icon="fa-book"/>
            </tree>
        </field>
    </record>

    <!-- Search View -->
    <record id="view_library_book_available_search" model="ir.ui.view">
        <field name="name">library.book.available.search</field>
        <field name="model">library.book.available</field>
        <field name="arch" type="xml">
            <search>
                <field name="book_name"/>
                <field name="author"/>
                <field name="category_id"/>
                <filter name="high_availability" 
                        string="High Availability" 
                        domain="[('available_copies', '>=', 3)]"/>
                <filter name="popular" 
                        string="Popular" 
                        domain="[('popularity_score', '>', 0.5)]"/>
                <group expand="0" string="Group By">
                    <filter name="group_category" 
                            string="Category" 
                            context="{'group_by': 'category_id'}"/>
                    <filter name="group_author" 
                            string="Author" 
                            context="{'group_by': 'author'}"/>
                </group>
            </search>
        </field>
    </record>

    <!-- Action -->
    <record id="action_library_book_available" model="ir.actions.act_window">
        <field name="name">Available Books</field>
        <field name="res_model">library.book.available</field>
        <field name="view_mode">tree,form</field>
        <field name="context">{'search_default_high_availability': 1}</field>
    </record>

    <!-- Menu -->
    <menuitem id="menu_library_book_available"
              name="Available Books"
              parent="menu_library_root"
              action="action_library_book_available"
              sequence="15"/>
</odoo>
```

---

## 6. Performance Tips

### Indexing untuk SQL Views

```python
def init(self):
    tools.drop_view_if_exists(self.env.cr, self._table)
    
    # Create view
    self.env.cr.execute("""
        CREATE OR REPLACE VIEW my_view AS (...)
    """)
    
    # Create indexes untuk performance
    self.env.cr.execute("""
        CREATE INDEX IF NOT EXISTS my_view_date_idx 
        ON my_view (date)
    """)
    
    self.env.cr.execute("""
        CREATE INDEX IF NOT EXISTS my_view_member_idx 
        ON my_view (member_id)
    """)
```

### Gunakan EXPLAIN untuk Optimize Query

```python
# Di Odoo shell atau psql
self.env.cr.execute("EXPLAIN ANALYZE SELECT * FROM library_loan_report WHERE member_id = 1")
print(self.env.cr.fetchall())
```

### Materialized View vs Regular View

| Aspek | Regular View | Materialized View |
|-------|-------------|-------------------|
| Speed | Slower (query setiap kali) | Faster (data tersimpan) |
| Storage | Tidak pakai storage | Pakai storage |
| Freshness | Always fresh | Perlu refresh manual |
| Use Case | Data real-time | Dashboard, reports |

---

## 7. Troubleshooting

### Error: "relation does not exist"

```bash
# Solusi: Upgrade module untuk trigger init()
docker compose exec odoo odoo -d odoo -u library_management
```

### Error: "column must appear in GROUP BY"

```sql
-- BAD: field3 tidak di-aggregate dan tidak di-group
SELECT field1, field2, field3, SUM(field4)
FROM table
GROUP BY field1, field2

-- GOOD: semua non-aggregate field harus di GROUP BY
SELECT field1, field2, field3, SUM(field4)
FROM table
GROUP BY field1, field2, field3
```

### View Tidak Update Setelah Ubah Query

```python
# Solusi 1: Drop manual di psql
DROP VIEW IF EXISTS library_loan_report CASCADE;

# Solusi 2: Upgrade module dengan force
docker compose exec odoo odoo -d odoo -u library_management --stop-after-init

# Solusi 3: Gunakan tools.drop_view_if_exists() di init()
```

---

## 8. Checklist

```
[ ] _auto = False untuk SQL view models
[ ] _table sesuai dengan nama view di SQL
[ ] Semua field readonly=True
[ ] init() method untuk create view
[ ] tools.drop_view_if_exists() sebelum CREATE
[ ] row_number() OVER () AS id untuk generate ID
[ ] GROUP BY semua non-aggregate fields
[ ] COALESCE untuk handle NULL values
[ ] Index pada field yang sering di-filter
[ ] Test query dengan EXPLAIN ANALYZE
[ ] create="false" edit="false" delete="false" di tree view
[ ] Dokumentasi query SQL dengan comment
```

---

## Kesimpulan

**Gunakan SQL Views ketika:**
- Butuh reporting/analytics kompleks
- Query melibatkan banyak JOIN dan agregasi
- Data read-only (tidak perlu CRUD)
- Performance penting

**Gunakan Inherited Model dengan Filter ketika:**
- Butuh CRUD operations
- Filter sederhana (1-2 kondisi)
- Ingin reuse logic dari parent model
- Tidak butuh agregasi kompleks

**Best Practice:**
- SQL views untuk reporting
- Inherited model + record rules untuk business logic
- Materialized views untuk dashboard yang di-refresh berkala
- Index pada field yang sering di-query
