# Bab 16: Contoh Praktis - Database Views & Filtering

> **Tahap:** 4 Data & Analitik | **Prasyarat:** Bab 5, 6, 7, 15 | **Estimasi:** ± 3 jam | **Versi:** Odoo 18 (catatan Odoo 19)

Bab ini adalah contoh praktis dari konsep di Bab 15 (SQL view, materialized view, `_auto = False`, `init()`). Teori dan best practice-nya tidak diulang di sini, lihat Bab 15. Studi kasusnya memakai data penjualan (`sale`), bukan modul Library.

## Tujuan Belajar

- Membangun modul analitik utuh (`sales_analytics`) dari model SQL view sampai menu
- Membedakan kapan memakai materialized view dan view biasa pada kasus nyata
- Menulis query SQL yang agregasinya benar (menghindari double counting akibat JOIN)
- Menyusun view list, pivot, graph, dan search untuk model read-only
- Menjadwalkan refresh materialized view dengan cron dan mengujinya

## Studi Kasus: Sales Analytics Dashboard

Tiga model read-only berbasis SQL:

| No | Model | Jenis | Isi |
|----|-------|-------|-----|
| 1 | `sales.summary.view` | Materialized view | Agregasi penjualan per salesperson per hari |
| 2 | `product.performance.view` | View biasa (real-time) | Performa tiap produk |
| 3 | `res.partner.vip` | View biasa + `HAVING` | Customer VIP berdasarkan total pembelian |

---

## 1. Setup Module

### Struktur Direktori

```
sales_analytics/
├── __init__.py
├── __manifest__.py
├── models/
│   ├── __init__.py
│   ├── sales_summary_view.py
│   ├── product_performance_view.py
│   └── res_partner_vip.py
├── views/
│   ├── sales_summary_views.xml
│   ├── product_performance_views.xml
│   ├── res_partner_vip_views.xml
│   └── menu.xml
├── security/
│   └── ir.model.access.csv
├── data/
│   └── cron_refresh_views.xml
└── tests/
    ├── __init__.py
    └── test_sales_summary_view.py
```

### __manifest__.py

```python
{
    'name': 'Sales Analytics Dashboard',
    'version': '18.0.1.0.0',
    'category': 'Sales/Analytics',
    'summary': 'Advanced sales analytics with database views',
    'depends': ['sale_margin', 'stock'],
    'data': [
        'security/ir.model.access.csv',
        'data/cron_refresh_views.xml',
        'views/sales_summary_views.xml',
        'views/product_performance_views.xml',
        'views/res_partner_vip_views.xml',
        'views/menu.xml',
    ],
    'installable': True,
    'application': True,
    'license': 'LGPL-3',
}
```

Kenapa `depends` seperti ini:
- `sale_margin` (otomatis menarik `sale`) menyediakan kolom `purchase_price` di `sale_order_line` yang dipakai query.
- `stock` menyediakan tabel `stock_quant` dan `stock_location`.
- Query SQL membaca tabel langsung, jadi modul pemilik tabelnya **wajib** ada di `depends`, kalau tidak `init()` gagal saat install.

### models/__init__.py

```python
from . import sales_summary_view
from . import product_performance_view
from . import res_partner_vip
```

### tests/__init__.py

```python
from . import test_sales_summary_view
```

---

## 2. Sales Summary (Materialized View)

Dipilih materialized karena query-nya berat dan datanya cukup di-update tiap jam.

### Model

