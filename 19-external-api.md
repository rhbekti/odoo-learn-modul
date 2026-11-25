# Bab 19: External API (XML-RPC & JSON-RPC)

> **Tahap:** 5 Profesional | **Prasyarat:** Bab 4, Bab 10, Bab 12 | **Estimasi:** ± 2,5 jam | **Versi:** Odoo 18 (catatan Odoo 19)

Odoo menyediakan API untuk mengakses data dari aplikasi eksternal (Python, PHP, Node.js, mobile app, dll). Contoh di bab ini memakai model Library dari Bab 10 (module `library_management`).

> **Penting:** Odoo (termasuk versi 18) **tidak menyediakan REST API bawaan**. API resmi yang built-in adalah **XML-RPC** dan **JSON-RPC** (keduanya bergaya RPC, bukan REST). Kalau butuh endpoint bergaya REST (`GET /api/v1/books`, dsb), itu harus **dibuat sendiri** memakai `http.Controller`; lihat bagian 5. Jangan menganggap REST sebagai fitur native Odoo 18.

> Akses ke external API di Odoo Online hanya tersedia pada paket Custom (menurut dokumentasi 18). Di instance sendiri (self-hosted/Docker seperti di Bab 1) tidak ada batasan itu.

## Tujuan Belajar

Setelah bab ini kamu bisa:

- Membedakan XML-RPC, JSON-RPC, dan endpoint REST-style custom.
- Autentikasi dengan `authenticate` dan API key, lalu memanggil `execute_kw`.
- Melakukan search, read, create, write, unlink, dan memanggil method custom lewat API.
- Menulis field relasi (One2many/Many2many) dengan command tuple.
- Membuat endpoint REST-style sederhana dengan `http.Controller` beserta autentikasi token.

## Jenis API

| API | Protocol | Status di Odoo | Kapan Dipakai |
|-----|----------|----------------|---------------|
| XML-RPC | XML over HTTP | Built-in (resmi) | Stabil, didukung banyak bahasa |
| JSON-RPC | JSON over HTTP | Built-in (resmi) | Lebih ringan, mudah di-debug |
| REST-style custom | HTTP REST | **Custom (bukan bawaan Odoo)** | Dibuat sendiri via `http.Controller` untuk tim frontend/mobile yang terbiasa REST |

---

## 1. Autentikasi dan API Key

Semua panggilan XML-RPC/JSON-RPC butuh: nama database, user id (`uid`), dan password. Sejak Odoo 14 kamu bisa memakai **API key** sebagai pengganti password; `login` tetap dipakai. Buat key di Preferences (My Profile) > tab Account Security > New API Key. Simpan seperti password: key memberi akses setara user tersebut (tapi tidak bisa dipakai login lewat UI).

```python
import os
import xmlrpc.client

URL = 'http://localhost:8069'
DB = 'odoo'
USERNAME = 'admin'
PASSWORD = os.environ['ODOO_API_KEY']   # API key (atau password) jangan ditulis di kode

common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

# Cek versi (tidak butuh login)
print(common.version()['server_version'])

# Login: dapatkan uid (False jika gagal)
uid = common.authenticate(DB, USERNAME, PASSWORD, {})
print(f'Authenticated as uid: {uid}')
```

Dua endpoint XML-RPC: `/xmlrpc/2/common` (versi, authenticate) dan `/xmlrpc/2/object` (memanggil method model lewat `execute_kw`).

---

## 2. XML-RPC: CRUD dengan `execute_kw`

Parameter `execute_kw`: `db, uid, password, model, method, [args posisi], {kwargs}`.

