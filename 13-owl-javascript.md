# Bab 13: OWL Components & JavaScript (Frontend)

> **Tahap:** 3 Fitur Lanjutan | **Prasyarat:** Bab 3, 5, 10, 12 | **Estimasi:** ± 4 jam | **Versi:** Odoo 18 (catatan Odoo 19)

Odoo 18 memakai OWL (Odoo Web Library) sebagai framework JavaScript-nya (OWL 2 di Odoo 17/18). OWL mirip React/Vue, tapi dibuat Odoo sendiri. Di bab ini kita membuat dashboard, widget field, custom list view, dan item systray untuk modul `library_management` (Bab 10).

## Tujuan Belajar

Setelah bab ini kamu bisa:

- Mendaftarkan file JS, XML template, dan SCSS lewat key `assets` di manifest.
- Menulis komponen OWL (class `Component`, `setup()`, `useState`, `static template`) beserta template XML-nya.
- Memakai service (`orm`, `action`, `notification`, `dialog`) lewat `useService`, dan memanggil controller dengan `rpc`.
- Mendaftarkan komponen ke registry sebagai client action, field widget, view, dan item systray.
- Memodifikasi komponen yang sudah ada dengan `patch`, dan memahami lifecycle hook OWL.

---

## 1. Struktur File dan Registrasi Assets

```
library_management/
└── static/
    └── src/
        ├── components/
        │   ├── book_dashboard.js
        │   ├── book_dashboard.xml
        │   └── book_dashboard.scss
        ├── fields/
        │   ├── star_rating_field.js
        │   └── star_rating_field.xml
        ├── systray/
        │   ├── library_systray.js
        │   └── library_systray.xml
        └── views/
            ├── book_list_view.js
            └── book_list_view.xml
```

File JS, template XML, dan SCSS didaftarkan di `__manifest__.py` lewat key `assets`:

```python
'assets': {
    'web.assets_backend': [
        'library_management/static/src/**/*',
    ],
},
```

- `web.assets_backend`: bundle untuk web client (backend). Untuk halaman website publik, pakai `web.assets_frontend` (lihat Bab 12).
- Pola `**/*` mengambil semua file di bawahnya (JS, XML, SCSS).
- Mendaftarkan asset lewat manifest adalah cara standar di Odoo modern; hindari mewarisi template `web.assets_backend` untuk menyisipkan `<script>`.

**Soal `/** @odoo-module **/`:** menurut dokumentasi Odoo 18 dan 19, file di bawah `/static/src` dan `/static/tests` otomatis diubah menjadi Odoo module. Di folder lain, file baru diproses kalau baris pertamanya berisi komentar `/** @odoo-module **/`. Jadi untuk file di `static/src`, komentar itu tidak wajib; kita tetap menuliskannya di contoh bab ini karena aman dan umum dijumpai di kode lama.

---

## 2. Komponen OWL Pertama: Dashboard

### JavaScript

```javascript
/** @odoo-module **/

import { Component, useState, onWillStart } from "@odoo/owl";
import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";

class BookDashboard extends Component {
    static template = "library_management.BookDashboard";
    // Client action menerima props dari action service, jadi izinkan semua props
    static props = { "*": true };

    setup() {
        // Service: akses ke fitur Odoo (mirip dependency injection)
        this.orm = useService("orm");
        this.action = useService("action");
        this.notification = useService("notification");

        // Reactive state: perubahan otomatis me-render ulang template
        this.state = useState({
            books: [],
            totalBooks: 0,
            totalMembers: 0,
            activeLoans: 0,
            loading: true,
        });

        // Dipanggil sebelum render pertama; boleh async
        onWillStart(async () => {
            await this.loadData();
        });
    }

    async loadData() {
        this.state.loading = true;

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

// Daftarkan sebagai client action; tag ini dipakai oleh ir.actions.client
registry.category("actions").add("library_dashboard", BookDashboard);
```

Poin yang perlu dipahami:

- `static template` menunjuk ke `t-name` di file XML.
- `setup()` adalah pengganti constructor. Semua hook (`useState`, `useService`, `onWillStart`, ...) dipanggil di dalamnya.
- Assign ke `this.state.xxx` memicu render ulang; mengubah variabel biasa tidak.

### Template XML (QWeb versi OWL)

```xml
<?xml version="1.0" encoding="utf-8"?>
<templates xml:space="preserve">
    <t t-name="library_management.BookDashboard">
        <div class="o_library_dashboard">
            <div t-if="state.loading" class="text-center p-5">
                <i class="fa fa-spinner fa-spin fa-3x"/>
            </div>

            <div t-else="">
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

                <div class="card">
                    <div class="card-header d-flex justify-content-between">
                        <h5>Recent Books</h5>
                        <button class="btn btn-sm btn-outline-primary" t-on-click="refreshData">
                            <i class="fa fa-refresh"/> Refresh
                        </button>
                    </div>
                    <div class="card-body p-0">
                        <table class="table table-hover mb-0">
                            <thead>
                                <tr><th>Title</th><th>Author</th><th>Available</th></tr>
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

Aturan template OWL yang sering terlewat:

- `t-foreach` wajib punya `t-key` yang unik.
- Event pakai `t-on-click="namaMethod"`; kalau perlu argumen, pakai arrow function: `t-on-click="() => this.openBook(book.id)"`.
- Output data: `t-out` (dianjurkan). `t-esc` masih dikenali di kode lama.
- Ekspresi di dalam atribut `t-` adalah JavaScript, bukan Python (`state.loading`, `a ? b : c`).

### SCSS

```scss
// static/src/components/book_dashboard.scss
.o_library_dashboard {
    padding: 20px;
    max-width: 1200px;
    margin: 0 auto;

    .card {
        border-radius: 8px;
        box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    }
}
```

### Menampilkan lewat client action dan menu

```xml
<!-- views/menu.xml -->
<record id="action_library_dashboard" model="ir.actions.client">
    <field name="name">Library Dashboard</field>
    <field name="tag">library_dashboard</field>  <!-- harus sama dengan key di registry "actions" -->
</record>

<menuitem id="menu_library_dashboard"
          name="Dashboard"
          parent="menu_library_root"
          action="action_library_dashboard"
          sequence="1"/>
```

---

## 3. Service yang Sering Dipakai

```javascript
setup() {
    this.orm = useService("orm");                    // CRUD ke backend
    this.action = useService("action");              // buka form/list/wizard
    this.notification = useService("notification");  // toast
    this.dialog = useService("dialog");              // dialog/popup
}
```

### Contoh ORM service

```javascript
// search_read: domain, fields, opsi
const books = await this.orm.searchRead(
    "library.book",
    [["available_copies", ">", 0]],
    ["name", "author", "isbn"],
    { limit: 20, offset: 0, order: "name" }
);

// read: baca record berdasarkan ID
const records = await this.orm.read("library.book", [1, 2, 3], ["name", "isbn"]);

// create: menerima LIST nilai, mengembalikan list ID
const [newId] = await this.orm.create("library.book", [{ name: "New Book", author: "Author" }]);

// write dan unlink
await this.orm.write("library.book", [bookId], { author: "Other" });
await this.orm.unlink("library.book", [bookId]);

// call: panggil method Python (argumen pertama = list ID)
await this.orm.call("library.loan", "action_confirm", [[loanId]]);

// searchCount
const count = await this.orm.searchCount("library.book", [["active", "=", true]]);
```

### Memanggil controller dengan `rpc`

Untuk endpoint buatan sendiri (Bab 12), pakai fungsi `rpc` yang diimpor langsung. Service `rpc` lewat `useService("rpc")` tidak dipakai lagi di Odoo 18.

```javascript
import { rpc } from "@web/core/network/rpc";

onWillStart(async () => {
    const result = await rpc("/library/api/books", { limit: 5 });
    this.state.books = result.data;
});
```

---

## 4. Lifecycle Hook OWL

```javascript
import { Component, onWillStart, onMounted, onWillUpdateProps,
         onPatched, onWillUnmount } from "@odoo/owl";