```python
# models/sales_summary_view.py
from datetime import timedelta

from odoo import models, fields, tools, api
from odoo.exceptions import UserError


class SalesSummaryView(models.Model):
    _name = 'sales.summary.view'
    _description = 'Sales Summary Analytics'
    _auto = False
    _rec_name = 'salesperson_id'
    _order = 'total_sales desc'

    # Dimensions
    salesperson_id = fields.Many2one('res.users', string='Salesperson', readonly=True)
    team_id = fields.Many2one('crm.team', string='Sales Team', readonly=True)
    date = fields.Date(string='Date', readonly=True)
    month = fields.Char(string='Month', readonly=True)
    year = fields.Char(string='Year', readonly=True)

    # Metrics
    order_count = fields.Integer(string='Orders', readonly=True)
    total_sales = fields.Monetary(string='Total Sales', readonly=True, currency_field='currency_id')
    total_cost = fields.Monetary(string='Total Cost', readonly=True, currency_field='currency_id')
    total_margin = fields.Monetary(string='Margin', readonly=True, currency_field='currency_id')
    # Persentase/rata-rata tidak boleh dijumlah di pivot, jadi pakai aggregator avg
    margin_percent = fields.Float(string='Margin %', readonly=True, aggregator='avg')
    avg_order_value = fields.Monetary(
        string='Avg Order Value', readonly=True,
        currency_field='currency_id', aggregator='avg',
    )
    customer_count = fields.Integer(string='Customers', readonly=True)
    currency_id = fields.Many2one('res.currency', string='Currency', readonly=True)

    def init(self):
        """Buat materialized view. Dipanggil saat install/upgrade modul."""
        # drop_view_if_exists hanya untuk VIEW biasa; materialized view
        # harus di-drop dengan perintah sendiri.
        self.env.cr.execute("DROP MATERIALIZED VIEW IF EXISTS sales_summary_view CASCADE")
        self.env.cr.execute("""
            CREATE MATERIALIZED VIEW sales_summary_view AS (
                SELECT
                    ROW_NUMBER() OVER (ORDER BY so.user_id, DATE(so.date_order)) AS id,
                    so.user_id AS salesperson_id,
                    so.team_id,
                    DATE(so.date_order) AS date,
                    TO_CHAR(so.date_order, 'YYYY-MM') AS month,
                    TO_CHAR(so.date_order, 'YYYY') AS year,
                    COUNT(DISTINCT so.id) AS order_count,
                    SUM(so.amount_total) AS total_sales,
                    SUM(COALESCE(sol.cost, 0)) AS total_cost,
                    SUM(so.amount_total) - SUM(COALESCE(sol.cost, 0)) AS total_margin,
                    CASE
                        WHEN SUM(so.amount_total) > 0 THEN
                            ((SUM(so.amount_total) - SUM(COALESCE(sol.cost, 0)))
                              / SUM(so.amount_total)) * 100
                        ELSE 0
                    END AS margin_percent,
                    AVG(so.amount_total) AS avg_order_value,
                    COUNT(DISTINCT so.partner_id) AS customer_count,
                    so.currency_id
                FROM sale_order so
                -- Hitung biaya per order DULU (subquery). Kalau sale_order di-JOIN
                -- langsung ke sale_order_line, amount_total ikut terhitung
                -- sebanyak jumlah baris order (double counting).
                LEFT JOIN (
                    SELECT order_id, SUM(purchase_price * product_uom_qty) AS cost
                    FROM sale_order_line
                    GROUP BY order_id
                ) sol ON sol.order_id = so.id
                WHERE
                    so.state = 'sale'
                    AND so.date_order >= CURRENT_DATE - INTERVAL '365 days'
                GROUP BY
                    so.user_id,
                    so.team_id,
                    DATE(so.date_order),
                    TO_CHAR(so.date_order, 'YYYY-MM'),
                    TO_CHAR(so.date_order, 'YYYY'),
                    so.currency_id
            )
        """)

        # Index untuk kolom yang sering difilter (hilang saat view di-drop, jadi dibuat ulang)
        self.env.cr.execute("""
            CREATE INDEX IF NOT EXISTS sales_summary_view_salesperson_idx
            ON sales_summary_view (salesperson_id)
        """)
        self.env.cr.execute("""
            CREATE INDEX IF NOT EXISTS sales_summary_view_date_idx
            ON sales_summary_view (date)
        """)

    @api.model
    def refresh_view(self):
        """Refresh materialized view. Dipanggil oleh cron dan test."""
        try:
            self.env.cr.execute("REFRESH MATERIALIZED VIEW sales_summary_view")
        except Exception as e:
            raise UserError(f"Failed to refresh sales summary view: {e}")
        return True

    def action_view_orders(self):
        """Buka sale order yang membentuk baris ini."""
        self.ensure_one()
        day_start = fields.Datetime.to_datetime(self.date)
        return {
            'name': 'Sale Orders',
            'type': 'ir.actions.act_window',
            'res_model': 'sale.order',
            'view_mode': 'list,form',
            # date_order bertipe datetime, jadi filter dengan rentang satu hari
            # (SQL di atas memakai tanggal UTC)
            'domain': [
                ('user_id', '=', self.salesperson_id.id),
                ('date_order', '>=', day_start),
                ('date_order', '<', day_start + timedelta(days=1)),
                ('state', '=', 'sale'),
            ],
        }
```

