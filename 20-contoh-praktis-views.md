# Bab 20: Contoh Praktis - Database Views & Filtering

## Studi Kasus: Sales Analytics Dashboard

Kita akan membuat dashboard analytics untuk sales dengan beberapa views:
1. **Sales Summary View** - Agregasi penjualan per salesperson
2. **Product Performance View** - Performa produk
3. **Customer Segment View** - Segmentasi customer berdasarkan pembelian
4. **VIP Customer Model** - Inherit customer dengan filter otomatis

---

## Setup Module

### Struktur Direktori

```
sales_analytics/
├── __init__.py
├── __manifest__.py
├── models/
│   ├── __init__.py
│   ├── sales_summary_view.py
│   ├── product_performance_view.py
│   ├── customer_segment_view.py
│   └── res_partner_vip.py
├── views/
│   ├── sales_summary_views.xml
│   ├── product_performance_views.xml
│   ├── customer_segment_views.xml
│   ├── res_partner_vip_views.xml
│   └── menu.xml
├── security/
│   ├── ir.model.access.csv
│   └── ir_rule.xml
└── data/
    └── cron_refresh_views.xml
```

### __manifest__.py

```python
{
    'name': 'Sales Analytics Dashboard',
    'version': '18.0.1.0.0',
    'category': 'Sales/Analytics',
    'summary': 'Advanced sales analytics with database views',
    'depends': ['sale', 'product', 'base'],
    'data': [
        'security/ir.model.access.csv',
        'security/ir_rule.xml',
        'data/cron_refresh_views.xml',
        'views/sales_summary_views.xml',
        'views/product_performance_views.xml',
        'views/customer_segment_views.xml',
        'views/res_partner_vip_views.xml',
        'views/menu.xml',
    ],
    'installable': True,
    'application': True,
    'license': 'LGPL-3',
}
```

### models/__init__.py

```python
from . import sales_summary_view
from . import product_performance_view
from . import customer_segment_view
from . import res_partner_vip
```

---

## 1. Sales Summary View (Materialized)

### Model

```python
# models/sales_summary_view.py
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
    margin_percent = fields.Float(string='Margin %', readonly=True)
    avg_order_value = fields.Monetary(string='Avg Order Value', readonly=True, currency_field='currency_id')
    customer_count = fields.Integer(string='Customers', readonly=True)
    currency_id = fields.Many2one('res.currency', string='Currency', readonly=True)

    def init(self):
        """Create materialized view for better performance."""
        tools.drop_view_if_exists(self.env.cr, self._table)
        query = """
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
                    SUM(sol.purchase_price * sol.product_uom_qty) AS total_cost,
                    SUM(so.amount_total) - SUM(sol.purchase_price * sol.product_uom_qty) AS total_margin,
                    CASE 
                        WHEN SUM(so.amount_total) > 0 THEN
                            ((SUM(so.amount_total) - SUM(sol.purchase_price * sol.product_uom_qty)) / SUM(so.amount_total)) * 100
                        ELSE 0
                    END AS margin_percent,
                    AVG(so.amount_total) AS avg_order_value,
                    COUNT(DISTINCT so.partner_id) AS customer_count,
                    so.currency_id
                FROM
                    sale_order so
                LEFT JOIN
                    sale_order_line sol ON sol.order_id = so.id
                WHERE
                    so.state IN ('sale', 'done')
                    AND so.date_order >= CURRENT_DATE - INTERVAL '365 days'
                GROUP BY
                    so.user_id,
                    so.team_id,
                    DATE(so.date_order),
                    TO_CHAR(so.date_order, 'YYYY-MM'),
                    TO_CHAR(so.date_order, 'YYYY'),
                    so.currency_id
            )
        """
        self.env.cr.execute(query)
        
        # Create indexes for performance
        self.env.cr.execute("""
            CREATE INDEX IF NOT EXISTS sales_summary_view_salesperson_idx 
            ON sales_summary_view (salesperson_id)
        """)
        self.env.cr.execute("""
            CREATE INDEX IF NOT EXISTS sales_summary_view_date_idx 
            ON sales_summary_view (date)
        """)
        self.env.cr.execute("""
            CREATE INDEX IF NOT EXISTS sales_summary_view_month_idx 
            ON sales_summary_view (month)
        """)

    @api.model
    def refresh_view(self):
        """Refresh materialized view. Called by cron job."""
        try:
            self.env.cr.execute("REFRESH MATERIALIZED VIEW sales_summary_view")
            return True
        except Exception as e:
            raise UserError(f"Failed to refresh sales summary view: {str(e)}")

    def action_view_orders(self):
        """Open related sale orders."""
        self.ensure_one()
        return {
            'name': 'Sale Orders',
            'type': 'ir.actions.act_window',
            'res_model': 'sale.order',
            'view_mode': 'tree,form',
            'domain': [
                ('user_id', '=', self.salesperson_id.id),
                ('date_order', '=', self.date),
                ('state', 'in', ['sale', 'done']),
            ],
        }
```

