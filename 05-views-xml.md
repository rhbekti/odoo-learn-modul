# Bab 5: Views (XML)

> **Tahap:** 2 Inti Pengembangan | **Prasyarat:** Bab 3, 4 | **Estimasi:** ± 3 jam | **Versi:** Odoo 18 (catatan Odoo 19)

## Tujuan Belajar

Setelah bab ini kamu bisa:
- Menulis form, list, dan search view untuk sebuah model dengan struktur XML yang benar.
- Menghubungkan view ke menu lewat window action dan `menuitem`.
- Mengatur tampil/sembunyi, readonly, dan required secara kondisional dengan sintaks inline (`invisible="..."`), bukan `attrs`.
- Membuat view tambahan (kanban, activity, graph, pivot, calendar) dan memilih widget yang tepat.
- Memperluas view yang sudah ada dengan `inherit_id` + XPath, termasuk memakai `list` (bukan `tree`).

> **Beda di Odoo 19:** Sintaks view di bab ini berlaku untuk Odoo 18 dan 19 (tag `<list>`, `<chatter/>`, template kanban `card`, atribut inline `invisible`/`readonly`/`required`). Tidak ada perubahan sintaks view tambahan yang kami verifikasi antara 18 dan 19. Kalau modulmu berasal dari Odoo 16 ke bawah, lihat tabel padanan di bagian akhir bab.

## Struktur File View

Setiap file view adalah file XML dengan root `<odoo>`. Pembungkus `<data>` bersifat opsional; kalau dipakai, bisa diberi atribut `noupdate` (dibahas di Bab 7).

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- record view, action, dan menu ditulis di sini -->
</odoo>
```

Ingat: file ini harus didaftarkan di `'data'` pada `__manifest__.py` (Bab 3), dan model yang dipakai view perlu punya access rights (Bab 6) supaya bisa dibuka oleh user non-admin.

Setiap view adalah record `ir.ui.view` dengan tiga field utama: `name`, `model`, dan `arch` (isi XML view).

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

Bagian-bagian form: `<header>` (tombol aksi + statusbar), `<sheet>` (isi utama dengan `<group>` dan `<notebook>`), dan `<chatter/>`.

> `<chatter/>` menggantikan blok manual `<div class="oe_chatter">` berisi `message_follower_ids`, `activity_ids`, `message_ids`. Model-nya harus mewarisi `mail.thread` (dan `mail.activity.mixin` untuk aktivitas). Kalau butuh kustomisasi, atributnya bisa ditambahkan, misalnya `<chatter reload_on_follower="True"/>`.

## List View (dulu bernama "Tree View")

> Di Odoo 18 dan 19, tag `<tree>` diganti menjadi `<list>`. Fungsinya sama (menampilkan data sebagai tabel), hanya nama tag dan istilahnya yang berubah. Kalau kamu upgrade dari versi lama, semua `<tree>` di `arch` **dan** semua XPath yang menargetkan `tree` (misal `//field[@name='order_line']/tree`) wajib diganti jadi `list`.

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
            <field name="partner_id" optional="show"/>
        </list>
    </field>
</record>
```

- `decoration-danger`, `decoration-success`, dst. mewarnai baris berdasarkan ekspresi.
- `optional="show"` / `optional="hide"` membuat kolom bisa ditampilkan/disembunyikan user lewat menu kolom.

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

Perhatikan: `domain` pada `<filter>` tetap memakai format list domain biasa (`[('field', 'op', value)]`). Hanya atribut `invisible`/`readonly`/`required` pada view yang memakai ekspresi inline.

## Action & Menu

View baru muncul di UI setelah dihubungkan ke menu lewat window action. **Tulis action sebelum `menuitem` yang merujuknya**, karena `action="..."` pada menu butuh ID yang sudah terdaftar.

```xml
<!-- Window Action -->
<record id="act_library_book" model="ir.actions.act_window">
    <field name="name">Books</field>
    <field name="res_model">library.book</field>
    <field name="view_mode">list,form,kanban</field>
    <field name="help" type="html">
        <p class="o_view_nocontent_smiling_face">
            Create your first book
        </p>
    </field>
