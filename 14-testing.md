# Bab 14: Testing

Odoo menyediakan framework testing bawaan yang terintegrasi dengan unittest Python.

## Jenis Test di Odoo

| Jenis | Base Class | Fungsi |
|-------|-----------|--------|
| `TransactionCase` | Setiap test di-rollback | Test CRUD, logic, tanpa commit |
| `SingleTransactionCase` | Semua test 1 transaksi | Test yang butuh data dari test sebelumnya |
| `SavepointCase` | Savepoint per test | Lebih cepat dari TransactionCase |
| `HttpCase` | Test HTTP/browser | Test controller, UI, tour |
| `Form` (test utility) | Simulasi form | Test onchange, computed tanpa browser |

---

## Struktur Test

```
library_management/
├── tests/
│   ├── __init__.py
│   ├── common.py           # Setup data bersama
│   ├── test_book.py
│   ├── test_loan.py
│   ├── test_member.py
│   └── test_controller.py
```

### tests/__init__.py

```python
from . import test_book
from . import test_loan
from . import test_member
```

---

## Common Test Setup

```python
# tests/common.py
from odoo.tests.common import TransactionCase

class LibraryTestCommon(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        # Buat data test yang dipakai bersama
        cls.category = cls.env['library.book.category'].create({
            'name': 'Test Category',
        })

        cls.book = cls.env['library.book'].create({
            'name': 'Test Book',
            'author': 'Test Author',
            'isbn': '978-0-00-000000-0',
            'category_id': cls.category.id,
        })

        cls.book_copy = cls.env['library.book.copy'].create({
            'barcode': 'TEST-001',
            'book_id': cls.book.id,
            'state': 'available',
        })

        cls.member = cls.env['library.member'].create({
            'name': 'Test Member',
            'email': 'test@example.com',
            'membership_type': 'regular',
        })
```

---

## Test Model: CRUD & Logic

```python
# tests/test_book.py
from odoo.tests.common import TransactionCase
from odoo.exceptions import ValidationError, UserError

class TestLibraryBook(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.category = cls.env['library.book.category'].create({
            'name': 'Fiction',
        })

    def test_create_book(self):
        """Test creating a book with required fields."""
        book = self.env['library.book'].create({
            'name': 'New Book',
            'author': 'Author',
            'category_id': self.category.id,
        })
        self.assertTrue(book.id)
        self.assertEqual(book.name, 'New Book')
        self.assertTrue(book.active)

    def test_create_book_without_name_fails(self):
        """Test that creating a book without name raises error."""
        with self.assertRaises(Exception):
            self.env['library.book'].create({
                'category_id': self.category.id,
            })

    def test_isbn_unique_constraint(self):
        """Test that duplicate ISBN raises error."""
        self.env['library.book'].create({
            'name': 'Book 1',
            'isbn': '978-1-111-11111-1',
            'category_id': self.category.id,
        })
        with self.assertRaises(Exception):
            self.env['library.book'].create({
                'name': 'Book 2',
                'isbn': '978-1-111-11111-1',
                'category_id': self.category.id,
            })

    def test_computed_copy_stats(self):
        """Test that total_copies and available_copies are computed correctly."""
        book = self.env['library.book'].create({
            'name': 'Book With Copies',
            'category_id': self.category.id,
        })
        self.assertEqual(book.total_copies, 0)
        self.assertEqual(book.available_copies, 0)

        # Tambah 2 copy
        self.env['library.book.copy'].create({
            'barcode': 'C001',
            'book_id': book.id,
            'state': 'available',
        })
        self.env['library.book.copy'].create({
            'barcode': 'C002',
            'book_id': book.id,
            'state': 'borrowed',
        })

        book.invalidate_recordset()
        self.assertEqual(book.total_copies, 2)
        self.assertEqual(book.available_copies, 1)

    def test_name_get(self):
        """Test display name includes author."""
        book = self.env['library.book'].create({
            'name': 'The Title',
            'author': 'The Author',
            'category_id': self.category.id,
        })
        display_name = book.name_get()[0][1]
        self.assertIn('The Author', display_name)
```

---

## Test Loan (Workflow & Business Logic)

