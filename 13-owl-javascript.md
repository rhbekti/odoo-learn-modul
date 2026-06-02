# Bab 13: OWL Components & JavaScript (Frontend)

Odoo 18 menggunakan OWL (Odoo Web Library) sebagai framework JavaScript-nya. OWL mirip dengan React/Vue tapi buatan Odoo sendiri.

## Struktur File JavaScript di Module

```
library_management/
├── static/
│   ├── src/
│   │   ├── components/
│   │   │   ├── book_dashboard.js
│   │   │   ├── book_dashboard.xml
│   │   │   └── book_dashboard.scss
│   │   └── views/
│   │       └── book_list_view.js
│   └── description/
│       └── icon.png
```

---

## Registrasi Assets

```xml
<!-- views/assets.xml -->
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Asset untuk backend (web client) -->
    <template id="assets_backend" inherit_id="web.assets_backend">
        <xpath expr="." position="inside">
            <script type="text/javascript"
                    src="/library_management/static/src/components/book_dashboard.js"/>
            <link rel="stylesheet"
                  href="/library_management/static/src/components/book_dashboard.scss"/>
        </xpath>
    </template>

    <!-- Asset untuk website (frontend publik) -->
    <template id="assets_frontend" inherit_id="website.assets_frontend">
        <xpath expr="." position="inside">
            <script type="text/javascript"
                    src="/library_management/static/src/frontend/main.js"/>
        </xpath>
    </template>
</odoo>
```

Tambahkan di `__manifest__.py`:

```python
'assets': {
    'web.assets_backend': [
        'library_management/static/src/components/**/*',
    ],
    'web.assets_frontend': [
        'library_management/static/src/frontend/**/*',
    ],
},
```

**Odoo 18 preferred:** Gunakan key `assets` di manifest daripada template inherit.

---

## OWL Component Dasar

### JavaScript (Component Logic)

```javascript
/** @odoo-module **/

import { Component, useState, onWillStart } from "@odoo/owl";
import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";

class BookDashboard extends Component {
    static template = "library_management.BookDashboard";
    static props = {};

    setup() {
        // Services (mirip dependency injection)
        this.orm = useService("orm");
        this.action = useService("action");
        this.notification = useService("notification");

        // Reactive state
        this.state = useState({
            books: [],
            totalBooks: 0,
            totalMembers: 0,
            activeLoans: 0,
            loading: true,
        });

        // Lifecycle: dipanggil sebelum component mount
        onWillStart(async () => {
            await this.loadData();
        });
    }

    async loadData() {
        this.state.loading = true;

        // ORM calls ke backend
        const [books, totalBooks, totalMembers, activeLoans] = await Promise.all([
            this.orm.searchRead("library.book", [], ["name", "author", "available_copies"], {
                limit: 10,
                order: "create_date desc",
            }),
            this.orm.searchCount("library.book", []),
            this.orm.searchCount("library.member", [["state", "=", "active"]]),
            this.orm.searchCount("library.loan", [["state", "=", "active"]]),
        ]);

        this.state.books = books;
        this.state.totalBooks = totalBooks;
        this.state.totalMembers = totalMembers;
        this.state.activeLoans = activeLoans;
        this.state.loading = false;
    }

    openBook(bookId) {
        this.action.doAction({
            type: "ir.actions.act_window",
            res_model: "library.book",
            res_id: bookId,
            views: [[false, "form"]],
        });
    }

    openLoans() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Active Loans",
            res_model: "library.loan",
            views: [[false, "list"], [false, "form"]],
            domain: [["state", "=", "active"]],
        });
    }

    async refreshData() {
        await this.loadData();
        this.notification.add("Dashboard refreshed!", { type: "success" });
    }
}

// Register sebagai client action
registry.category("actions").add("library_dashboard", BookDashboard);
```

### XML Template (OWL QWeb)

