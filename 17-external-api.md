# Bab 17: External API (XML-RPC & JSON-RPC)

Odoo menyediakan API untuk mengakses data dari aplikasi eksternal (Python, PHP, Node.js, mobile app, dll).

> ⚠️ **Penting:** Odoo (termasuk versi 18) **tidak menyediakan REST API bawaan**. Satu-satunya API resmi yang built-in adalah **XML-RPC** dan **JSON-RPC** (keduanya RPC-style, bukan REST). Kalau butuh endpoint bergaya REST (`GET /api/v1/books`, dsb), itu harus **dibuat sendiri** memakai `http.Controller` — lihat bagian "Custom REST API Endpoint" di bawah. Jangan menganggap REST API sebagai fitur native Odoo 18.

## Jenis API

| API | Protocol | Status di Odoo | Kapan Dipakai |
|-----|---------|-----------------|---------------|
| XML-RPC | XML over HTTP | Built-in (resmi) | Paling stabil, didukung banyak bahasa |
| JSON-RPC | JSON over HTTP | Built-in (resmi) | Lebih ringan, mudah debug |
| REST-style custom | HTTP REST | **Custom (bukan bawaan Odoo)** | Dibuat sendiri via `http.Controller` saat butuh gaya REST yang familiar untuk tim frontend/mobile |

---

## XML-RPC (Python Client)

### Koneksi & Autentikasi

```python
import xmlrpc.client

# Konfigurasi
URL = 'http://localhost:8069'
DB = 'odoo'
USERNAME = 'admin'
PASSWORD = 'admin'

# Endpoint
common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

# Autentikasi: dapatkan uid
uid = common.authenticate(DB, USERNAME, PASSWORD, {})
print(f'Authenticated as uid: {uid}')

# Cek versi Odoo
version = common.version()
print(f'Odoo version: {version["server_version"]}')
```

### CRUD Operations

```python
# === SEARCH ===
# Cari book IDs
book_ids = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book',          # model
    'search',                # method
    [[                       # domain
        ('state', '=', 'available'),
        ('author', 'ilike', 'fitzgerald'),
    ]],
    {'limit': 10, 'offset': 0, 'order': 'name ASC'}
)
print(f'Found book IDs: {book_ids}')


# === READ ===
# Baca data dari IDs
books = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'read',
    [book_ids],                         # IDs
    {'fields': ['name', 'author', 'isbn', 'available_copies']}
)
for book in books:
    print(f"{book['name']} by {book['author']}")


# === SEARCH_READ (gabungan search + read) ===
books = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'search_read',
    [[('active', '=', True)]],          # domain
    {
        'fields': ['name', 'author', 'isbn', 'category_id'],
        'limit': 20,
        'offset': 0,
        'order': 'name ASC',
    }
)


# === SEARCH_COUNT ===
count = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'search_count',
    [[('state', '=', 'available')]]
)
print(f'Available books: {count}')


# === CREATE ===
new_book_id = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'create',
    [{
        'name': 'New Book via API',
        'author': 'API Author',
        'isbn': '978-0-00-999999-9',
        'category_id': 1,
    }]
)
print(f'Created book ID: {new_book_id}')


# === WRITE (update) ===
models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'write',
    [
        [new_book_id],                  # IDs to update
        {'author': 'Updated Author'}    # values
    ]
)


# === UNLINK (delete) ===
models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'unlink',
    [[new_book_id]]
)


# === CALL CUSTOM METHOD ===
result = models.execute_kw(
    DB, uid, PASSWORD,
    'library.loan', 'action_confirm',
    [[loan_id]]                         # args: record IDs
)
```

### Relational Fields via API

```python
# Create record dengan relasi
loan_id = models.execute_kw(
    DB, uid, PASSWORD,
    'library.loan', 'create',
    [{
        'member_id': 1,
        'loan_date': '2026-05-18',
        'due_date': '2026-06-01',
        # One2many: buat lines langsung
        'line_ids': [
            (0, 0, {'copy_id': 1}),       # Create new line
            (0, 0, {'copy_id': 2}),
        ],
    }]
)

# Update Many2many
models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'write',
    [
        [book_id],
        {
            'tag_ids': [
                (4, tag_id_1),             # Link existing tag
                (4, tag_id_2),
                (3, old_tag_id),           # Unlink tag
            ],
        }
    ]
)

# Read relational field
books = models.execute_kw(
    DB, uid, PASSWORD,
    'library.book', 'read',
    [[1]],
    {'fields': ['name', 'category_id', 'tag_ids', 'copy_ids']}
)
# category_id returns: [id, "display_name"]
# tag_ids returns: [id1, id2, id3]
# copy_ids returns: [id1, id2, id3]
```

