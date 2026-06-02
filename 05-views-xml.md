# Bab 5: Views (XML)

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
                <button name="action_confirm" string="Confirm" class="btn-primary" type="object"/>
                <button name="action_cancel" string="Cancel" class="btn-secondary" type="object"/>
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
                        <field name="price"/>
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
            <div class="oe_chatter">
                <field name="message_follower_ids"/>
                <field name="activity_ids"/>
                <field name="message_ids"/>
            </div>
        </form>
    </field>
</record>
```

## Tree View (List)

```xml
<record id="view_library_book_tree" model="ir.ui.view">
    <field name="name">library.book.tree</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <tree>
            <field name="name"/>
            <field name="author"/>
            <field name="price"/>
            <field name="state"/>
            <field name="partner_id"/>
        </tree>
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
                <t t-name="kanban-box">
                    <div class="oe_kanban_global_click">
                        <div class="o_kanban_record_title">
                            <field name="name"/>
                        </div>
                        <div class="o_kanban_record_body">
                            <span><field name="author"/></span>
                        </div>
                        <div class="oe_kanban_footer">
                            <field name="state" widget="label_selection"
                                   options="{'classes': {'available': 'success', 'borrowed': 'warning'}}"/>
                        </div>
                    </div>
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

## Action & Menu

```xml
<!-- Menuitem -->
<menuitem id="menu_library_root"
          name="Library"
          action=""
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
    <field name="view_mode">tree,form,kanban</field>
    <field name="help">Create your first book</field>
</record>
```

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
```

## Field Attributes di View

```xml
<field name="name" readonly="1"/>
<field name="price" options="{'currency': 'IDR'}"/>
<field name="date" options="{'datepicker': {'minDate': 0}}"/>
<field name="state" attrs="{'invisible': [('type', '=', 'draft')]}"/>
<field name="price" attrs="{'readonly': [('state', 'in', ['done', 'cancel'])]}"/>
<field name="name" placeholder="Enter title..."/>
<field name="email" widget="email"/>
<field name="website" widget="url"/>
```