```xml
<?xml version="1.0" encoding="utf-8"?>
<templates xml:space="preserve">
    <t t-name="library_management.BookDashboard">
        <div class="o_library_dashboard">
            <!-- Loading spinner -->
            <div t-if="state.loading" class="text-center p-5">
                <i class="fa fa-spinner fa-spin fa-3x"/>
            </div>

            <div t-else="">
                <!-- Summary cards -->
                <div class="row g-3 mb-4">
                    <div class="col-md-4">
                        <div class="card bg-primary text-white">
                            <div class="card-body text-center">
                                <h3 t-out="state.totalBooks"/>
                                <p>Total Books</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="card bg-success text-white">
                            <div class="card-body text-center">
                                <h3 t-out="state.totalMembers"/>
                                <p>Active Members</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-4" t-on-click="openLoans" style="cursor: pointer;">
                        <div class="card bg-warning text-white">
                            <div class="card-body text-center">
                                <h3 t-out="state.activeLoans"/>
                                <p>Active Loans</p>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Book list -->
                <div class="card">
                    <div class="card-header d-flex justify-content-between">
                        <h5>Recent Books</h5>
                        <button class="btn btn-sm btn-outline-primary"
                                t-on-click="refreshData">
                            <i class="fa fa-refresh"/> Refresh
                        </button>
                    </div>
                    <div class="card-body p-0">
                        <table class="table table-hover mb-0">
                            <thead>
                                <tr>
                                    <th>Title</th>
                                    <th>Author</th>
                                    <th>Available</th>
                                </tr>
                            </thead>
                            <tbody>
                                <t t-foreach="state.books" t-as="book" t-key="book.id">
                                    <tr t-on-click="() => this.openBook(book.id)"
                                        style="cursor: pointer;">
                                        <td t-out="book.name"/>
                                        <td t-out="book.author"/>
                                        <td t-out="book.available_copies"/>
                                    </tr>
                                </t>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
    </t>
</templates>
```

### SCSS Styling

```scss
// static/src/components/book_dashboard.scss
.o_library_dashboard {
    padding: 20px;
    max-width: 1200px;
    margin: 0 auto;

    .card {
        border-radius: 8px;
        box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        transition: transform 0.2s;

        &:hover {
            transform: translateY(-2px);
        }
    }
}
```

---

## Memanggil Dashboard via Client Action

```xml
<!-- views/menu.xml -->
<record id="action_library_dashboard" model="ir.actions.client">
    <field name="name">Library Dashboard</field>
    <field name="tag">library_dashboard</field>  <!-- harus cocok dengan registry.add -->
</record>

<menuitem id="menu_library_dashboard"
          name="Dashboard"
          parent="menu_library_root"
          action="action_library_dashboard"
          sequence="1"/>
```

---

## OWL Services yang Sering Dipakai

```javascript
setup() {
    // ORM: CRUD operations ke backend
    this.orm = useService("orm");

    // Action: navigate, buka form/wizard
    this.action = useService("action");

    // Notification: toast messages
    this.notification = useService("notification");

    // RPC: custom RPC call
    this.rpc = useService("rpc");

    // Dialog: popup konfirmasi
    this.dialog = useService("dialog");

    // User: info user yang login
    this.user = useService("user");
}
```

### Contoh Penggunaan ORM Service

```javascript
// search_read: cari dan baca records
const books = await this.orm.searchRead(
    "library.book",                          // model
    [["state", "=", "available"]],           // domain
    ["name", "author", "price"],             // fields
    { limit: 20, offset: 0, order: "name" } // options
);

// read: baca record by IDs
const records = await this.orm.read("library.book", [1, 2, 3], ["name", "price"]);

// create: buat record baru
const newId = await this.orm.create("library.book", { name: "New Book", author: "Author" });

// write: update record
await this.orm.write("library.book", [bookId], { price: 150 });

// unlink: delete record
await this.orm.unlink("library.book", [bookId]);

// call: panggil method Python custom
const result = await this.orm.call("library.loan", "action_confirm", [[loanId]]);

// searchCount
const count = await this.orm.searchCount("library.book", [["active", "=", true]]);
```

---

## Extend/Override Component yang Sudah Ada

### Patch Component Existing

```javascript
/** @odoo-module **/

import { patch } from "@web/core/utils/patch";
import { FormController } from "@web/views/form/form_controller";

patch(FormController.prototype, {
    setup() {
        super.setup(...arguments);
        // Tambah logic setelah setup parent
        console.log("Form opened for model:", this.props.resModel);
    },

    async onWillSaveRecord(record) {
        // Tambah validasi sebelum save
        if (record.resModel === "library.loan" && !record.data.line_ids.records.length) {
            this.notification.add("Please add at least one book!", { type: "danger" });
            return false;
        }
        return super.onWillSaveRecord(...arguments);
    },
});
```

### Extend View dengan JS

```javascript
/** @odoo-module **/

import { registry } from "@web/core/registry";
import { listView } from "@web/views/list/list_view";
import { ListController } from "@web/views/list/list_controller";

class BookListController extends ListController {
    setup() {
        super.setup();
        this.notification = useService("notification");
    }

    async onClickExportBooks() {
        const ids = this.model.root.selection.map((r) => r.resId);
        if (!ids.length) {
            this.notification.add("Select books to export!", { type: "warning" });
            return;
        }
        // Custom export logic
        await this.orm.call("library.book", "action_export", [ids]);
        this.notification.add("Books exported!", { type: "success" });
    }
}

// Register custom list view
registry.category("views").add("book_list", {
    ...listView,
    Controller: BookListController,
    buttonTemplate: "library_management.BookListButtons",
});
```