---

## JSON-RPC (Python Client)

```python
import requests
import json

URL = 'http://localhost:8069'
DB = 'odoo'
USERNAME = 'admin'
PASSWORD = 'admin'

def json_rpc(url, method, params):
    payload = {
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
        'id': 1,
    }
    response = requests.post(url, json=payload)
    result = response.json()
    if 'error' in result:
        raise Exception(result['error']['data']['message'])
    return result['result']


# Autentikasi
uid = json_rpc(f'{URL}/jsonrpc', 'call', {
    'service': 'common',
    'method': 'authenticate',
    'args': [DB, USERNAME, PASSWORD, {}],
})
print(f'UID: {uid}')


# Search Read
books = json_rpc(f'{URL}/jsonrpc', 'call', {
    'service': 'object',
    'method': 'execute_kw',
    'args': [
        DB, uid, PASSWORD,
        'library.book', 'search_read',
        [[('active', '=', True)]],
        {'fields': ['name', 'author'], 'limit': 10},
    ],
})
for book in books:
    print(f"{book['id']}: {book['name']}")


# Create
new_id = json_rpc(f'{URL}/jsonrpc', 'call', {
    'service': 'object',
    'method': 'execute_kw',
    'args': [
        DB, uid, PASSWORD,
        'library.book', 'create',
        [{'name': 'API Book', 'author': 'API', 'category_id': 1}],
    ],
})
```

---

## JSON-RPC (JavaScript / Node.js)

```javascript
const fetch = require('node-fetch');

const URL = 'http://localhost:8069';
const DB = 'odoo';
const USERNAME = 'admin';
const PASSWORD = 'admin';

async function jsonRpc(url, method, params) {
    const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            jsonrpc: '2.0',
            method: method,
            params: params,
            id: 1,
        }),
    });
    const data = await response.json();
    if (data.error) throw new Error(data.error.data.message);
    return data.result;
}

async function main() {
    // Authenticate
    const uid = await jsonRpc(`${URL}/jsonrpc`, 'call', {
        service: 'common',
        method: 'authenticate',
        args: [DB, USERNAME, PASSWORD, {}],
    });

    // Search books
    const books = await jsonRpc(`${URL}/jsonrpc`, 'call', {
        service: 'object',
        method: 'execute_kw',
        args: [
            DB, uid, PASSWORD,
            'library.book', 'search_read',
            [[['active', '=', true]]],
            { fields: ['name', 'author'], limit: 10 },
        ],
    });

    books.forEach(book => console.log(`${book.id}: ${book.name}`));
}

main();
```

---

## Custom REST API Endpoint

