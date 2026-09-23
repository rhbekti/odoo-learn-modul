# Bab 5: Views (XML)

> **Catatan versi:** Dokumen ini sudah disesuaikan dengan Odoo 18 dan 19. Perubahan paling besar dibanding Odoo 16/17 ke bawah:
> - Tag `<tree>` **diganti nama menjadi** `<list>` (sejak Odoo 18). XPath yang menargetkan `tree` juga harus diperbarui.
> - Atribut `attrs="{...}"` dan `states="..."` **sudah dihapus total** (sejak Odoo 17). Diganti dengan ekspresi inline langsung di atribut `invisible=`, `readonly=`, `required=`, `column_invisible=`.
> - Template kanban `kanban-box` diganti menjadi `card`, dengan struktur `<header>`, `<main>`/isi langsung, dan `<footer>`.
> - Blok chatter yang panjang (`message_follower_ids`, `activity_ids`, `message_ids`) bisa diringkas jadi satu tag `<chatter/>`.

## Struktur View di XML

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data>
        <!-- View definitions here -->
    </data>
</odoo>
```

## Form View

```xml
<record id="view_library_book_form" model="ir.ui.view">
    <field name="name">library.book.form</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <form string="Book Form">
            <header>
                <button name="action_confirm" string="Confirm" class="btn-primary" type="object"
                        invisible="state != 'draft'"/>
                <button name="action_cancel" string="Cancel" class="btn-secondary" type="object"
                        invisible="state in ('confirm', 'done')"/>
                <field name="state" widget="statusbar" statusbar_visible="draft,confirm,done"/>
            </header>
            <sheet>
                <group>
                    <group string="Main Info">
                        <field name="name"/>
                        <field name="isbn"/>
                        <field name="author"/>
                    </group>
                    <group string="Details">
                        <field name="price" readonly="state == 'done'"/>
                        <field name="partner_id"/>
                        <field name="date_release"/>
                    </group>
                </group>
                <notebook>
                    <page string="Description" name="description">
                        <field name="description"/>
                    </page>
                    <page string="Notes" name="notes">
                        <field name="notes"/>
                    </page>
                </notebook>
            </sheet>
            <chatter/>
        </form>
    </field>
</record>
```

> `<chatter/>` adalah shorthand baru (sejak Odoo 17+) yang menggantikan blok manual `<div class="oe_chatter">` berisi `message_follower_ids`, `activity_ids`, `message_ids`. Kalau butuh kustomisasi (misal menyembunyikan tab tertentu), masih bisa pakai atribut seperti `<chatter reload_on_follower="True"/>`.

## List View (dulu bernama "Tree View")

> Sejak **Odoo 18**, tag `<tree>` resmi diganti menjadi `<list>`. Fungsinya sama persis (menampilkan data dalam bentuk tabel/daftar), hanya nama tag dan istilahnya yang berubah. Kalau kamu upgrade dari Odoo 17 ke bawah, semua `<tree>` di `arch` **dan** semua XPath yang menargetkan `tree` (misal `//field[@name='order_line']/tree`) wajib diganti jadi `list`.

```xml
<record id="view_library_book_list" model="ir.ui.view">
    <field name="name">library.book.list</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <list string="Books" decoration-danger="state == 'lost'">
            <field name="name"/>
            <field name="author"/>
            <field name="price"/>
            <field name="state"/>
            <field name="partner_id" column_invisible="not context.get('show_partner')"/>
        </list>
    </field>
</record>
```

## Search View

```xml
<record id="view_library_book_search" model="ir.ui.view">
    <field name="name">library.book.search</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <search>
            <field name="name" string="Title"/>
            <field name="author" string="Author"/>
            <filter name="available" string="Available" domain="[('state', '=', 'available')]"/>
            <separator/>
            <filter name="high_price" string="High Price" domain="[('price', '>', 100)]"/>
            <group expand="0" string="Group By">
                <filter name="group_state" string="State" context="{'group_by': 'state'}"/>
                <filter name="group_partner" string="Partner" context="{'group_by': 'partner_id'}"/>
            </group>
        </search>
    </field>
</record>
```