Poin penting:
- Filter `state = 'sale'` hanya mengambil order terkonfirmasi. Jika instansimu memakai state `done` (order terkunci), tambahkan `IN ('sale', 'done')`. Sesuaikan dengan kebutuhan bisnismu.
- `aggregator='avg'` mengatur cara pivot/graph menggabungkan nilai. Defaultnya `sum`, yang salah untuk persentase dan rata-rata. Nama lama `group_operator` sudah diganti `aggregator`.
- `customer_count` pada pivot tetap dijumlahkan antar baris sehingga bisa menghitung customer yang sama lebih dari sekali. Untuk angka distinct yang tepat, hitung di level query yang sesuai dimensinya.
- Untuk pola dasar `init()`, `_auto = False`, dan `row_number()`, lihat Bab 15.

> **Beda di Odoo 19:** Atribut field `aggregator` berlaku di Odoo 18 dan 19 (pengganti `group_operator`). Jika kamu memanggil agregasi dari Python, `read_group` terdokumentasi di Odoo 18, sedangkan di Odoo 19 yang terdokumentasi hanya `_read_group`.

### Cron untuk Refresh

Materialized view tidak otomatis ter-update, jadi dijadwalkan refresh tiap jam. Format record cron sama dengan Bab 7.

```xml
<!-- data/cron_refresh_views.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="cron_refresh_sales_summary" model="ir.cron">
            <field name="name">Refresh Sales Summary View</field>
            <field name="model_id" ref="model_sales_summary_view"/>
            <field name="state">code</field>
            <field name="code">model.refresh_view()</field>
            <field name="user_id" ref="base.user_root"/>
            <field name="interval_number">1</field>
            <field name="interval_type">hours</field>
            <field name="active" eval="True"/>
            <field name="priority">5</field>
        </record>
    </data>
</odoo>
```

Field `numbercall` dan `doall` sengaja tidak dipakai (lihat catatan di Bab 7).

### Views