```python
# === SEARCH: hanya ID ===
book_ids = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'search',
    [[
        ('available_copies', '>', 0),
        ('author', 'ilike', 'fitzgerald'),
    ]],                                          # args: domain
    {'limit': 10, 'offset': 0, 'order': 'name ASC'},   # kwargs
)

# === READ: baca dari ID ===
books = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'read',
    [book_ids],
    {'fields': ['name', 'author', 'isbn', 'available_copies']},
)

# === SEARCH_READ: search + read dalam satu panggilan ===
books = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'search_read',
    [[('active', '=', True)]],
    {'fields': ['name', 'author', 'isbn', 'category_id'],
     'limit': 20, 'offset': 0, 'order': 'name ASC'},
)

# === SEARCH_COUNT ===
count = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'search_count',
    [[('available_copies', '>', 0)]],
)

# === CREATE: mengembalikan ID record baru ===
new_book_id = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'create',
    [{
        'name': 'New Book via API',
        'author': 'API Author',
        'isbn': '978-0-00-999999-9',
        'category_id': 1,     # category_id wajib di model Bab 10
    }],
)

# === WRITE: update ===
models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'write',
    [[new_book_id], {'author': 'Updated Author'}],
)

# === UNLINK: hapus ===
models.execute_kw(DB, uid, PASSWORD, 'library.book', 'unlink', [[new_book_id]])

# === Method custom (method publik, tanpa awalan underscore) ===
models.execute_kw(
    DB, uid, PASSWORD,
    'library.loan', 'action_confirm',
    [[loan_id]],              # args: list ID record
)
```

Catatan:

- `search` dan `search_read` menerima domain di **args**; `fields`, `limit`, `offset`, `order` di **kwargs**.
- Method yang namanya diawali `_` (privat) tidak bisa dipanggil lewat API.
- Method yang mengembalikan recordset atau objek yang tidak bisa diserialisasi akan gagal. Jika kamu menulis method untuk dipanggil dari API, kembalikan `True` atau dict/list sederhana.

### Field Relasi

```python
# Create loan dengan lines sekaligus (One2many)
loan_id = models.execute_kw(
    DB, uid, PASSWORD,
    'library.loan', 'create',
    [{
        'member_id': 1,
        'loan_date': '2026-05-18',
        'due_date': '2026-06-01',
        'line_ids': [
            (0, 0, {'copy_id': 1}),   # buat line baru
            (0, 0, {'copy_id': 2}),
        ],
    }],
)

# Update Many2many
models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'write',
    [[book_id], {'tag_ids': [
        (4, tag_id_1),        # link tag yang sudah ada
        (4, tag_id_2),
        (3, old_tag_id),      # lepas link (tag tidak dihapus)
    ]}],
)

# Membaca field relasi
books = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'read',
    [[1]], {'fields': ['name', 'category_id', 'tag_ids', 'copy_ids']},
)
# category_id -> [id, "display_name"]  (Many2one)
# tag_ids / copy_ids -> [id1, id2, ...]  (x2many)
```

Ringkasan command tuple: `(0, 0, vals)` buat, `(1, id, vals)` update, `(2, id)` hapus, `(3, id)` lepas, `(4, id)` link, `(5,)` lepas semua, `(6, 0, [ids])` ganti semua.

---

## 3. JSON-RPC

Endpoint `/jsonrpc` menerima payload `{jsonrpc, method: 'call', params: {service, method, args}}`. Layanan yang sama dengan XML-RPC: `common` dan `object` (dengan method `execute_kw`).

### Python (`requests`)

```python
import os
import requests

URL = 'http://localhost:8069'
DB = 'odoo'
USERNAME = 'admin'
PASSWORD = os.environ['ODOO_API_KEY']


def json_rpc(service, method, args):
    payload = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {'service': service, 'method': method, 'args': args},
        'id': 1,
    }
    result = requests.post(f'{URL}/jsonrpc', json=payload, timeout=30).json()
    if 'error' in result:
        raise Exception(result['error']['data']['message'])
    return result['result']


uid = json_rpc('common', 'authenticate', [DB, USERNAME, PASSWORD, {}])

books = json_rpc('object', 'execute_kw', [
    DB, uid, PASSWORD,
    'library.book', 'search_read',
    [[('active', '=', True)]],
    {'fields': ['name', 'author'], 'limit': 10},
])
for book in books:
    print(f"{book['id']}: {book['name']}")

new_id = json_rpc('object', 'execute_kw', [
    DB, uid, PASSWORD,
    'library.book', 'create',
    [{'name': 'API Book', 'author': 'API', 'category_id': 1}],
])
```