## Kanban View

> Struktur template kanban berubah sejak Odoo 17+: nama template `kanban-box` menjadi `card`, dan sekarang ada elemen bawaan `<header>`, isi utama langsung sebagai children `<t t-name="card">`, dan `<footer>` — tidak perlu lagi bungkus manual `<div class="oe_kanban_global_click">` dkk (walaupun class lama masih dikenali untuk kompatibilitas).

```xml
<record id="view_library_book_kanban" model="ir.ui.view">
    <field name="name">library.book.kanban</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <kanban>
            <field name="name"/>
            <field name="author"/>
            <field name="state"/>
            <templates>
                <t t-name="card">
                    <field name="name" class="fw-bold"/>
                    <div><field name="author"/></div>
                    <footer>
                        <field name="state" widget="label_selection"
                               options="{'classes': {'available': 'success', 'borrowed': 'warning'}}"/>
                    </footer>
                </t>
            </templates>
        </kanban>
    </field>
</record>
```

## Activity View

```xml
<record id="view_library_book_activity" model="ir.ui.view">
    <field name="name">library.book.activity</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <activity string="Book Activities">
            <field name="name" string="Title"/>
            <templates>
                <field name="state"/>
            </templates>
        </activity>
    </field>
</record>
```

## Graph View

```xml
<record id="view_library_book_graph" model="ir.ui.view">
    <field name="name">library.book.graph</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <graph type="bar">
            <field name="state" type="row"/>
            <field name="price" type="measure"/>
        </graph>
    </field>
</record>
```

## Pivot View

```xml
<record id="view_library_book_pivot" model="ir.ui.view">
    <field name="name">library.book.pivot</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <pivot>
            <field name="state" type="col"/>
            <field name="partner_id" type="row"/>
            <field name="price" type="measure"/>
        </pivot>
    </field>
</record>
```

## Calendar View

```xml
<record id="view_library_book_calendar" model="ir.ui.view">
    <field name="name">library.book.calendar</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <calendar date_start="date_release" color="state" create="0" delete="0">
            <field name="name"/>
            <field name="author"/>
        </calendar>
    </field>
</record>
```

## View Inheritance

```xml
<!-- Extend existing view -->
<record id="view_library_book_form_inherit" model="ir.ui.view">
    <field name="name">library.book.form.inherit</field>
    <field name="model">library.book</field>
    <field name="inherit_id" ref="library_app.view_library_book_form"/>
    <field name="arch" type="xml">
        <!-- Insert after specific element -->
        <xpath expr="//field[@name='author']" position="after">
            <field name="publisher_id"/>
        </xpath>
        <!-- Or use element location -->
        <form position="inside">
            <group string="Publisher">
                <field name="publisher_id"/>
            </group>
        </form>
    </field>
</record>
```

Kalau view yang di-inherit punya sub-list (misal one2many di dalam form), ingat XPath-nya juga sudah pakai `list`, bukan `tree` lagi:

```xml
<!-- Odoo 18/19 -->
<xpath expr="//field[@name='order_line']/list/field[@name='price_unit']" position="after">
    <field name="discount"/>
</xpath>
```

## Action & Menu

```xml
<!-- Menuitem -->
<menuitem id="menu_library_root"
          name="Library"
          sequence="10"/>

<menuitem id="menu_library_book"
          name="Books"
          parent="menu_library_root"
          action="act_library_book"
          sequence="10"/>

<!-- Window Action -->
<record id="act_library_book" model="ir.actions.act_window">
    <field name="name">Books</field>
    <field name="res_model">library.book</field>
    <field name="view_mode">list,form,kanban</field>
    <field name="help">Create your first book</field>
</record>
```

> `view_mode` sekarang menggunakan kata kunci `list` (bukan `tree`) untuk merujuk ke List View, konsisten dengan penamaan tag barunya. Untuk `menuitem` root tanpa action, atribut `action` cukup dihilangkan (tidak perlu ditulis `action=""`).

## Widgets