```xml
<!-- views/sales_summary_views.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- List View -->
    <record id="view_sales_summary_list" model="ir.ui.view">
        <field name="name">sales.summary.view.list</field>
        <field name="model">sales.summary.view</field>
        <field name="arch" type="xml">
            <list string="Sales Summary" create="false" edit="false" delete="false">
                <field name="salesperson_id"/>
                <field name="team_id"/>
                <field name="date"/>
                <field name="order_count"/>
                <field name="customer_count"/>
                <field name="total_sales" sum="Total"/>
                <field name="total_cost" sum="Total"/>
                <field name="total_margin" sum="Total"/>
                <!-- Nilai sudah 0-100, jadi JANGAN pakai widget="percentage"
                     (widget itu mengalikan 100 lagi) -->
                <field name="margin_percent"/>
                <field name="avg_order_value"/>
                <field name="currency_id" column_invisible="1"/>
                <button name="action_view_orders"
                        string="View Orders"
                        type="object"
                        icon="fa-list"/>
            </list>
        </field>
    </record>

    <!-- Pivot View -->
    <record id="view_sales_summary_pivot" model="ir.ui.view">
        <field name="name">sales.summary.view.pivot</field>
        <field name="model">sales.summary.view</field>
        <field name="arch" type="xml">
            <pivot string="Sales Analysis">
                <field name="salesperson_id" type="row"/>
                <field name="month" type="col"/>
                <field name="total_sales" type="measure"/>
                <field name="total_margin" type="measure"/>
                <field name="order_count" type="measure"/>
            </pivot>
        </field>
    </record>

    <!-- Graph View -->
    <record id="view_sales_summary_graph" model="ir.ui.view">
        <field name="name">sales.summary.view.graph</field>
        <field name="model">sales.summary.view</field>
        <field name="arch" type="xml">
            <graph string="Sales Trend" type="line">
                <field name="date" interval="month" type="row"/>
                <field name="total_sales" type="measure"/>
                <field name="total_margin" type="measure"/>
            </graph>
        </field>
    </record>

    <!-- Search View -->
    <record id="view_sales_summary_search" model="ir.ui.view">
        <field name="name">sales.summary.view.search</field>
        <field name="model">sales.summary.view</field>
        <field name="arch" type="xml">
            <search>
                <field name="salesperson_id"/>
                <field name="team_id"/>
                <field name="date"/>
                <filter name="this_month"
                        string="This Month"
                        domain="[('month', '=', context_today().strftime('%Y-%m'))]"/>
                <filter name="this_year"
                        string="This Year"
                        domain="[('year', '=', context_today().strftime('%Y'))]"/>
                <filter name="high_margin"
                        string="High Margin (&gt;30%)"
                        domain="[('margin_percent', '&gt;', 30)]"/>
                <separator/>
                <filter name="group_salesperson"
                        string="Salesperson"
                        context="{'group_by': 'salesperson_id'}"/>
                <filter name="group_team"
                        string="Team"
                        context="{'group_by': 'team_id'}"/>
                <filter name="group_month"
                        string="Month"
                        context="{'group_by': 'month'}"/>
            </search>
        </field>
    </record>

    <!-- Action -->
    <record id="action_sales_summary" model="ir.actions.act_window">
        <field name="name">Sales Summary</field>
        <field name="res_model">sales.summary.view</field>
        <field name="view_mode">list,pivot,graph</field>
        <field name="context">{'search_default_this_month': 1}</field>
    </record>
</odoo>
```

Catatan view:
- Odoo 18 memakai `<list>` (bukan `<tree>`) dan `view_mode` `list`. Suffix nama view juga `.list`.
- Di pivot/graph, atribut `type` bernilai `row`, `col`, atau `measure`; `interval` dipakai untuk field tanggal (`day`, `week`, `month`, `quarter`, `year`). Detail tipe view ada di Bab 5.
- `column_invisible="1"` menyembunyikan kolom pembantu `currency_id` (dibutuhkan widget monetary).

---

## 3. Product Performance (View Biasa)

Data produk dan stok yang perlu real-time, jadi memakai view biasa (bukan materialized).