### Node.js

```javascript
// Node.js 18+ sudah punya fetch bawaan
const URL = 'http://localhost:8069';
const DB = 'odoo';
const USERNAME = 'admin';
const PASSWORD = process.env.ODOO_API_KEY;

async function jsonRpc(service, method, args) {
    const response = await fetch(`${URL}/jsonrpc`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            jsonrpc: '2.0',
            method: 'call',
            params: { service, method, args },
            id: 1,
        }),
    });
    const data = await response.json();
    if (data.error) throw new Error(data.error.data.message);
    return data.result;
}

async function main() {
    const uid = await jsonRpc('common', 'authenticate', [DB, USERNAME, PASSWORD, {}]);
    const books = await jsonRpc('object', 'execute_kw', [
        DB, uid, PASSWORD,
        'library.book', 'search_read',
        [[['active', '=', true]]],
        { fields: ['name', 'author'], limit: 10 },
    ]);
    books.forEach(book => console.log(`${book.id}: ${book.name}`));
}

main();
```

---

## 4. Python Helper Class (Reusable Client)

```python
"""odoo_client.py: client XML-RPC yang bisa dipakai ulang."""
import xmlrpc.client


class OdooClient:
    def __init__(self, url, db, username, password):
        self.db = db
        self.password = password
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        self.models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
        self.uid = common.authenticate(db, username, password, {})
        if not self.uid:
            raise Exception('Authentication failed')

    def execute(self, model, method, *args, **kwargs):
        return self.models.execute_kw(
            self.db, self.uid, self.password, model, method, list(args), kwargs
        )

    def search_read(self, model, domain, fields=None, **kwargs):
        return self.execute(model, 'search_read', domain,
                            fields=fields or [], **kwargs)

    def create(self, model, vals):
        return self.execute(model, 'create', vals)

    def write(self, model, ids, vals):
        return self.execute(model, 'write', ids, vals)

    def unlink(self, model, ids):
        return self.execute(model, 'unlink', ids)

    def count(self, model, domain):
        return self.execute(model, 'search_count', domain)


# Penggunaan
client = OdooClient('http://localhost:8069', 'odoo', 'admin', 'API_KEY_ATAU_PASSWORD')
books = client.search_read('library.book', [('active', '=', True)],
                           fields=['name', 'author'], limit=10)
book_id = client.create('library.book', {'name': 'API Book', 'category_id': 1})
client.write('library.book', [book_id], {'author': 'New Author'})
client.unlink('library.book', [book_id])
```

---

## 5. Custom REST-Style Endpoint (`http.Controller`)

Karena Odoo tidak punya REST API bawaan, endpoint bergaya REST dibuat sendiri di module (pengetahuan routing: Bab 12). Contoh ini memakai autentikasi token sederhana.

> Model `library.api.key` di bawah **bukan bagian Bab 10**; ia hanya ilustrasi. Kamu perlu membuatnya sendiri (field `token`, `user_id`, `active`, plus access rights), atau memakai mekanisme autentikasi lain. Simpan token sebagai hash di production, bukan teks biasa.