```xml
<!-- Common widgets -->
<field name="image" widget="image"/>
<field name="binary" widget="binary"/>
<field name="state" widget="statusbar"/>
<field name="date" widget="date"/>
<field name="priority" widget="priority"/>
<field name="progress" widget="progressbar"/>
<field name="note" widget="text"/>
<field name="html_field" widget="html"/>

<!-- Many2one dengan autocomplete -->
<field name="partner_id" widget="selection"/>

<!-- Phone field -->
<field name="phone" widget="phone"/>

<!-- Avatar user (umum dipakai di kanban/list, sejak Odoo 17+) -->
<field name="user_id" widget="many2one_avatar_user"/>
```

## Field Attributes di View (sintaks baru, sejak Odoo 17+)

> `attrs="{...}"` dan `states="..."` **sudah tidak berfungsi lagi**. Sebagai gantinya, tulis ekspresi kondisi langsung sebagai nilai atribut `invisible`, `readonly`, `required`, atau `column_invisible` (untuk kolom dalam list view di dalam one2many). Ekspresi ini pakai sintaks mirip Python/JS sederhana — perbandingan, `and`/`or`/`not`, `in`/`not in` — tanpa perlu format domain list `[('field', '=', value)]`.

```xml
<!-- Readonly biasa -->
<field name="name" readonly="1"/>

<!-- Kondisional, menggantikan attrs lama -->
<field name="state" invisible="type == 'draft'"/>
<field name="price" readonly="state in ('done', 'cancel')"/>
<field name="date_order" required="state == 'sale'"/>

<!-- Kombinasi kondisi -->
<field name="warehouse_id" invisible="picking_policy == 'direct' or not active"/>

<!-- column_invisible: dipakai di dalam one2many/list, bisa akses field parent -->
<field name="qty_delivered" column_invisible="parent.state == 'draft'"/>

<!-- Opsi tambahan lain tetap sama -->
<field name="price" options="{'currency': 'IDR'}"/>
<field name="date" options="{'datepicker': {'minDate': 0}}"/>
<field name="name" placeholder="Enter title..."/>
<field name="email" widget="email"/>
<field name="website" widget="url"/>
```

### Tabel padanan `attrs`/`states` lama → sintaks baru

| Odoo ≤16 (`attrs` / `states`) | Odoo 17/18/19 (inline) |
|---|---|
| `attrs="{'invisible': [('state','=','draft')]}"` | `invisible="state == 'draft'"` |
| `attrs="{'invisible': [('state','!=','draft')]}"` | `invisible="state != 'draft'"` |
| `attrs="{'invisible': [('state','in',['a','b'])]}"` | `invisible="state in ('a', 'b')"` |
| `attrs="{'readonly': [('qty','>',0)]}"` | `readonly="qty > 0"` |
| `attrs="{..., '|', (...), (...)}"` (OR) | `invisible="cond1 or cond2"` |
| `states="draft,sent"` pada tombol/field | `invisible="state not in ('draft', 'sent')"` |

## Ringkasan Perubahan Versi

| Area | Odoo ≤16 | Odoo 17 | Odoo 18 | Odoo 19 |
|---|---|---|---|---|
| Tag list/tabel | `<tree>` | `<tree>` (masih ada) | `<list>` (rename resmi) | `<list>` |
| `attrs` / `states` | Dipakai | **Dihapus**, pakai inline `invisible=`/`readonly=`/`required=` | Sama seperti 17 | Sama seperti 17 |
| Template kanban | `kanban-box` | Mulai transisi ke `card` | `card` + `<header>`/`<footer>` | Sama seperti 18 |
| Chatter di form | Tulis manual 3 field | `<chatter/>` shorthand tersedia | Sama | Sama |
| `view_mode` action | `tree,form,...` | `tree,form,...` | `list,form,...` | `list,form,...` |

**Saran:** kalau modul kamu masih ditarget ke Odoo ≤16, tetap pakai `<tree>` dan `attrs=`. Untuk pengembangan baru di Odoo 17 ke atas, selalu pakai `<list>` dan atribut inline seperti di atas.