class MyComponent extends Component {
    setup() {
        onWillStart(async () => { /* sebelum render pertama (async OK) */ });
        onMounted(() => { /* setelah masuk DOM; cocok untuk init chart */ });
        onWillUpdateProps(async (nextProps) => { /* sebelum props berubah (async OK) */ });
        onPatched(() => { /* setelah DOM di-update */ });
        onWillUnmount(() => { /* cleanup: lepas listener, destroy chart */ });
    }
}
```

---

## 5. Field Widget Custom

```javascript
/** @odoo-module **/

import { Component } from "@odoo/owl";
import { registry } from "@web/core/registry";
import { standardFieldProps } from "@web/views/fields/standard_field_props";

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

Pakai di form view (field `rating` bertipe Integer perlu kamu tambahkan sendiri ke model):

```xml
<field name="rating" widget="star_rating"/>
```

---

## 6. Custom List View dengan `js_class`

Kita menambah tombol "Export Books" di list view buku. Pertama controller dan registrasi view:

```javascript
/** @odoo-module **/

import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";
import { listView } from "@web/views/list/list_view";
import { ListController } from "@web/views/list/list_controller";

class BookListController extends ListController {
    setup() {
        super.setup();
        this.orm = useService("orm");
        this.notification = useService("notification");
    }

    async onClickExportBooks() {
        const ids = this.model.root.selection.map((r) => r.resId);
        if (!ids.length) {
            this.notification.add("Select books to export!", { type: "warning" });
            return;
        }
        // action_export adalah contoh: method ini harus kamu buat sendiri di library.book
        await this.orm.call("library.book", "action_export", [ids]);
        this.notification.add("Books exported!", { type: "success" });
    }
}

registry.category("views").add("book_list", {
    ...listView,
    Controller: BookListController,
    buttonTemplate: "library_management.BookListButtons",
});
```

Template tombol, mewarisi template tombol bawaan list view:

```xml
<t t-name="library_management.BookListButtons"
   t-inherit="web.ListView.Buttons" t-inherit-mode="primary">
    <xpath expr="//div[hasclass('o_list_buttons')]" position="inside">
        <button class="btn btn-secondary" t-on-click="onClickExportBooks">
            <i class="fa fa-download"/> Export Books
        </button>
    </xpath>
</t>
```

Pasang di XML view dengan `js_class` pada tag `<list>`:

```xml
<record id="view_library_book_list" model="ir.ui.view">
    <field name="name">library.book.list</field>
    <field name="model">library.book</field>
    <field name="arch" type="xml">
        <list js_class="book_list">
            <field name="name"/>
            <field name="author"/>
        </list>
    </field>
</record>
```

Nilai `js_class` harus sama dengan key di `registry.category("views")`. Struktur XPath di template tombol bawaan bisa berbeda antar versi, jadi cek source `web.ListView.Buttons` di instalasimu bila tombol tidak muncul.

---

## 7. Patch Komponen yang Sudah Ada

`patch` menambah atau menimpa perilaku komponen/class bawaan tanpa menyalin seluruhnya.

```javascript
/** @odoo-module **/

import { patch } from "@web/core/utils/patch";
import { FormController } from "@web/views/form/form_controller";

patch(FormController.prototype, {
    setup() {
        super.setup(...arguments);
        // logika tambahan setelah setup bawaan
        console.log("Form opened for model:", this.props.resModel);
    },
});
```

Aturan main:

- Selalu panggil `super.<method>(...arguments)` supaya perilaku asli tetap jalan.
- Patch mengubah semua instance, jadi cek kondisinya (mis. `this.props.resModel === "library.loan"`) sebelum bertindak.
- Nama method internal komponen bisa berubah antar versi. Kalau patch tidak berefek setelah upgrade, baca source komponennya.
- Untuk validasi data (mis. loan wajib punya minimal satu buku), lebih aman memakai `@api.constrains` di Python (Bab 4) daripada patch di JS.

---

## 8. Item Systray (Ikon di Top Bar)