```python
# tests/test_loan.py
from odoo.exceptions import UserError, ValidationError
from .common import LibraryTestCommon

class TestLibraryLoan(LibraryTestCommon):

    def _create_loan(self, **kwargs):
        """Helper: buat loan dengan defaults."""
        vals = {
            'member_id': self.member.id,
            'loan_date': '2026-05-01',
            'due_date': '2026-05-15',
            'line_ids': [(0, 0, {
                'copy_id': self.book_copy.id,
            })],
        }
        vals.update(kwargs)
        return self.env['library.loan'].create(vals)

    def test_loan_sequence(self):
        """Test that loan gets auto sequence number."""
        loan = self._create_loan()
        self.assertNotEqual(loan.name, 'New')
        self.assertTrue(loan.name.startswith('LOAN/'))

    def test_loan_confirm(self):
        """Test confirming a loan changes state and book copy state."""
        loan = self._create_loan()
        self.assertEqual(loan.state, 'draft')
        self.assertEqual(self.book_copy.state, 'available')

        loan.action_confirm()

        self.assertEqual(loan.state, 'active')
        self.assertEqual(self.book_copy.state, 'borrowed')

    def test_loan_confirm_without_lines_fails(self):
        """Test that confirming empty loan raises error."""
        loan = self.env['library.loan'].create({
            'member_id': self.member.id,
            'loan_date': '2026-05-01',
            'due_date': '2026-05-15',
        })
        with self.assertRaises(UserError):
            loan.action_confirm()

    def test_loan_return(self):
        """Test returning books updates states."""
        loan = self._create_loan()
        loan.action_confirm()

        loan.action_return()

        self.assertEqual(loan.state, 'returned')
        self.assertTrue(loan.return_date)
        self.assertEqual(self.book_copy.state, 'available')

    def test_loan_cancel(self):
        """Test cancelling loan releases books."""
        loan = self._create_loan()
        loan.action_confirm()
        self.assertEqual(self.book_copy.state, 'borrowed')

        loan.action_cancel()

        self.assertEqual(loan.state, 'cancel')
        self.assertEqual(self.book_copy.state, 'available')

    def test_date_constraint(self):
        """Test that due_date before loan_date raises error."""
        with self.assertRaises(ValidationError):
            self._create_loan(
                loan_date='2026-05-15',
                due_date='2026-05-01',
            )

    def test_max_books_exceeded(self):
        """Test that member cannot exceed max book limit."""
        # Member regular: max 5 books
        copies = []
        for i in range(6):
            copies.append(self.env['library.book.copy'].create({
                'barcode': f'MAX-{i:03d}',
                'book_id': self.book.id,
                'state': 'available',
            }))

        # Buat 5 loan aktif (satu per loan)
        for i in range(5):
            loan = self.env['library.loan'].create({
                'member_id': self.member.id,
                'loan_date': '2026-05-01',
                'due_date': '2026-05-15',
                'line_ids': [(0, 0, {'copy_id': copies[i].id})],
            })
            loan.action_confirm()

        # Loan ke-6 harus gagal
        loan_6 = self.env['library.loan'].create({
            'member_id': self.member.id,
            'loan_date': '2026-05-01',
            'due_date': '2026-05-15',
            'line_ids': [(0, 0, {'copy_id': copies[5].id})],
        })
        with self.assertRaises(UserError):
            loan_6.action_confirm()
```

---

## Test dengan Form Simulation

Simulasi interaksi user di form view (onchange, computed fields) tanpa browser.

```python
from odoo.tests.common import Form
from .common import LibraryTestCommon

class TestLoanForm(LibraryTestCommon):

    def test_onchange_member_sets_due_date(self):
        """Test that selecting member auto-fills due date."""
        loan_form = Form(self.env['library.loan'])
        loan_form.member_id = self.member

        # onchange harus auto-set due_date
        self.assertTrue(loan_form.due_date)

    def test_onchange_loan_date_updates_due_date(self):
        """Test that changing loan_date updates due_date."""
        from datetime import date
        loan_form = Form(self.env['library.loan'])
        loan_form.member_id = self.member
        loan_form.loan_date = date(2026, 6, 1)

        # due_date harus 14 hari setelah loan_date
        self.assertEqual(loan_form.due_date, date(2026, 6, 15))

    def test_add_line_via_form(self):
        """Test adding loan lines through form."""
        loan_form = Form(self.env['library.loan'])
        loan_form.member_id = self.member
        loan_form.due_date = '2026-05-15'

        with loan_form.line_ids.new() as line:
            line.copy_id = self.book_copy

        loan = loan_form.save()
        self.assertEqual(len(loan.line_ids), 1)
        self.assertEqual(loan.line_ids.copy_id, self.book_copy)
```

---

## Test dengan User Berbeda (Access Rights)