### Views

```xml
<!-- views/sales_summary_views.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Tree View -->
    <record id="view_sales_summary_tree" model="ir.ui.view">
        <field name="name">sales.summary.view.tree</field>
        <field name="model">sales.summary.view</field>
        <field name="arch" type="xml">
            <tree string="Sales Summary" create="false" edit="false" delete="false">
                <field name="salesperson_id"/>
                <field name="team_id"/>
                <field name="date"/>
                <field name="order_count"/>
                <field name="customer_count"/>
                <field name="total_sales" sum="Total"/>
                <field name="total_cost" sum="Total"/>
                <field name="total_margin" sum="Total"/>
                <field name="margin_percent" widget="percentage"/>
                <field name="avg_order_value"/>
                <field name="currency_id" invisible="1"/>
                <button name="action_view_orders" 
                        string="View Orders" 
                        type="object" 
                        icon="fa-list"/>
            </tree>
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
                <field name="date" interval="month"/>
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
                        string="High Margin (>30%)" 
                        domain="[('margin_percent', '>', 30)]"/>
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
        <field name="view_mode">tree,pivot,graph</field>
        <field name="context">{'search_default_this_month': 1}</field>
    </record>
</odoo>
```

---

## 2. Product Performance View (Regular View)

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
    margin_percent = fields.Float(string='Margin %', readonly=True)
    
    # Performance indicators
    order_count = fields.Integer(string='Orders', readonly=True)
    customer_count = fields.Integer(string='Customers', readonly=True)
    avg_price = fields.Monetary(string='Avg Price', readonly=True, currency_field='currency_id')
    last_sale_date = fields.Date(string='Last Sale', readonly=True)
    days_since_last_sale = fields.Integer(string='Days Since Last Sale', readonly=True)
    
    # Stock info
    qty_available = fields.Float(string='On Hand', readonly=True)
    virtual_available = fields.Float(string='Forecast', readonly=True)
    
    currency_id = fields.Many2one('res.currency', string='Currency', readonly=True)

    def init(self):
        tools.drop_view_if_exists(self.env.cr, self._table)
        query = """
            CREATE OR REPLACE VIEW product_performance_view AS (
                SELECT
                    pp.id,
                    pp.id AS product_id,
                    pt.id AS product_tmpl_id,
                    pt.categ_id,
                    SUM(sol.product_uom_qty) AS total_qty_sold,
                    SUM(sol.price_subtotal) AS total_revenue,
                    SUM(sol.purchase_price * sol.product_uom_qty) AS total_cost,
                    SUM(sol.price_subtotal) - SUM(sol.purchase_price * sol.product_uom_qty) AS total_margin,
                    CASE 
                        WHEN SUM(sol.price_subtotal) > 0 THEN
                            ((SUM(sol.price_subtotal) - SUM(sol.purchase_price * sol.product_uom_qty)) / SUM(sol.price_subtotal)) * 100
                        ELSE 0
                    END AS margin_percent,
                    COUNT(DISTINCT so.id) AS order_count,
                    COUNT(DISTINCT so.partner_id) AS customer_count,
                    AVG(sol.price_unit) AS avg_price,
                    MAX(so.date_order)::date AS last_sale_date,
                    EXTRACT(days FROM (CURRENT_DATE - MAX(so.date_order)::date)) AS days_since_last_sale,
                    COALESCE(sq.quantity, 0) AS qty_available,
                    COALESCE(sq.quantity, 0) + COALESCE(
                        (SELECT SUM(product_qty) FROM stock_move 
                         WHERE product_id = pp.id AND state = 'assigned'), 0
                    ) AS virtual_available,
                    so.currency_id
                FROM
                    product_product pp
                INNER JOIN
                    product_template pt ON pp.product_tmpl_id = pt.id
                LEFT JOIN
                    sale_order_line sol ON sol.product_id = pp.id
                LEFT JOIN
                    sale_order so ON sol.order_id = so.id AND so.state IN ('sale', 'done')
                LEFT JOIN
                    stock_quant sq ON sq.product_id = pp.id AND sq.location_id IN (
                        SELECT id FROM stock_location WHERE usage = 'internal'
                    )
                WHERE
                    pt.active = true
                    AND (so.date_order IS NULL OR so.date_order >= CURRENT_DATE - INTERVAL '365 days')
                GROUP BY
                    pp.id,
                    pt.id,
                    pt.categ_id,
                    sq.quantity,
                    so.currency_id
            )
        """
        self.env.cr.execute(query)

    def action_view_sales(self):
        """View sale order lines for this product."""
        self.ensure_one()
        return {
            'name': 'Sales',
            'type': 'ir.actions.act_window',
            'res_model': 'sale.order.line',
            'view_mode': 'tree,form',
            'domain': [('product_id', '=', self.product_id.id)],
            'context': {'create': False},
        }

    def action_open_product(self):
        """Open product form."""
        self.ensure_one()
        return {
            'name': 'Product',
            'type': 'ir.actions.act_window',
            'res_model': 'product.product',
            'res_id': self.product_id.id,
            'view_mode': 'form',
        }