Odoo tidak punya REST API bawaan, jadi kalau mau gaya REST, buat endpoint sendiri di module Odoo dengan `http.Controller`.

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
        """Simple token-based authentication."""
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
                methods=['GET'], csrf=False, cors='*')
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

        books = request.env['library.book'].with_user(user).search_read(
            domain,
            ['name', 'author', 'isbn', 'available_copies', 'category_id'],
            limit=limit,
            offset=offset,
            order='name ASC',
        )
        total = request.env['library.book'].with_user(user).search_count(domain)

        return self._json_response({
            'data': books,
            'total': total,
            'limit': limit,
            'offset': offset,
        })

    # GET /api/v1/books/:id
    @http.route('/api/v1/books/<int:book_id>', type='http', auth='none',
                methods=['GET'], csrf=False, cors='*')
    def get_book(self, book_id, **kwargs):
        user = self._authenticate()
        if not user:
            return self._json_response({'error': 'Unauthorized'}, 401)

        book = request.env['library.book'].with_user(user).browse(book_id)
        if not book.exists():
            return self._json_response({'error': 'Not found'}, 404)

        return self._json_response({
            'data': {
                'id': book.id,
                'name': book.name,
                'author': book.author,
                'isbn': book.isbn,
                'category': book.category_id.name,
                'available_copies': book.available_copies,
                'total_copies': book.total_copies,
            }
        })

    # POST /api/v1/books
    @http.route('/api/v1/books', type='http', auth='none',
                methods=['POST'], csrf=False, cors='*')
    def create_book(self, **kwargs):
        user = self._authenticate()
        if not user:
            return self._json_response({'error': 'Unauthorized'}, 401)

        try:
            data = json.loads(request.httprequest.data)
        except json.JSONDecodeError:
            return self._json_response({'error': 'Invalid JSON'}, 400)

        required = ['name', 'category_id']
        missing = [f for f in required if f not in data]
        if missing:
            return self._json_response(
                {'error': f'Missing fields: {", ".join(missing)}'}, 400
            )

        try:
            book = request.env['library.book'].with_user(user).create(data)
            return self._json_response({'data': {'id': book.id}}, 201)
        except Exception as e:
            return self._json_response({'error': str(e)}, 400)

    # PUT /api/v1/books/:id
    @http.route('/api/v1/books/<int:book_id>', type='http', auth='none',
                methods=['PUT'], csrf=False, cors='*')
    def update_book(self, book_id, **kwargs):
        user = self._authenticate()
        if not user:
            return self._json_response({'error': 'Unauthorized'}, 401)

        book = request.env['library.book'].with_user(user).browse(book_id)
        if not book.exists():
            return self._json_response({'error': 'Not found'}, 404)

        try:
            data = json.loads(request.httprequest.data)
            book.write(data)
            return self._json_response({'data': {'id': book.id}})
        except Exception as e:
            return self._json_response({'error': str(e)}, 400)

    # DELETE /api/v1/books/:id
    @http.route('/api/v1/books/<int:book_id>', type='http', auth='none',
                methods=['DELETE'], csrf=False, cors='*')
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

### Menggunakan REST API

```bash
# Get all books
curl -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:8069/api/v1/books?limit=10

# Get single book
curl -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:8069/api/v1/books/1

# Create book
curl -X POST \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"name": "New Book", "author": "Author", "category_id": 1}' \
     http://localhost:8069/api/v1/books

# Update book
curl -X PUT \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"author": "Updated Author"}' \
     http://localhost:8069/api/v1/books/1

# Delete book
curl -X DELETE \
     -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:8069/api/v1/books/1
```

---

## Python Helper Class (Reusable Client)

```python
"""
odoo_client.py — Reusable Odoo XML-RPC client.
"""
import xmlrpc.client

class OdooClient:
    def __init__(self, url, db, username, password):
        self.url = url
        self.db = db
        self.password = password
        self.common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        self.models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
        self.uid = self.common.authenticate(db, username, password, {})
        if not self.uid:
            raise Exception('Authentication failed')

    def execute(self, model, method, *args, **kwargs):
        return self.models.execute_kw(
            self.db, self.uid, self.password,
            model, method, list(args), kwargs
        )

    def search(self, model, domain, **kwargs):
        return self.execute(model, 'search', domain, **kwargs)

    def read(self, model, ids, fields=None):
        return self.execute(model, 'read', ids, fields=fields or [])

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


# Penggunaan:
client = OdooClient('http://localhost:8069', 'odoo', 'admin', 'admin')

# Search
books = client.search_read('library.book', [('active', '=', True)],
                           fields=['name', 'author'], limit=10)

# Create
book_id = client.create('library.book', {
    'name': 'API Book',
    'category_id': 1,
})

# Update
client.write('library.book', [book_id], {'author': 'New Author'})

# Delete
client.unlink('library.book', [book_id])
```

---

## Tips External API

1. **Gunakan `search_read`** bukan `search` + `read` terpisah — lebih efisien (1 call vs 2)
2. **Selalu specify `fields`** — jangan baca semua field jika hanya butuh beberapa
3. **Gunakan `limit` dan `offset`** — hindari membaca semua record sekaligus
4. **Handle timeout** — set timeout di xmlrpc client untuk koneksi lambat
5. **API user terpisah** — buat user khusus untuk API, jangan pakai admin
6. **Rate limiting** — implementasikan di reverse proxy (Nginx) untuk mencegah abuse
7. **HTTPS wajib** di production — credentials dikirim setiap request
