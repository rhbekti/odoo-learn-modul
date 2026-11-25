# Bab 12: Controllers & Routing

> **Tahap:** 3 Fitur Lanjutan | **Prasyarat:** Bab 3, 4, 6, 10, 11 | **Estimasi:** ± 3 jam | **Versi:** Odoo 18 (catatan Odoo 19)

Controller menerima HTTP request dan mengembalikan response: halaman website, file, atau data JSON. Di bab ini kita menambahkan halaman katalog buku publik dan endpoint JSON ke modul `library_management` (Bab 10).

## Tujuan Belajar

Setelah bab ini kamu bisa:

- Menulis controller dengan `@http.route` dan memilih `type`, `auth`, `methods`, serta `csrf` yang tepat.
- Me-render halaman website dari template QWeb dan membaca parameter URL maupun form.
- Mengembalikan redirect, file download, dan 404 dari controller.
- Membuat endpoint JSON dan menjelaskan cara memanggilnya.
- Menerapkan aturan keamanan dasar: batasi field, filter record, dan hindari `sudo()` tanpa pembatas.

## Persiapan: Dependensi dan Struktur

Halaman website memerlukan modul `website`. Tambahkan di manifest `library_management`:

```python
'depends': ['base', 'mail', 'website'],
'data': [
    # ... file yang sudah ada (Bab 10)
    'views/website_templates.xml',
],
```

```
library_management/
├── __init__.py          # from . import models, controllers
├── controllers/
│   ├── __init__.py      # from . import main
│   └── main.py
└── views/
    └── website_templates.xml
```

---

## 1. Controller Pertama

```python
# controllers/main.py
from odoo import http
from odoo.http import request


class LibraryController(http.Controller):

    @http.route('/library/books', type='http', auth='public', website=True)
    def list_books(self, **kwargs):
        # Pengunjung publik tidak punya akses baca ke library.book,
        # jadi pakai sudo() DENGAN filter yang eksplisit (lihat bagian 8).
        books = request.env['library.book'].sudo().search(
            [('active', '=', True), ('available_copies', '>', 0)]
        )
        return request.render('library_management.book_list', {
            'books': books,
        })

    @http.route('/library/book/<int:book_id>', type='http', auth='public', website=True)
    def detail_book(self, book_id, **kwargs):
        book = request.env['library.book'].sudo().browse(book_id).exists()
        if not book or not book.active:
            return request.not_found()
        return request.render('library_management.book_detail', {
            'book': book,
        })
```

Semua method controller adalah method dari `http.Controller`; nama class bebas, yang penting `@http.route`-nya terdaftar. `request.env` adalah environment milik user yang sedang mengakses (untuk `auth='public'`, user publik).

---

## 2. Parameter `@http.route`

```python
@http.route(
    '/path/to/page',           # URL; boleh list, boleh berisi <int:id>
    type='http',               # 'http' atau 'json'
    auth='public',             # 'public', 'user', 'none'
    methods=['GET', 'POST'],   # method HTTP yang diizinkan (kosong = semua)
    website=True,              # fitur website (layout, multi-bahasa, dsb.)
    csrf=True,                 # proteksi CSRF
    cors='*',                  # header Access-Control-Allow-Origin
)
```

**`auth`:**

| Nilai | Arti |
|-------|------|
| `'user'` | User harus login; request berjalan dengan hak user itu |
| `'public'` | Boleh login atau tidak; kalau tidak login, dijalankan sebagai user Public bersama |
| `'none'` | Selalu aktif, bahkan tanpa database; tidak ada akses ke user. Dipakai framework dan modul autentikasi |

**`type`:** `'http'` untuk halaman, file, dan redirect; `'json'` untuk endpoint JSON-RPC (bagian 6). `type` menentukan dari mana parameter dibaca dan bagaimana response diserialisasi.

**`csrf`:** aktif secara default untuk route `type='http'`, dan nonaktif secara default untuk route JSON (menurut dokumentasi). Mematikannya (`csrf=False`) hanya untuk endpoint yang memang dipanggil sistem luar, dan endpoint itu harus punya cara autentikasi sendiri.

**`cors`:** nilai untuk header `Access-Control-Allow-Origin`; hanya isi kalau situs lain memang perlu memanggil endpoint ini dari browser.

**`website=True`:** menambahkan konteks website ke request. Dibutuhkan kalau template memakai `website.layout`.

---

## 3. Template Website