```

---

## 3. VIP Customer Model (Inherited with Filter)

```python
# models/res_partner_vip.py
from odoo import models, fields, api, tools

class ResPartnerVIP(models.Model):
    _name = 'res.partner.vip'
    _description = 'VIP Customers'
    _auto = False
    _rec_name = 'name'
    _order = 'total_purchased desc'

    # Partner fields
    partner_id = fields.Many2one('res.partner', string='Partner', readonly=True)
    name = fields.Char(string='Name', readonly=True)
    email = fields.Char(string='Email', readonly=True)
    phone = fields.Char(string='Phone', readonly=True)
    country_id = fields.Many2one('res.country', string='Country', readonly=True)
    
    # VIP metrics
    total_purchased = fields.Monetary(string='Total Purchased', readonly=True, currency_field='currency_id')
    order_count = fields.Integer(string='Orders', readonly=True)
    avg_order_value = fields.Monetary(string='Avg Order', readonly=True, currency_field='currency_id')
    last_order_date = fields.Date(string='Last Order', readonly=True)
    days_since_last_order = fields.Integer(string='Days Since Last Order', readonly=True)
    vip_level = fields.Selection([
        ('gold', 'Gold'),
        ('platinum', 'Platinum'),
        ('diamond', 'Diamond'),
    ], string='VIP Level', readonly=True)
    currency_id = fields.Many2one('res.currency', string='Currency', readonly=True)

    def init(self):
        tools.drop_view_if_exists(self.env.cr, self._table)
        query = """
            CREATE OR REPLACE VIEW res_partner_vip AS (
                SELECT
                    rp.id,
                    rp.id AS partner_id,
                    rp.name,
                    rp.email,
                    rp.phone,
                    rp.country_id,
                    SUM(so.amount_total) AS total_purchased,
                    COUNT(so.id) AS order_count,
                    AVG(so.amount_total) AS avg_order_value,
                    MAX(so.date_order)::date AS last_order_date,
                    EXTRACT(days FROM (CURRENT_DATE - MAX(so.date_order)::date)) AS days_since_last_order,
                    CASE
                        WHEN SUM(so.amount_total) >= 100000 THEN 'diamond'
                        WHEN SUM(so.amount_total) >= 50000 THEN 'platinum'
                        ELSE 'gold'
                    END AS vip_level,
                    so.currency_id
                FROM
                    res_partner rp
                INNER JOIN
                    sale_order so ON so.partner_id = rp.id
                WHERE
                    so.state IN ('sale', 'done')
                    AND rp.active = true
                    AND rp.customer_rank > 0
                GROUP BY
                    rp.id,
                    rp.name,
                    rp.email,
                    rp.phone,
                    rp.country_id,
                    so.currency_id
                HAVING
                    SUM(so.amount_total) >= 10000  -- Minimum 10k untuk VIP
            )
        """
        self.env.cr.execute(query)

    def action_view_orders(self):
        """View customer orders."""
        self.ensure_one()
        return {
            'name': 'Orders',
            'type': 'ir.actions.act_window',
            'res_model': 'sale.order',
            'view_mode': 'tree,form',
            'domain': [('partner_id', '=', self.partner_id.id)],
        }

    def action_send_vip_email(self):
        """Send VIP appreciation email."""
        self.ensure_one()
        template = self.env.ref('sales_analytics.email_template_vip_appreciation', raise_if_not_found=False)
        if template:
            template.send_mail(self.id, force_send=True)
        return True