```python
# controllers/api.py
import json

from odoo import http
from odoo.http import request, Response


class LibraryRestAPI(http.Controller):

    def _json_response(self, data, status=200):
        return Response(
            json.dumps(data, default=str),
            status=status,
            content_type='application/json',
        )

    def _authenticate(self):
        """Autentikasi token sederhana lewat header Authorization: Bearer <token>."""
        token = request.httprequest.headers.get('Authorization', '').replace('Bearer ', '')
        if not token:
            return None
        api_key = request.env['library.api.key'].sudo().search([
            ('token', '=', token),
            ('active', '=', True),
        ], limit=1)
        return api_key.user_id if api_key else None

    # GET /api/v1/books
    @http.route('/api/v1/books', type='http', auth='none',
                methods=['GET'], csrf=False)
    def get_books(self, **kwargs):
        user = self._authenticate()
        if not user:
            return self._json_response({'error': 'Unauthorized'}, 401)

        limit = int(kwargs.get('limit', 20))
        offset = int(kwargs.get('offset', 0))
        search = kwargs.get('search', '')

        domain = [('active', '=', True)]
        if search:
            domain.append(('name', 'ilike', search))

        Book = request.env['library.book'].with_user(user)
        books = Book.search_read(
            domain,
            ['name', 'author', 'isbn', 'available_copies', 'category_id'],
            limit=limit, offset=offset, order='name ASC',
        )
        return self._json_response({
            'data': books,
            'total': Book.search_count(domain),
            'limit': limit,
            'offset': offset,
        })

    # GET /api/v1/books/<id>
    @http.route('/api/v1/books/<int:book_id>', type='http', auth='none',
                methods=['GET'], csrf=False)
    def get_book(self, book_id, **kwargs):
        user = self._authenticate()
        if not user:
            return self._json_response({'error': 'Unauthorized'}, 401)

        book = request.env['library.book'].with_user(user).browse(book_id)
        if not book.exists():
            return self._json_response({'error': 'Not found'}, 404)

        return self._json_response({'data': {
            'id': book.id,
            'name': book.name,
            'author': book.author,
            'isbn': book.isbn,
            'category': book.category_id.name,
            'available_copies': book.available_copies,
            'total_copies': book.total_copies,
        }})

    # POST /api/v1/books
    @http.route('/api/v1/books', type='http', auth='none',
                methods=['POST'], csrf=False)
    def create_book(self, **kwargs):
        user = self._authenticate()
        if not user:
            return self._json_response({'error': 'Unauthorized'}, 401)

        try:
            data = json.loads(request.httprequest.data)
        except json.JSONDecodeError:
            return self._json_response({'error': 'Invalid JSON'}, 400)

        missing = [f for f in ('name', 'category_id') if f not in data]
        if missing:
            return self._json_response(
                {'error': f'Missing fields: {", ".join(missing)}'}, 400)

        try:
            book = request.env['library.book'].with_user(user).create(data)
        except Exception as e:
            return self._json_response({'error': str(e)}, 400)
        return self._json_response({'data': {'id': book.id}}, 201)

    # PUT /api/v1/books/<id>
    @http.route('/api/v1/books/<int:book_id>', type='http', auth='none',
                methods=['PUT'], csrf=False)
    def update_book(self, book_id, **kwargs):
        user = self._authenticate()
        if not user:
            return self._json_response({'error': 'Unauthorized'}, 401)

        book = request.env['library.book'].with_user(user).browse(book_id)
        if not book.exists():
            return self._json_response({'error': 'Not found'}, 404)

        try:
            book.write(json.loads(request.httprequest.data))
        except Exception as e:
            return self._json_response({'error': str(e)}, 400)
        return self._json_response({'data': {'id': book.id}})

    # DELETE /api/v1/books/<id>
    @http.route('/api/v1/books/<int:book_id>', type='http', auth='none',
                methods=['DELETE'], csrf=False)
    def delete_book(self, book_id, **kwargs):
        user = self._authenticate()
        if not user:
            return self._json_response({'error': 'Unauthorized'}, 401)

        book = request.env['library.book'].with_user(user).browse(book_id)
        if not book.exists():
            return self._json_response({'error': 'Not found'}, 404)

        book.unlink()
        return self._json_response({'data': {'deleted': True}})
```

Catatan keamanan dan perilaku:

- `auth='none'` berarti Odoo tidak membuat sesi user. Jika server memuat lebih dari satu database, pastikan database terpilih (`db_name`/`dbfilter`, Bab 2), kalau tidak `request.env` tidak punya registry.
- `with_user(user)` membuat ORM mengikuti access rights dan record rule user itu, jadi API tidak membuka data lebih dari yang boleh diakses user tersebut.
- `csrf=False` wajar untuk API non-browser. Pasang `cors='*'` **hanya** jika memang butuh dipanggil dari browser lain asal; default-nya jangan dibuka.
- Pesan `str(e)` ke klien bisa membocorkan detail internal; di production kembalikan pesan generik dan catat detailnya di log (Bab 18).

