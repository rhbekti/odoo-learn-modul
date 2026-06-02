# Bab 6: Controllers & Routing

## Dasar Controller

Controller handle HTTP requests dan return response.

```python
from odoo import http
from odoo.http import request, route

class LibraryController(http.Controller):

    @http.route('/library/books', type='http', auth='public', website=True)
    def list_books(self):
        books = request.env['library.book'].search([])
        return request.render('library_app.book_list', {
            'books': books,
        })

    @http.route('/library/book/<int:book_id>', type='http', auth='public', website=True)
    def detail_book(self, book_id):
        book = request.env['library.book'].browse(book_id)
        return request.render('library_app.book_detail', {
            'book': book,
        })
```

## Routing Decorator

```python
@http.route(
    '/path/to/page',           # URL path
    type='http',               # 'http' atau 'json'
    auth='public',             # 'public', 'user', 'none'
    website=True,              # Enable website features
    sitemap=True,              # Include in sitemap
    multilang=True,            # Multi-language support
    methods=['GET', 'POST'],   # Allowed HTTP methods
    csrf=True,                 # CSRF protection
)
```

**auth types:**

| Type | Fungsi |
|------|--------|
| `public` | Semua orang bisa akses |
| `user` | Harus login |
| `none` | Tidak ada auth check |

## HTTP Response Types

### Render Template

```python
@http.route('/library/books', type='http', auth='public', website=True)
def list_books(self):
    books = request.env['library.book'].search([])
    return request.render('library_app.book_list', {
        'books': books,
        'page_title': 'Book List',
    })
```

### JSON Response

```python
@http.route('/library/api/books', type='json', auth='user')
    def get_books(self):
        books = request.env['library.book'].search_read([], ['name', 'author', 'price'])
        return books
```

### Redirect

```python
@http.route('/library/redirect', type='http', auth='public', website=True)
def redirect_page(self):
    return http.redirect('/library/books')
```

### File Download

```python
@http.route('/library/report/<int:report_id>', type='http', auth='user')
def download_report(self, report_id):
    report = request.env['library.report'].browse(report_id)
    content = report.get_pdf()
    return request.make_response(
        content,
        headers=[
            ('Content-Type', 'application/pdf'),
            ('Content-Disposition', f'attachment; filename={report.name}.pdf'),
        ]
    )
```

### Error Response

```python
from odoo.exceptions import AccessError, ValidationError

@http.route('/library/error', type='http', auth='user')
def trigger_error(self):
    raise ValidationError('Something went wrong!')

@http.route('/library/403', type='http', auth='public')
def forbidden(self):
    return request.render('website.403')
```

## QWeb Templates

### Template Dasar

```xml
<template id="book_list" name="Book List">
    <t t-call="website.layout">
        <div class="container">
            <h1>Library Books</h1>
            <div class="row">
                <t t-foreach="books" t-as="book">
                    <div class="col-md-4">
                        <div class="card">
                            <div class="card-body">
                                <h5 t-esc="book.name"/>
                                <p t-esc="book.author"/>
                                <span t-esc="book.price" t-options="{'widget': 'monetary'}"/>
                            </div>
                        </div>
                    </div>
                </t>
            </div>
        </div>
    </t>
</template>
```

### Template dengan Form

```xml
<template id="book_form" name="Add Book">
    <t t-call="website.layout">
        <div class="container">
            <h1>Add New Book</h1>
            <form action="/library/book/submit" method="POST">
                <input type="hidden" name="csrf_token" t-att-value="request.csrf_token()"/>
                <div class="form-group">
                    <label>Title</label>
                    <input type="text" name="name" class="form-control" required="1"/>
                </div>
                <div class="form-group">
                    <label>Author</label>
                    <input type="text" name="author" class="form-control"/>
                </div>
                <div class="form-group">
                    <label>Price</label>
                    <input type="number" name="price" class="form-control"/>
                </div>
                <button type="submit" class="btn btn-primary">Submit</button>
            </form>
        </div>
    </t>
</template>
```

## Request Handling

```python
@http.route('/library/submit', type='http', auth='public', website=True)
    methods=['POST'])
def submit_form(self, **post):
    name = post.get('name')
    author = post.get('author')
    price = float(post.get('price', 0))
    
    # Create record
    book = request.env['library.book'].create({
        'name': name,
        'author': author,
        'price': price,
    })
    
    return request.render('library_app.submitted', {
        'book': book,
    })
```

## JSON Controllers (API)

```python
class LibraryAPI(http.Controller):

    @http.route('/library/api/v1/books', type='json', auth='user', methods=['GET'])
    def get_books(self, limit=20, offset=0, **kwargs):
        domain = kwargs.get('domain', [])
        fields = ['id', 'name', 'author', 'price', 'state']
        books = request.env['library.book'].search_read(
            domain, fields, offset=offset, limit=limit
        )
        return {
            'status': 'success',
            'data': books,
            'count': len(books),
        }

    @http.route('/library/api/v1/books', type='json', auth='user', methods=['POST'])
    def create_book(self, **kwargs):
        try:
            book = request.env['library.book'].create(kwargs)
            return {
                'status': 'success',
                'id': book.id,
            }
        except Exception as e:
            return {
                'status': 'error',
                'message': str(e),
            }

    @http.route('/library/api/v1/books/<int:book_id>', type='json', auth='user', methods=['PUT'])
    def update_book(self, book_id, **kwargs):
        book = request.env['library.book'].browse(book_id)
        book.write(kwargs)
        return {'status': 'success'}

    @http.route('/library/api/v1/books/<int:book_id>', type='json', auth='user', methods=['DELETE'])
    def delete_book(self, book_id):
        book = request.env['library.book'].browse(book_id)
        book.unlink()
        return {'status': 'success'}
```

## Helper Methods

```python
class LibraryController(http.Controller):

    def _prepare_navbar_values(self):
        return {
            'library_count': request.env['library.book'].search_count([]),
        }

    @http.route('/library/books', type='http', auth='public', website=True)
    def list_books(self, **kwargs):
        values = self._prepare_navbar_values()
        values['books'] = request.env['library.book'].search([])
        return request.render('library_app.book_list', values)
```

## Register Routes

```xml
<!-- views/templates.xml -->
<odoo>
    <data>
        <template id="book_list"/>
        <template id="book_detail"/>
    </data>
</odoo>
```

## Static Files

```
static/
├── js/
│   └── main.js
├── css/
│   └── style.css
└── images/
    └── logo.png
```

Include dalam template:

```xml
<template id="my_template" name="My Template">
    <t t-call="website.layout">
        <t t-call-assets="library_app.my_assets" reload="1"/>
        <div class="content">
            <!-- content -->
        </div>
    </t>
</template>

<template id="my_assets" name="My Assets">
    <link rel="stylesheet" href="/library_app/static/css/style.css"/>
    <script type="text/javascript" src="/library_app/static/js/main.js"/>
</template>
```