```javascript
/** @odoo-module **/

import { Component, useState } from "@odoo/owl";
import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";

class LibraryNotification extends Component {
    static template = "library_management.SystrayItem";
    static props = {};

    setup() {
        this.action = useService("action");
        this.orm = useService("orm");
        this.state = useState({ overdueCount: 0 });
        this.loadOverdueCount();
    }

    get overdueDomain() {
        // is_overdue di Bab 10 tidak di-store, jadi tidak bisa dipakai di domain
        const today = new Date().toISOString().slice(0, 10);
        return [["state", "=", "active"], ["due_date", "<", today]];
    }

    async loadOverdueCount() {
        this.state.overdueCount = await this.orm.searchCount("library.loan", this.overdueDomain);
    }

    onClick() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Overdue Loans",
            res_model: "library.loan",
            views: [[false, "list"], [false, "form"]],
            domain: this.overdueDomain,
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

## 9. Registry: Ringkasan Kategori

| Kategori | Dipakai untuk | Contoh di bab ini |
|----------|---------------|-------------------|
| `actions` | Client action (`ir.actions.client`) | `library_dashboard` |
| `fields` | Field widget (`widget="..."`) | `star_rating` |
| `views` | View custom (`js_class="..."`) | `book_list` |
| `systray` | Item di top bar | `library_notification` |

---

## 10. Tips dan Debugging

1. Gunakan `useState` untuk data yang mempengaruhi tampilan.
2. Akses backend lewat `useService("orm")` atau `rpc`, bukan `fetch`/`XMLHttpRequest` langsung, supaya penanganan error dan session konsisten.
3. Daftarkan ekstensi lewat `registry`, dan ubah komponen bawaan dengan `patch`.
4. Setelah mengubah JS/XML/SCSS atau daftar `assets` di manifest, upgrade modul dan muat ulang browser (hard refresh). Menjalankan server dengan `--dev=all` membantu karena asset tidak di-cache.
5. Buka konsol browser (F12): error import, prop yang salah, atau `t-key` yang hilang terlihat di sana.
6. Error "props validation" biasanya berarti `static props` tidak mencakup props yang diterima komponen.

---

> **Beda di Odoo 19:** Dokumentasi 18 dan 19 sama-sama menyatakan file di `/static/src` otomatis menjadi Odoo module, dan `rpc` tetap diimpor dari `@web/core/network/rpc` (tercantum di halaman services kedua versi). Versi OWL di Odoo 19 tidak kami verifikasi, jadi cek dokumentasi frontend 19 sebelum menyalin hook, helper view, atau nama method internal dari bab ini.

## Ringkasan

- Daftarkan JS, XML, dan SCSS lewat `assets` di manifest (`web.assets_backend` untuk backend).
- Komponen OWL: class `Component` dengan `static template`, `setup()`, dan `useState` untuk state reaktif.
- Akses backend lewat service (`useService("orm")`, `"action"`, `"notification"`) dan fungsi `rpc` untuk controller; `useService("rpc")` sudah tidak dipakai di Odoo 18.
- Template OWL: `t-out` untuk output, `t-foreach` dengan `t-key`, `t-on-click` untuk event.
- Registry menyambungkan komponen ke Odoo: `actions`, `fields`, `views` (dengan `js_class` pada `<list>`), dan `systray`.
- `patch` mengubah komponen bawaan; panggil `super` dan jangan bergantung berlebihan pada method internal.

## Latihan

1. Buat client action "Library Dashboard" yang menampilkan jumlah buku, anggota aktif, dan loan aktif. Tambahkan menu dan pastikan angka sesuai data di list view.
2. Tambahkan field Integer `rating` ke `library.book`, buat widget `star_rating`, lalu pasang di form view. Pastikan klik bintang menyimpan nilai dan widget tidak bisa diklik saat form readonly.
3. Buat tombol "Export Books" di list view buku lewat `js_class`, lalu ganti `action_export` dengan method Python sederhana yang mengembalikan notifikasi jumlah buku terpilih.

## Lanjut ke

Bab 14: i18n & Multi-Company (`14-i18n-multi-company.md`).