</record>

<!-- Menu root (tanpa action) -->
<menuitem id="menu_library_root"
          name="Library"
          sequence="10"/>

<!-- Menu yang membuka action -->
<menuitem id="menu_library_book"
          name="Books"
          parent="menu_library_root"
          action="act_library_book"
          sequence="10"/>
```

> `view_mode` memakai kata kunci `list` (bukan `tree`) untuk List View, konsisten dengan nama tag barunya. Untuk `menuitem` root tanpa action, atribut `action` cukup dihilangkan (tidak perlu `action=""`). Menu juga bisa dibatasi per group dengan atribut `groups` (Bab 6).

## Atribut Field di View: Kondisi Inline

`attrs="{...}"` dan `states="..."` sudah tidak berfungsi (dihapus sejak Odoo 17). Tulis ekspresi kondisi langsung sebagai nilai atribut `invisible`, `readonly`, `required`, atau `column_invisible` (untuk kolom di list). Ekspresinya mirip Python sederhana: perbandingan, `and`/`or`/`not`, `in`/`not in`, tanpa format domain list.

```xml
<!-- Readonly biasa -->
<field name="name" readonly="1"/>

<!-- Kondisional -->
<field name="isbn" invisible="state == 'draft'"/>
<field name="price" readonly="state in ('done', 'cancel')"/>
<field name="date_release" required="state == 'confirm'"/>

<!-- Kombinasi kondisi -->
<field name="partner_id" invisible="state == 'draft' or not active"/>

<!-- column_invisible: kolom di list dalam one2many, bisa akses field parent -->
<field name="qty_delivered" column_invisible="parent.state == 'draft'"/>

<!-- Atribut umum lain -->
<field name="name" placeholder="Enter title..."/>
```

### Tabel padanan `attrs`/`states` lama ke sintaks baru

| Lama (`attrs` / `states`) | Odoo 18/19 (inline) |
|---|---|
| `attrs="{'invisible': [('state','=','draft')]}"` | `invisible="state == 'draft'"` |
| `attrs="{'invisible': [('state','!=','draft')]}"` | `invisible="state != 'draft'"` |
| `attrs="{'invisible': [('state','in',['a','b'])]}"` | `invisible="state in ('a', 'b')"` |
| `attrs="{'readonly': [('qty','>',0)]}"` | `readonly="qty > 0"` |
| `attrs="{'invisible': ['|', (...), (...)]}"` (OR) | `invisible="cond1 or cond2"` |
| `states="draft,sent"` pada tombol/field | `invisible="state not in ('draft', 'sent')"` |

## Widgets

```xml
<field name="image" widget="image"/>
<field name="binary" widget="binary"/>
<field name="state" widget="statusbar"/>
<field name="priority" widget="priority"/>
<field name="progress" widget="progressbar"/>
<field name="note" widget="text"/>
<field name="html_field" widget="html"/>
<field name="phone" widget="phone"/>
<field name="email" widget="email"/>
<field name="website" widget="url"/>

<!-- Many2one tampil sebagai dropdown biasa (bukan autocomplete) -->
<field name="partner_id" widget="selection"/>

<!-- Angka uang dengan simbol mata uang dari field currency_id -->
<field name="price" widget="monetary" options="{'currency_field': 'currency_id'}"/>

<!-- Avatar user (umum dipakai di kanban/list) -->
<field name="user_id" widget="many2one_avatar_user"/>
```

Many2one tanpa `widget` sudah berupa autocomplete; pakai `widget="selection"` hanya kalau daftarnya pendek.

## Kanban View

> Template kanban memakai nama `card` (menggantikan `kanban-box`), dengan elemen bawaan `<header>`, isi utama langsung sebagai children `<t t-name="card">`, dan `<footer>`. Tidak perlu lagi membungkus manual dengan `<div class="oe_kanban_global_click">` dan sejenisnya.

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

Butuh model yang mewarisi `mail.activity.mixin`, dan `activity` harus ada di `view_mode` action.

```xml
<record id="view_library_book_activity" model="ir.ui.view">
    <field name="name">library.book.activity</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <activity string="Book Activities">
            <templates>
                <div t-name="activity-box">
                    <field name="name" display="full"/>
                </div>
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