```python
# models/product_performance_view.py
from odoo import models, fields, tools


class ProductPerformanceView(models.Model):
    _name = 'product.performance.view'
    _description = 'Product Performance Analytics'
    _auto = False
    _rec_name = 'product_id'
    _order = 'total_qty_sold desc'

    product_id = fields.Many2one('product.product', string='Product', readonly=True)
    product_tmpl_id = fields.Many2one('product.template', string='Product Template', readonly=True)
    categ_id = fields.Many2one('product.category', string='Category', readonly=True)

    # Sales metrics
    total_qty_sold = fields.Float(string='Qty Sold', readonly=True)
    total_revenue = fields.Monetary(string='Revenue', readonly=True, currency_field='currency_id')
    total_cost = fields.Monetary(string='Cost', readonly=True, currency_field='currency_id')
    total_margin = fields.Monetary(string='Margin', readonly=True, currency_field='currency_id')
    margin_percent = fields.Float(string='Margin %', readonly=True, aggregator='avg')

    # Performance indicators
    order_count = fields.Integer(string='Orders', readonly=True)
    customer_count = fields.Integer(string='Customers', readonly=True)
    avg_price = fields.Monetary(
        string='Avg Price', readonly=True,
        currency_field='currency_id', aggregator='avg',
    )
    last_sale_date = fields.Date(string='Last Sale', readonly=True)
    days_since_last_sale = fields.Integer(
        string='Days Since Last Sale', readonly=True, aggregator='avg',
    )

    # Stock info
    qty_available = fields.Float(string='On Hand', readonly=True)

    currency_id = fields.Many2one('res.currency', string='Currency', readonly=True)

    def init(self):
        tools.drop_view_if_exists(self.env.cr, self._table)
        self.env.cr.execute("""
            CREATE OR REPLACE VIEW product_performance_view AS (
                SELECT
                    pp.id AS id,
                    pp.id AS product_id,
                    pt.id AS product_tmpl_id,
                    pt.categ_id,
                    COALESCE(s.total_qty_sold, 0) AS total_qty_sold,
                    COALESCE(s.total_revenue, 0) AS total_revenue,
                    COALESCE(s.total_cost, 0) AS total_cost,
                    COALESCE(s.total_revenue, 0) - COALESCE(s.total_cost, 0) AS total_margin,
                    CASE
                        WHEN COALESCE(s.total_revenue, 0) > 0 THEN
                            ((s.total_revenue - s.total_cost) / s.total_revenue) * 100
                        ELSE 0
                    END AS margin_percent,
                    COALESCE(s.order_count, 0) AS order_count,
                    COALESCE(s.customer_count, 0) AS customer_count,
                    COALESCE(s.avg_price, 0) AS avg_price,
                    s.last_sale_date,
                    -- date - date menghasilkan integer, jadi TIDAK perlu EXTRACT
                    (CURRENT_DATE - s.last_sale_date) AS days_since_last_sale,
                    COALESCE(st.qty_available, 0) AS qty_available,
                    s.currency_id
                FROM product_product pp
                INNER JOIN product_template pt ON pp.product_tmpl_id = pt.id
                -- Penjualan dan stok diagregasi di subquery terpisah supaya
                -- JOIN keduanya tidak saling menggandakan baris
                LEFT JOIN (
                    SELECT
                        sol.product_id,
                        SUM(sol.product_uom_qty) AS total_qty_sold,
                        SUM(sol.price_subtotal) AS total_revenue,
                        SUM(sol.purchase_price * sol.product_uom_qty) AS total_cost,
                        COUNT(DISTINCT so.id) AS order_count,
                        COUNT(DISTINCT so.partner_id) AS customer_count,
                        AVG(sol.price_unit) AS avg_price,
                        MAX(so.date_order)::date AS last_sale_date,
                        -- Penyederhanaan: asumsi satu mata uang per produk
                        MAX(so.currency_id) AS currency_id
                    FROM sale_order_line sol
                    INNER JOIN sale_order so ON sol.order_id = so.id
                    WHERE
                        so.state = 'sale'
                        AND so.date_order >= CURRENT_DATE - INTERVAL '365 days'
                    GROUP BY sol.product_id
                ) s ON s.product_id = pp.id
                LEFT JOIN (
                    SELECT sq.product_id, SUM(sq.quantity) AS qty_available
                    FROM stock_quant sq
                    INNER JOIN stock_location sl ON sl.id = sq.location_id
                    WHERE sl.usage = 'internal'
                    GROUP BY sq.product_id
                ) st ON st.product_id = pp.id
                WHERE pt.active = true
            )
        """)

    def action_view_sales(self):
        """Lihat sale order line untuk produk ini."""
        self.ensure_one()
        return {
            'name': 'Sales',
            'type': 'ir.actions.act_window',
            'res_model': 'sale.order.line',
            'view_mode': 'list,form',
            'domain': [('product_id', '=', self.product_id.id)],
            'context': {'create': False},
        }

    def action_open_product(self):
        """Buka form produk."""
        self.ensure_one()
        return {
            'name': 'Product',
            'type': 'ir.actions.act_window',
            'res_model': 'product.product',
            'res_id': self.product_id.id,
            'view_mode': 'form',
        }
```