```xml
<!-- Template untuk extra buttons -->
<t t-name="library_management.BookListButtons" t-inherit="web.ListView.Buttons">
    <xpath expr="//div[hasclass('o_list_buttons')]" position="inside">
        <button class="btn btn-secondary"
                t-on-click="onClickExportBooks">
            <i class="fa fa-download"/> Export Books
        </button>
    </xpath>
</t>
```

Pakai di XML view:

```xml
<record id="view_library_book_tree" model="ir.ui.view">
    <field name="name">library.book.tree</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <tree js_class="book_list">
            <field name="name"/>
            <field name="author"/>
        </tree>
    </field>
</record>
```

---

## OWL Lifecycle Hooks

```javascript
import { Component, onWillStart, onMounted, onWillUpdateProps,
         onPatched, onWillUnmount } from "@odoo/owl";

class MyComponent extends Component {
    setup() {
        // Sebelum component pertama kali render (async OK)
        onWillStart(async () => {
            await this.loadInitialData();
        });

        // Setelah component ter-mount di DOM
        onMounted(() => {
            this.initChart();
        });

        // Sebelum props berubah (async OK)
        onWillUpdateProps(async (nextProps) => {
            if (nextProps.bookId !== this.props.bookId) {
                await this.loadBookData(nextProps.bookId);
            }
        });

        // Setelah DOM di-update karena state/props change
        onPatched(() => {
            this.updateChart();
        });

        // Sebelum component di-unmount (cleanup)
        onWillUnmount(() => {
            this.destroyChart();
        });
    }
}
```

---

## Widget Custom untuk Field

```javascript
/** @odoo-module **/

import { registry } from "@web/core/registry";
import { standardFieldProps } from "@web/views/fields/standard_field_props";
import { Component } from "@odoo/owl";

class StarRatingField extends Component {
    static template = "library_management.StarRatingField";
    static props = { ...standardFieldProps };

    get stars() {
        const value = this.props.record.data[this.props.name] || 0;
        return Array.from({ length: 5 }, (_, i) => i < value);
    }

    onStarClick(index) {
        if (!this.props.readonly) {
            this.props.record.update({ [this.props.name]: index + 1 });
        }
    }
}

// Register sebagai field widget
registry.category("fields").add("star_rating", {
    component: StarRatingField,
    supportedTypes: ["integer"],
});
```

```xml
<t t-name="library_management.StarRatingField">
    <div class="d-inline-flex">
        <t t-foreach="stars" t-as="filled" t-key="filled_index">
            <i t-att-class="filled ? 'fa fa-star text-warning' : 'fa fa-star-o text-muted'"
               t-on-click="() => this.onStarClick(filled_index)"
               style="cursor: pointer; font-size: 18px; margin-right: 2px;"/>
        </t>
    </div>
</t>
```

Pakai di XML view:

```xml
<field name="rating" widget="star_rating"/>
```

---

## Systray Item (Icon di Top Bar)

```javascript
/** @odoo-module **/

import { Component, useState } from "@odoo/owl";
import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";

class LibraryNotification extends Component {
    static template = "library_management.SystrayItem";

    setup() {
        this.action = useService("action");
        this.orm = useService("orm");
        this.state = useState({ overdueCount: 0 });
        this.loadOverdueCount();
    }

    async loadOverdueCount() {
        this.state.overdueCount = await this.orm.searchCount(
            "library.loan",
            [["is_overdue", "=", true]]
        );
    }

    onClick() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Overdue Loans",
            res_model: "library.loan",
            views: [[false, "list"], [false, "form"]],
            domain: [["is_overdue", "=", true]],
        });
    }
}

registry.category("systray").add("library_notification", {
    Component: LibraryNotification,
});
```

```xml
<t t-name="library_management.SystrayItem">
    <div class="o_nav_entry" t-on-click="onClick" role="button">
        <i class="fa fa-book"/>
        <span t-if="state.overdueCount > 0"
              class="badge rounded-pill bg-danger"
              t-out="state.overdueCount"/>
    </div>
</t>
```

---

## Tips JavaScript Odoo 18

1. **Selalu tambah `/** @odoo-module **/`** di baris pertama JS — tanpa ini, Odoo tidak mengenali sebagai ES module
2. **Gunakan `useState`** untuk reactive state — mirip React hooks
3. **Gunakan `useService`** untuk akses backend — jangan pakai `fetch` atau `XMLHttpRequest` langsung
4. **`registry`** — sistem plugin Odoo: semua extension didaftarkan via registry
5. **`patch`** — cara aman override component yang sudah ada tanpa mengganti seluruhnya
6. **Assets harus di-rebuild** setelah edit JS: Settings > Technical > Clear JS Assets Cache, atau restart server dengan `--dev=all`