```

---

## 4. Cron Job untuk Refresh Views

```xml
<!-- data/cron_refresh_views.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <!-- Refresh sales summary every hour -->
        <record id="cron_refresh_sales_summary" model="ir.cron">
            <field name="name">Refresh Sales Summary View</field>
            <field name="model_id" ref="model_sales_summary_view"/>
            <field name="state">code</field>
            <field name="code">model.refresh_view()</field>
            <field name="interval_number">1</field>
            <field name="interval_type">hours</field>
            <field name="numbercall">-1</field>
            <field name="active">True</field>
            <field name="priority">5</field>
        </record>
    </data>
</odoo>
```

---

## 5. Security

```csv
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_sales_summary_view_user,sales.summary.view user,model_sales_summary_view,sales_team.group_sale_salesman,1,0,0,0
access_sales_summary_view_manager,sales.summary.view manager,model_sales_summary_view,sales_team.group_sale_manager,1,0,0,0
access_product_performance_view_user,product.performance.view user,model_product_performance_view,sales_team.group_sale_salesman,1,0,0,0
access_res_partner_vip_user,res.partner.vip user,model_res_partner_vip,sales_team.group_sale_salesman,1,0,0,0
access_res_partner_vip_manager,res.partner.vip manager,model_res_partner_vip,sales_team.group_sale_manager,1,0,0,0
```

---

## 6. Menu Structure

```xml
<!-- views/menu.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Root Menu -->
    <menuitem id="menu_sales_analytics_root"
              name="Sales Analytics"
              sequence="100"
              web_icon="sales_analytics,static/description/icon.png"/>

    <!-- Sales Summary -->
    <menuitem id="menu_sales_summary"
              name="Sales Summary"
              parent="menu_sales_analytics_root"
              action="action_sales_summary"
              sequence="10"/>

    <!-- Product Performance -->
    <menuitem id="menu_product_performance"
              name="Product Performance"
              parent="menu_sales_analytics_root"
              action="action_product_performance"
              sequence="20"/>

    <!-- VIP Customers -->
    <menuitem id="menu_vip_customers"
              name="VIP Customers"
              parent="menu_sales_analytics_root"
              action="action_res_partner_vip"
              sequence="30"/>
</odoo>
```

---

## 7. Testing

```python
# tests/test_sales_summary_view.py
from odoo.tests.common import TransactionCase
from datetime import datetime, timedelta

class TestSalesSummaryView(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        
        # Create test data
        cls.partner = cls.env['res.partner'].create({
            'name': 'Test Customer',
        })
        
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
        """Test that sales summary view contains correct data."""
        # Create sale order
        order = self.env['sale.order'].create({
            'partner_id': self.partner.id,
            'user_id': self.salesperson.id,
            'order_line': [(0, 0, {
                'product_id': self.product.id,
                'product_uom_qty': 2,
                'price_unit': 100.0,
            })],
        })
        order.action_confirm()
        
        # Refresh view
        self.env['sales.summary.view'].refresh_view()
        
        # Check view data
        summary = self.env['sales.summary.view'].search([
            ('salesperson_id', '=', self.salesperson.id),
        ])
        
        self.assertTrue(summary, "Sales summary should exist")
        self.assertEqual(summary.order_count, 1)
        self.assertEqual(summary.total_sales, 200.0)

    def test_refresh_view_method(self):
        """Test refresh view method works."""
        result = self.env['sales.summary.view'].refresh_view()
        self.assertTrue(result, "Refresh should return True")
```

---

## Kesimpulan

Contoh praktis ini mendemonstrasikan:

✅ **Materialized views** untuk data yang jarang berubah (sales summary)
✅ **Regular views** untuk data real-time (product performance)
✅ **Filtered inherited models** untuk segmentasi (VIP customers)
✅ **Cron jobs** untuk auto-refresh views
✅ **Multiple view types** (tree, pivot, graph)
✅ **Action buttons** untuk drill-down ke detail
✅ **Security** dan access rights
✅ **Testing** untuk memastikan data akurat

**Performance Tips:**
- Gunakan materialized views untuk dashboard yang di-refresh berkala
- Tambahkan index pada field yang sering di-filter
- Batasi data dengan WHERE clause (contoh: 365 hari terakhir)
- Test query dengan EXPLAIN ANALYZE sebelum production