Pelajaran dari query ini:
- Dua agregasi berbeda (penjualan dan stok) jangan di-JOIN langsung ke tabel yang sama lalu di-`SUM`; baris saling berkali lipat. Agregasikan di subquery masing-masing, lalu JOIN hasilnya per produk.
- Selisih dua `date` di PostgreSQL sudah berupa integer hari, jadi tidak perlu `EXTRACT(days FROM ...)`.

Views dan action (pola sama dengan Bagian 2, lebih ringkas):

```xml
<!-- views/product_performance_views.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_product_performance_list" model="ir.ui.view">
        <field name="name">product.performance.view.list</field>
        <field name="model">product.performance.view</field>
        <field name="arch" type="xml">
            <list string="Product Performance" create="false" edit="false" delete="false">
                <field name="product_id"/>
                <field name="categ_id"/>
                <field name="total_qty_sold" sum="Total"/>
                <field name="total_revenue" sum="Total"/>
                <field name="total_margin" sum="Total"/>
                <field name="margin_percent"/>
                <field name="last_sale_date"/>
                <field name="qty_available"/>
                <field name="currency_id" column_invisible="1"/>
                <button name="action_view_sales" string="Sales" type="object" icon="fa-list"/>
                <button name="action_open_product" string="Product" type="object" icon="fa-external-link"/>
            </list>
        </field>
    </record>

    <record id="view_product_performance_search" model="ir.ui.view">
        <field name="name">product.performance.view.search</field>
        <field name="model">product.performance.view</field>
        <field name="arch" type="xml">
            <search>
                <field name="product_id"/>
                <field name="categ_id"/>
                <filter name="no_sales" string="No Sales (365 days)"
                        domain="[('order_count', '=', 0)]"/>
                <filter name="group_categ" string="Category"
                        context="{'group_by': 'categ_id'}"/>
            </search>
        </field>
    </record>

    <record id="action_product_performance" model="ir.actions.act_window">
        <field name="name">Product Performance</field>
        <field name="res_model">product.performance.view</field>
        <field name="view_mode">list</field>
    </record>
</odoo>
```

---

## 4. VIP Customers (View Biasa dengan Filter `HAVING`)

Model ini berdiri sendiri (`_name` baru, `_auto = False`), bukan `_inherit`. Ia hanya menampilkan customer yang total pembeliannya melewati ambang. Untuk filtering model yang benar-benar di-inherit (`_inherit` + domain), lihat Bab 15.

```python
# models/res_partner_vip.py
from odoo import models, fields, tools


class ResPartnerVIP(models.Model):
    _name = 'res.partner.vip'
    _description = 'VIP Customers'
    _auto = False
    _rec_name = 'name'
    _order = 'total_purchased desc'

    partner_id = fields.Many2one('res.partner', string='Partner', readonly=True)
    name = fields.Char(string='Name', readonly=True)
    email = fields.Char(string='Email', readonly=True)
    phone = fields.Char(string='Phone', readonly=True)
    country_id = fields.Many2one('res.country', string='Country', readonly=True)

    total_purchased = fields.Monetary(string='Total Purchased', readonly=True, currency_field='currency_id')
    order_count = fields.Integer(string='Orders', readonly=True)
    avg_order_value = fields.Monetary(
        string='Avg Order', readonly=True,
        currency_field='currency_id', aggregator='avg',
    )
    last_order_date = fields.Date(string='Last Order', readonly=True)
    days_since_last_order = fields.Integer(
        string='Days Since Last Order', readonly=True, aggregator='avg',
    )
    vip_level = fields.Selection([
        ('gold', 'Gold'),
        ('platinum', 'Platinum'),
        ('diamond', 'Diamond'),
    ], string='VIP Level', readonly=True)
    currency_id = fields.Many2one('res.currency', string='Currency', readonly=True)

    def init(self):
        tools.drop_view_if_exists(self.env.cr, self._table)
        self.env.cr.execute("""
            CREATE OR REPLACE VIEW res_partner_vip AS (
                SELECT
                    rp.id AS id,
                    rp.id AS partner_id,
                    rp.name,
                    rp.email,
                    rp.phone,
                    rp.country_id,
                    SUM(so.amount_total) AS total_purchased,
                    COUNT(so.id) AS order_count,
                    AVG(so.amount_total) AS avg_order_value,
                    MAX(so.date_order)::date AS last_order_date,
                    (CURRENT_DATE - MAX(so.date_order)::date) AS days_since_last_order,
                    CASE
                        WHEN SUM(so.amount_total) >= 100000 THEN 'diamond'
                        WHEN SUM(so.amount_total) >= 50000 THEN 'platinum'
                        ELSE 'gold'
                    END AS vip_level,
                    -- Penyederhanaan: asumsi satu mata uang per customer.
                    -- Jangan masukkan currency_id ke GROUP BY: id (rp.id) bisa dobel.
                    MAX(so.currency_id) AS currency_id
                FROM res_partner rp
                INNER JOIN sale_order so ON so.partner_id = rp.id
                WHERE
                    so.state = 'sale'
                    AND rp.active = true
                    AND rp.customer_rank > 0
                GROUP BY
                    rp.id,
                    rp.name,
                    rp.email,
                    rp.phone,
                    rp.country_id
                HAVING
                    SUM(so.amount_total) >= 10000  -- minimum 10k untuk VIP
            )
        """)

    def action_view_orders(self):
        """Lihat order customer."""
        self.ensure_one()
        return {
            'name': 'Orders',
            'type': 'ir.actions.act_window',
            'res_model': 'sale.order',
            'view_mode': 'list,form',
            'domain': [('partner_id', '=', self.partner_id.id)],
        }
```