### Memanggil Endpoint

```bash
# Daftar buku
curl -H "Authorization: Bearer YOUR_TOKEN" \
     "http://localhost:8069/api/v1/books?limit=10"

# Satu buku
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:8069/api/v1/books/1

# Buat buku
curl -X POST \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"name": "New Book", "author": "Author", "category_id": 1}' \
     http://localhost:8069/api/v1/books

# Update
curl -X PUT \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"author": "Updated Author"}' \
     http://localhost:8069/api/v1/books/1

# Hapus
curl -X DELETE -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:8069/api/v1/books/1
```

---

## Tips External API

1. Pakai `search_read`, bukan `search` + `read` terpisah (satu panggilan, bukan dua).
2. Selalu tentukan `fields`; jangan baca semua field jika hanya butuh beberapa.
3. Pakai `limit` dan `offset` agar tidak membaca semua record sekaligus.
4. Atur timeout di client (mis. `timeout=30` pada `requests`) dan tangani error (`xmlrpc.client.Fault` pada XML-RPC).
5. Buat user khusus untuk integrasi, dengan hak akses minimum; jangan pakai admin.
6. Rate limiting tidak disediakan sebagai fitur bawaan Odoo untuk API; pasang di reverse proxy seperti Nginx (Bab 20).
7. HTTPS wajib di production karena kredensial dikirim di setiap request.

> **Beda di Odoo 19:**
> - XML-RPC (`/xmlrpc`, `/xmlrpc/2`) dan JSON-RPC (`/jsonrpc`) tetap berjalan di Odoo 19 tetapi sudah deprecated; menurut dokumentasi 19 dijadwalkan dihapus di Odoo 22 (musim gugur 2028) / Odoo Online 21.1 (musim dingin 2027).
> - Penggantinya adalah JSON-2 API: `POST /json/2/<model>/<method>` dengan header `Authorization: bearer <API key>`, argumen bernama, kode status HTTP bermakna, dan satu transaksi per panggilan.
> - Untuk controller custom, dokumentasi 19 menyebut `type='json'` dikenal hingga Odoo 18 dan kini bernama `type='jsonrpc'` (tidak termasuk deprecation di atas).
> - Dokumentasi: https://www.odoo.com/documentation/19.0/developer/reference/external_api.html

## Ringkasan

- Odoo hanya punya API resmi XML-RPC dan JSON-RPC (bergaya RPC); tidak ada REST API bawaan.
- Alurnya: `authenticate` untuk mendapat `uid`, lalu `execute_kw` dengan args posisi dan kwargs (`fields`, `limit`, `offset`, `order`).
- API key (sejak Odoo 14) dipakai sebagai pengganti password; simpan di environment variable.
- `create` mengembalikan ID; `write`/`unlink` dipanggil dengan list ID; field relasi ditulis dengan command tuple seperti `(0, 0, vals)` dan `(4, id)`.
- JSON-RPC memakai endpoint `/jsonrpc` dengan payload `{jsonrpc, method: 'call', params: {service, method, args}}`.
- Endpoint REST-style harus dibuat sendiri lewat `http.Controller`, dengan autentikasi token, `with_user`, dan kode status HTTP yang jelas.

## Latihan

1. Tulis skrip Python XML-RPC yang login memakai API key, lalu menampilkan 5 buku dengan `available_copies` terbanyak (`search_read` dengan `order`, `limit`, `fields`).
2. Buat satu `library.loan` beserta dua line lewat satu panggilan `create`, lalu panggil `action_confirm` dan cek state copy-nya.
3. Tambahkan endpoint `GET /api/v1/members` ke controller contoh (dengan `limit`/`offset`), dan uji dengan `curl`. Lakukan juga panggilan tanpa token dan pastikan responsnya 401.

## Lanjut ke

Bab 20: Deployment & Performance.