```xml
<!-- views/website_templates.xml -->
<odoo>
    <template id="book_list" name="Book List">
        <t t-call="website.layout">
            <div id="wrap" class="container py-4">
                <h1>Library Books</h1>
                <div class="row">
                    <t t-foreach="books" t-as="book">
                        <div class="col-md-4 mb-3">
                            <div class="card">
                                <div class="card-body">
                                    <h5 class="card-title">
                                        <a t-attf-href="/library/book/#{book.id}" t-out="book.name"/>
                                    </h5>
                                    <p class="card-text" t-out="book.author"/>
                                    <span class="badge text-bg-success">
                                        <t t-out="book.available_copies"/> available
                                    </span>
                                </div>
                            </div>
                        </div>
                    </t>
                </div>
            </div>
        </t>
    </template>

    <template id="book_detail" name="Book Detail">
        <t t-call="website.layout">
            <div id="wrap" class="container py-4">
                <h1 t-out="book.name"/>
                <p>Author: <span t-out="book.author"/></p>
                <p>ISBN: <span t-out="book.isbn"/></p>
                <a href="/library/books" class="btn btn-secondary">Back</a>
            </div>
        </t>
    </template>
</odoo>
```

Gunakan `t-out` (bukan `t-esc`) untuk menampilkan data: ia meng-escape HTML sehingga aman dari XSS. `t-esc` adalah nama lama yang sudah deprecated.

---

## 4. Form dan Membaca Request

Form yang membuat record mewajibkan login, dan hak aksesnya mengikuti user tersebut (tidak memakai `sudo()`).

```xml
<template id="book_form" name="Add Book">
    <t t-call="website.layout">
        <div id="wrap" class="container py-4">
            <h1>Add New Book</h1>
            <form action="/library/book/submit" method="POST">
                <input type="hidden" name="csrf_token" t-att-value="request.csrf_token()"/>
                <div class="mb-3">
                    <label class="form-label" for="name">Title</label>
                    <input type="text" id="name" name="name" class="form-control" required="1"/>
                </div>
                <div class="mb-3">
                    <label class="form-label" for="author">Author</label>
                    <input type="text" id="author" name="author" class="form-control"/>
                </div>
                <button type="submit" class="btn btn-primary">Submit</button>
            </form>
        </div>
    </t>
</template>
```

```python
@http.route('/library/book/new', type='http', auth='user', website=True)
def new_book_form(self, **kwargs):
    return request.render('library_management.book_form')

@http.route('/library/book/submit', type='http', auth='user',
            methods=['POST'], website=True)
def submit_book(self, **post):
    # Ambil hanya field yang kita izinkan; jangan teruskan **post langsung ke create()
    book = request.env['library.book'].create({
        'name': post.get('name'),
        'author': post.get('author'),
    })
    return request.redirect(f'/library/book/{book.id}')
```

- Parameter dari query string, form, dan path (`<int:book_id>`) tiba sebagai argumen method; `**post` menampung sisanya.
- Token CSRF di form wajib karena route `type='http'` memeriksanya secara default.

---

## 5. Jenis Response `type='http'`

```python
# Redirect
@http.route('/library/home', type='http', auth='public', website=True)
def home(self, **kwargs):
    return request.redirect('/library/books')

# 404
@http.route('/library/missing', type='http', auth='public', website=True)
def missing(self, **kwargs):
    return request.not_found()

# File download
@http.route('/library/export/<int:loan_id>', type='http', auth='user')
def download_receipt(self, loan_id, **kwargs):
    loan = request.env['library.loan'].browse(loan_id).exists()
    if not loan:
        return request.not_found()
    report = request.env.ref('library_management.action_report_loan_receipt')
    pdf, _fmt = report._render_qweb_pdf(report.report_name, loan.ids)
    return request.make_response(pdf, headers=[
        ('Content-Type', 'application/pdf'),
        ('Content-Length', len(pdf)),
        ('Content-Disposition', f'attachment; filename="{loan.name}.pdf"'),
    ])
```

Contoh download memakai report dari Bab 11. Karena `auth='user'` dan tanpa `sudo()`, user yang tidak berhak atas loan itu akan ditolak oleh access rights/record rules (Bab 6).

---

## 6. Endpoint JSON

Route `type='json'` menerima dan mengembalikan JSON-RPC lewat HTTP POST. Return value method otomatis dibungkus menjadi response JSON.

```python
class LibraryAPI(http.Controller):

    @http.route('/library/api/books', type='json', auth='user')
    def get_books(self, limit=20, offset=0, **kwargs):
        books = request.env['library.book'].search_read(
            [('active', '=', True)],
            ['id', 'name', 'author', 'available_copies'],
            offset=offset,
            limit=min(limit, 100),     # batasi supaya tidak bisa minta semuanya
        )
        return {'data': books, 'count': len(books)}

    @http.route('/library/api/books/create', type='json', auth='user')
    def create_book(self, name, author=None, **kwargs):
        # Whitelist field; jangan create(kwargs) langsung
        book = request.env['library.book'].create({
            'name': name,
            'author': author,
        })
        return {'id': book.id}
```

Pemanggilan dari JavaScript (OWL, Bab 13) memakai fungsi `rpc` dari `@web/core/network/rpc`:

```javascript
import { rpc } from "@web/core/network/rpc";

const result = await rpc("/library/api/books", { limit: 5 });
```

Pemanggilan dari luar (mis. `curl`) harus berupa body JSON-RPC 2.0 dengan parameter bernama:

```json
{"jsonrpc": "2.0", "method": "call", "params": {"limit": 5}, "id": null}
```

dikirim dengan `POST` dan header `Content-Type: application/json`, plus session login (cookie). Kalau ada exception, Odoo mengembalikannya sebagai objek `error` di response JSON-RPC; tidak perlu `try/except` hanya untuk membungkus pesan error. Untuk integrasi sistem eksternal, Bab 19 membahas API resmi Odoo.

Catatan: route JSON hanya menerima POST dengan format JSON-RPC, jadi `methods=['PUT']` atau `['DELETE']` ala REST tidak cocok di sini. Untuk gaya REST, pakai `type='http'` dan susun sendiri response-nya.

---

## 7. Method Helper dan Asset Frontend

Method pembantu boleh ditaruh di class yang sama (nama diawali `_` agar tidak mudah disangka route):

```python
class LibraryController(http.Controller):

    def _prepare_values(self):
        return {
            'library_count': request.env['library.book'].sudo().search_count(
                [('active', '=', True)]
            ),
        }

    @http.route('/library/books', type='http', auth='public', website=True)
    def list_books(self, **kwargs):
        values = self._prepare_values()
        values['books'] = request.env['library.book'].sudo().search(
            [('active', '=', True)]
        )
        return request.render('library_management.book_list', values)
```

File CSS/JS untuk halaman website didaftarkan lewat manifest, ke bundle `web.assets_frontend`:

```
library_management/static/src/
├── css/library.css
└── js/library.js
```

```python
'assets': {
    'web.assets_frontend': [
        'library_management/static/src/css/library.css',
        'library_management/static/src/js/library.js',
    ],
},
```

Cara mendaftarkan asset dibahas lebih lengkap di Bab 13.

---

## 8. Keamanan Controller

Controller adalah pintu masuk dari internet, jadi perhatikan hal berikut:

1. **Pilih `auth` seketat mungkin.** Pakai `'user'` kecuali halaman memang publik.
2. **`sudo()` melewati access rights dan record rules.** Kalau dipakai di route `public`, tambahkan filter domain eksplisit (mis. hanya `active` dan tersedia), dan tampilkan hanya field yang aman. Jangan pernah `sudo().search([])` lalu menampilkan semuanya.
3. **Whitelist field saat `create`/`write`.** Jangan `create(kwargs)` atau `write(post)` langsung: pengguna bisa menyuntikkan field apa saja.
4. **Jangan matikan `csrf` tanpa alasan.** Route `type='http'` yang mengubah data harus tetap memakai token CSRF.
5. **Validasi input.** Parameter dari URL dan form selalu string kecuali ada converter (`<int:id>`); cek tipe dan batasnya.
6. **`t-out`, bukan HTML mentah.** Jangan menyisipkan input pengguna sebagai markup.

---

> **Beda di Odoo 19:** Dokumentasi Odoo 19 menyebut nilai `type` untuk route JSON sebagai `'jsonrpc'` (bersama `'http'`), sedangkan dokumentasi 18 menyebut `'json'`; kode di bab ini memakai `'json'` (Odoo 18), jadi ganti ke `'jsonrpc'` saat menargetkan 19 dan cek dokumentasi 19 untuk detailnya. Dokumentasi 19 juga mencantumkan `auth='bearer'` (autentikasi dengan API key lewat header `Authorization: Bearer`). Selain itu, 19 punya JSON-2 API (`/json/2/<model>/<method>`) untuk integrasi eksternal; itu terpisah dari controller buatan sendiri dan dibahas di Bab 19.

## Ringkasan

- Controller = class turunan `http.Controller` dengan method yang diberi `@http.route`.
- `type='http'` untuk halaman, file, dan redirect; `type='json'` (Odoo 18) untuk endpoint JSON-RPC.
- `auth`: `public` (siapa saja), `user` (harus login), `none` (tanpa database/user).
- Halaman website: `request.render('modul.template', values)` dengan `t-call="website.layout"`, dan modul perlu `depends` ke `website`.
- Form `POST` butuh `csrf_token`; redirect lewat `request.redirect()`, 404 lewat `request.not_found()`.
- Amankan controller: `auth` ketat, `sudo()` hanya dengan filter, whitelist field, validasi input.

## Latihan

1. Buat route `/library/books` yang menampilkan buku aktif dan tersedia, dengan link ke `/library/book/<id>`. Buka tanpa login, lalu coba buka ID buku yang di-archive dan pastikan hasilnya 404.
2. Tambahkan kolom pencarian: route yang sama menerima parameter `?q=` dan memfilter dengan `('name', 'ilike', q)`. Pastikan parameter kosong tidak merusak halaman.
3. Buat endpoint JSON `/library/api/books/count` (`auth='user'`) yang mengembalikan jumlah buku tersedia, lalu panggil dari konsol browser pada sesi yang sudah login memakai `fetch` dengan body JSON-RPC.

## Lanjut ke

Bab 13: OWL Components & JavaScript (`13-owl-javascript.md`).