Views dan action:

```xml
<!-- views/res_partner_vip_views.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_res_partner_vip_list" model="ir.ui.view">
        <field name="name">res.partner.vip.list</field>
        <field name="model">res.partner.vip</field>
        <field name="arch" type="xml">
            <list string="VIP Customers" create="false" edit="false" delete="false">
                <field name="name"/>
                <field name="vip_level"/>
                <field name="total_purchased" sum="Total"/>
                <field name="order_count"/>
                <field name="last_order_date"/>
                <field name="currency_id" column_invisible="1"/>
                <button name="action_view_orders" string="Orders" type="object" icon="fa-list"/>
            </list>
        </field>
    </record>

    <record id="view_res_partner_vip_search" model="ir.ui.view">
        <field name="name">res.partner.vip.search</field>
        <field name="model">res.partner.vip</field>
        <field name="arch" type="xml">
            <search>
                <field name="name"/>
                <filter name="diamond" string="Diamond" domain="[('vip_level', '=', 'diamond')]"/>
                <filter name="platinum" string="Platinum" domain="[('vip_level', '=', 'platinum')]"/>
                <filter name="group_level" string="VIP Level"
                        context="{'group_by': 'vip_level'}"/>
            </search>
        </field>
    </record>

    <record id="action_res_partner_vip" model="ir.actions.act_window">
        <field name="name">VIP Customers</field>
        <field name="res_model">res.partner.vip</field>
        <field name="view_mode">list</field>
    </record>
</odoo>
```

---

## 5. Security

Model SQL view hanya perlu hak baca; tidak ada create/write/unlink.

```csv
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_sales_summary_view_user,sales.summary.view user,model_sales_summary_view,sales_team.group_sale_salesman,1,0,0,0
access_sales_summary_view_manager,sales.summary.view manager,model_sales_summary_view,sales_team.group_sale_manager,1,0,0,0
access_product_performance_view_user,product.performance.view user,model_product_performance_view,sales_team.group_sale_salesman,1,0,0,0
access_res_partner_vip_user,res.partner.vip user,model_res_partner_vip,sales_team.group_sale_salesman,1,0,0,0
access_res_partner_vip_manager,res.partner.vip manager,model_res_partner_vip,sales_team.group_sale_manager,1,0,0,0
```

Perhatikan: query SQL view mengabaikan access rights dan record rule model sumber (`sale.order`, dll.). Siapa pun yang punya akses baca ke model view ini bisa melihat semua baris agregatnya. Jika datanya sensitif, batasi grup di CSV dan tambahkan record rule pada model view itu sendiri (Bab 6).

---

## 6. Menu