Untuk menambah/mengubah view yang sudah ada (milik modul lain atau modulmu sendiri) tanpa menyalin seluruhnya, buat record baru dengan `inherit_id`. Mekanisme inheritance secara umum dibahas lebih dalam di Bab 8.

```xml
<record id="view_library_book_form_inherit" model="ir.ui.view">
    <field name="name">library.book.form.inherit</field>
    <field name="model">library.book</field>
    <field name="inherit_id" ref="library_management.view_library_book_form"/>
    <field name="arch" type="xml">
        <!-- Sisipkan setelah elemen tertentu -->
        <xpath expr="//field[@name='author']" position="after">
            <field name="publisher_id"/>
        </xpath>
        <!-- Sisipkan group baru sebelum notebook -->
        <xpath expr="//notebook" position="before">
            <group string="Publisher">
                <field name="publisher_id"/>
            </group>
        </xpath>
    </field>
</record>
```

Nilai `position`: `after`, `before`, `inside`, `replace`, `attributes`.

Kalau view yang di-inherit punya sub-list (misal one2many di dalam form), XPath-nya memakai `list`, bukan `tree`:

```xml
<xpath expr="//field[@name='order_line']/list/field[@name='price_unit']" position="after">
    <field name="discount"/>
</xpath>
```

## Ringkasan Perubahan Versi

| Area | Odoo 16 ke bawah | Odoo 18 dan 19 |
|---|---|---|
| Tag list/tabel | `<tree>` | `<list>` |
| `attrs` / `states` | Dipakai | Dihapus (sejak 17), pakai inline `invisible=`/`readonly=`/`required=` |
| Template kanban | `kanban-box` | `card` + `<header>`/`<footer>` |
| Chatter di form | Tulis manual 3 field | `<chatter/>` |
| `view_mode` action | `tree,form,...` | `list,form,...` |

Kalau modulmu masih ditarget ke Odoo 16 ke bawah, tetap pakai `<tree>` dan `attrs=`. Untuk pengembangan baru, pakai `<list>` dan atribut inline.

## Ringkasan

- View adalah record `ir.ui.view` dengan `name`, `model`, dan `arch`; file XML-nya didaftarkan di `'data'` manifest.
- Form terdiri dari `<header>`, `<sheet>` (`group`, `notebook`), dan `<chatter/>`.
- Di Odoo 18/19 gunakan `<list>` (bukan `<tree>`) dan `view_mode="list,form"`.
- Window action dan `menuitem` menghubungkan view ke UI; tulis action sebelum menu yang merujuknya.
- Kondisi tampilan memakai atribut inline (`invisible`, `readonly`, `required`, `column_invisible`); `attrs` dan `states` sudah tidak ada.
- Kanban memakai `t-name="card"`; activity view butuh `mail.activity.mixin`.
- View turunan memakai `inherit_id` + XPath; XPath ke sub-list harus memakai `list`.

## Latihan

1. Untuk model `library.book`, buat form view, list view (dengan `decoration-danger` untuk `state == 'lost'`), dan search view dengan satu filter dan satu group by. Buat window action `list,form` plus menu root dan sub-menu, lalu install/upgrade modul dan pastikan menunya muncul.
2. Ubah potongan lama berikut ke sintaks Odoo 18/19: `<field name="price" attrs="{'readonly': [('state','in',['done','cancel'])], 'invisible': ['|', ('state','=','draft'), ('active','=',False)]}"/>`
3. Buat view turunan dari form buku: tambahkan satu field baru setelah `author` dan satu `group` baru sebelum `notebook`. Cek hasilnya di UI.

## Lanjut ke

Bab 6: Security & Access Rights (`06-security-access-rights.md`).