```python
from odoo.tests.common import TransactionCase
from odoo.exceptions import AccessError

class TestLibrarySecurity(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.category = cls.env['library.book.category'].create({
            'name': 'Test',
        })

        # Buat user dengan group tertentu
        cls.user_librarian = cls.env['res.users'].create({
            'name': 'Librarian User',
            'login': 'librarian',
            'groups_id': [(6, 0, [
                cls.env.ref('library_management.group_library_user').id,
            ])],
        })
        cls.user_manager = cls.env['res.users'].create({
            'name': 'Library Manager',
            'login': 'lib_manager',
            'groups_id': [(6, 0, [
                cls.env.ref('library_management.group_library_manager').id,
            ])],
        })

    def test_user_cannot_delete_book(self):
        """Test that regular user cannot delete books."""
        book = self.env['library.book'].create({
            'name': 'Test',
            'category_id': self.category.id,
        })
        # Switch ke user biasa
        book_as_user = book.with_user(self.user_librarian)
        with self.assertRaises(AccessError):
            book_as_user.unlink()

    def test_manager_can_delete_book(self):
        """Test that manager can delete books."""
        book = self.env['library.book'].create({
            'name': 'Test',
            'category_id': self.category.id,
        })
        book_as_manager = book.with_user(self.user_manager)
        book_as_manager.unlink()
        self.assertFalse(book.exists())
```

---

## Test HTTP Controller

```python
# tests/test_controller.py
from odoo.tests.common import HttpCase

class TestLibraryController(HttpCase):

    def test_book_list_page(self):
        """Test that book list page returns 200."""
        response = self.url_open('/library/books')
        self.assertEqual(response.status_code, 200)

    def test_book_list_requires_no_auth(self):
        """Test that public users can access book list."""
        self.authenticate(None, None)  # Logout
        response = self.url_open('/library/books')
        self.assertEqual(response.status_code, 200)

    def test_api_requires_auth(self):
        """Test that API endpoint requires authentication."""
        self.authenticate(None, None)  # Logout
        response = self.url_open('/library/api/v1/books', data='{}',
                                  headers={'Content-Type': 'application/json'})
        self.assertNotEqual(response.status_code, 200)
```

---

## Test Tour (Browser UI Test)

```javascript
// static/tests/tour_test.js
/** @odoo-module **/

import { registry } from "@web/core/registry";

registry.category("web_tour.tours").add("library_create_book", {
    test: true,
    url: "/odoo/action-library_management.action_library_book",
    steps: () => [
        {
            trigger: ".o_list_button_add",
            content: "Click Create button",
            run: "click",
        },
        {
            trigger: "div[name='name'] input",
            content: "Enter book title",
            run: "edit Test Book From Tour",
        },
        {
            trigger: "div[name='author'] input",
            content: "Enter author",
            run: "edit Tour Author",
        },
        {
            trigger: "div[name='category_id'] input",
            content: "Select category",
            run: "edit Fiction",
        },
        {
            trigger: ".ui-autocomplete .ui-menu-item:first-child a",
            content: "Pick category from dropdown",
            run: "click",
        },
        {
            trigger: ".o_form_button_save",
            content: "Save the book",
            run: "click",
        },
        {
            trigger: ".o_form_view",
            content: "Verify we are on form view",
        },
    ],
});
```

Panggil tour dari Python test:

```python
class TestLibraryTour(HttpCase):

    def test_create_book_tour(self):
        self.start_tour("/odoo", "library_create_book", login="admin")
```

---

## Menjalankan Test

```bash
# Jalankan semua test dari module
docker compose exec odoo odoo --test-enable -d odoo -u library_management --stop-after-init

# Jalankan test file tertentu
docker compose exec odoo odoo --test-enable --test-tags /library_management -d odoo --stop-after-init

# Jalankan test class tertentu
docker compose exec odoo odoo --test-enable --test-tags library_management.TestLibraryBook -d odoo --stop-after-init

# Jalankan dengan log level debug (lihat detail)
docker compose exec odoo odoo --test-enable --log-level=test -d odoo -u library_management --stop-after-init
```

### Test Tags

```python
from odoo.tests import tagged

@tagged('post_install', '-at_install')
class TestAfterInstall(TransactionCase):
    """Test ini jalan setelah semua module ter-install."""
    pass

@tagged('at_install')
class TestAtInstall(TransactionCase):
    """Test ini jalan saat module di-install (default)."""
    pass
```

---

## Tips Testing

1. **`invalidate_recordset()`** — panggil setelah mengubah data yang mempengaruhi computed field stored, supaya cache ter-refresh
2. **`with_user(user)`** — test sebagai user berbeda untuk cek access rights
3. **`Form()` utility** — simulasi UI interaction tanpa browser, jauh lebih cepat dari HttpCase
4. **`setUpClass` vs `setUp`** — `setUpClass` dipanggil sekali per class, `setUp` dipanggil tiap method. Pakai `setUpClass` untuk data yang tidak berubah
5. **`assertRaises`** — selalu test error case, bukan hanya happy path
6. **Test harus independent** — jangan bergantung pada urutan eksekusi test