```xml
<!-- views/menu.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <menuitem id="menu_sales_analytics_root"
              name="Sales Analytics"
              sequence="100"
              groups="sales_team.group_sale_salesman"/>

    <menuitem id="menu_sales_summary"
              name="Sales Summary"
              parent="menu_sales_analytics_root"
              action="action_sales_summary"
              sequence="10"/>

    <menuitem id="menu_product_performance"
              name="Product Performance"
              parent="menu_sales_analytics_root"
              action="action_product_performance"
              sequence="20"/>

    <menuitem id="menu_vip_customers"
              name="VIP Customers"
              parent="menu_sales_analytics_root"
              action="action_res_partner_vip"
              sequence="30"/>
</odoo>
```

---

## 7. Testing

Test memastikan angka di view cocok dengan data sumber. Kita sengaja memakai order dengan dua baris untuk menangkap bug double counting. Dasar menulis test ada di Bab 17.

```python
# tests/test_sales_summary_view.py
from odoo.tests import TransactionCase


class TestSalesSummaryView(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.partner = cls.env['res.partner'].create({'name': 'Test Customer'})
        cls.product = cls.env['product.product'].create({
            'name': 'Test Product',
            'list_price': 100.0,
            'standard_price': 60.0,
        })
        cls.salesperson = cls.env['res.users'].create({
            'name': 'Test Salesperson',
            'login': 'test_sales',
        })

    def test_sales_summary_view_data(self):
        """Summary harus sama dengan order sumber (tanpa double counting)."""
        order = self.env['sale.order'].create({
            'partner_id': self.partner.id,
            'user_id': self.salesperson.id,
            'order_line': [
                (0, 0, {
                    'product_id': self.product.id,
                    'product_uom_qty': 2,
                    'price_unit': 100.0,
                }),
                (0, 0, {
                    'product_id': self.product.id,
                    'product_uom_qty': 1,
                    'price_unit': 100.0,
                }),
            ],
        })
        order.action_confirm()

        # Materialized view tidak otomatis update: refresh dulu
        self.env['sales.summary.view'].refresh_view()

        summary = self.env['sales.summary.view'].search([
            ('salesperson_id', '=', self.salesperson.id),
        ])

        self.assertEqual(len(summary), 1)
        self.assertEqual(summary.order_count, 1)
        self.assertEqual(summary.total_sales, order.amount_total)

    def test_refresh_view_method(self):
        """Method refresh_view berjalan tanpa error."""
        result = self.env['sales.summary.view'].refresh_view()
        self.assertTrue(result)
```

---

## Ringkasan

- Materialized view (Sales Summary) cocok untuk dashboard berat yang boleh sedikit tertinggal; wajib di-drop dengan `DROP MATERIALIZED VIEW` dan di-refresh lewat cron.
- View biasa (Product Performance, VIP) selalu real-time; cocok untuk data yang ringan dan perlu segar.
- Modul pemilik tabel yang dibaca query (`sale_margin`, `stock`) harus ada di `depends`.
- Agregasi di SQL harus bebas double counting: agregasikan tabel "banyak" di subquery sebelum di-JOIN.
- Field model SQL view diberi `readonly=True` dan `aggregator` yang tepat (`avg` untuk persentase/rata-rata); view memakai `<list>`, bukan `<tree>`.
- Akses cukup read-only, tetapi ingat view SQL melewati record rule model sumber.

## Latihan

1. Tambahkan view pivot dan graph untuk `product.performance.view` (ukur `total_revenue` per `categ_id`), lalu daftarkan di `view_mode` action-nya.
2. Ubah Product Performance supaya hanya menampilkan produk dengan stok > 0 (tambahkan filter di search view, bukan di SQL), lalu bandingkan dengan membuatnya di SQL (`WHERE`). Kapan masing-masing lebih tepat?
3. Di pivot Sales Summary, hapus sementara `aggregator='avg'` dari `margin_percent`, upgrade modul, lalu bandingkan totalnya. Kenapa angkanya jadi tidak masuk akal?

## Lanjut ke

Bab 17: Testing.
