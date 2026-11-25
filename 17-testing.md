# Bab 17: Testing

> **Tahap:** 5 Profesional | **Prasyarat:** Bab 4, 6, 10 (modul `library_management`), Bab 12 (untuk test controller) | **Estimasi:** ± 3,5 jam | **Versi:** Odoo 18 (catatan Odoo 19)

Odoo menyediakan framework testing bawaan yang terintegrasi dengan `unittest` Python. Di bab ini kita menulis test untuk modul `library_management` dari Bab 10.

## Tujuan Belajar

- Memilih base class test yang tepat (`TransactionCase`, `SingleTransactionCase`, `HttpCase`) dan memakai utility `Form`
- Menyusun folder `tests/` dan meregistrasikannya lewat `tests/__init__.py`
- Menulis test untuk logic model, workflow, constraint, dan access rights
- Menjalankan test (semua, per modul, per class, per method) dari command line dan Docker
- Memakai `@tagged` untuk mengatur kapan test dijalankan
- Membekukan waktu dengan `freeze_time` agar test berbasis tanggal (denda keterlambatan) tidak rapuh, dan memakai `self.patch` untuk mengganti panggilan eksternal
- Menyusun pipeline CI (contoh GitHub Actions) yang menjalankan test module di image `odoo:18.0` + PostgreSQL

---

## 1. Jenis Test di Odoo

| Jenis | Base Class | Fungsi |
|-------|-----------|--------|
| `TransactionCase` | Setiap method test di-rollback | Test CRUD dan logic. Pilihan default |
| `SingleTransactionCase` | Semua test dalam 1 transaksi | Test yang butuh data dari test sebelumnya (urutan penting, jarang dipakai) |
| `HttpCase` | Test HTTP/browser | Test controller, UI, tour |
| `Form` (utility) | Simulasi form view | Test onchange dan computed field tanpa browser |

Semua bisa di-import dari `odoo.tests`:

```python
from odoo.tests import TransactionCase, SingleTransactionCase, HttpCase, Form, tagged
```

> `SavepointCase` yang mungkin kamu temukan di tutorial lama sudah dihapus. `TransactionCase` modern sudah memakai savepoint sehingga `setUpClass` aman dipakai untuk data bersama.

---

## 2. Struktur Test dan Registrasi

```
library_management/
├── tests/
│   ├── __init__.py
│   ├── common.py           # Setup data bersama
│   ├── test_book.py
│   ├── test_loan.py
│   ├── test_loan_form.py
│   ├── test_security.py
│   └── test_controller.py
```

### tests/__init__.py

```python
from . import test_book
from . import test_loan
from . import test_loan_form
from . import test_security
from . import test_controller
```

Aturan penting:
- Nama file test harus diawali `test_`, dan **setiap file harus di-import** di `tests/__init__.py`. Kalau lupa, test tidak akan pernah jalan dan tidak ada error.
- `common.py` tidak perlu di-import di sini karena sudah ter-import oleh file test yang memakainya.
- Folder `tests/` tidak perlu (dan sebaiknya tidak) dimasukkan ke `'data'` di manifest.

---

## 3. Menjalankan Test

Test hanya jalan jika `--test-enable` aktif (otomatis aktif bila memakai `--test-tags`), dan hanya untuk module yang ter-install.

```bash
# Install modul sekaligus jalankan test-nya (database test terpisah)
docker compose exec odoo odoo --test-enable -d odoo_test -i library_management --stop-after-init

# Update modul (setelah mengubah kode) dan jalankan test-nya
docker compose exec odoo odoo --test-enable -d odoo_test -u library_management --stop-after-init

# Jalankan semua test milik satu modul
docker compose exec odoo odoo --test-tags /library_management -d odoo_test -u library_management --stop-after-init

# Satu class
docker compose exec odoo odoo --test-tags /library_management:TestLibraryBook -d odoo_test -u library_management --stop-after-init

# Satu method
docker compose exec odoo odoo --test-tags /library_management:TestLibraryBook.test_create_book -d odoo_test -u library_management --stop-after-init

# Lihat log detail test
docker compose exec odoo odoo --test-enable --log-level=test -d odoo_test -u library_management --stop-after-init
```

Penjelasan:
- Format `--test-tags`: `[-][tag][/module][:class][.method]`. Beberapa nilai dipisah koma, awalan `-` berarti "kecualikan".
- `-i` dipakai saat pertama kali install, `-u` saat upgrade. Test `at_install` (default) hanya berjalan saat modul sedang di-install/di-update.
- Pakai database terpisah (`odoo_test`) supaya data development tidak tercampur.
- `--stop-after-init` membuat proses berhenti setelah test selesai.
- Di instalasi dari source, ganti `odoo` dengan `./odoo-bin`. Di image Docker resmi, perintah `odoo` sudah tersedia.
- Jika `HttpCase` gagal karena port 8069 sudah dipakai server yang sedang berjalan, tambahkan `--http-port=8070`.

### Test Tags

```python
from odoo.tests import TransactionCase, tagged

@tagged('post_install', '-at_install')
class TestAfterInstall(TransactionCase):
    """Jalan setelah SEMUA module ter-install. Cocok untuk HttpCase."""

@tagged('at_install')
class TestAtInstall(TransactionCase):
    """Jalan tepat setelah module ini ter-install (perilaku default)."""
```

- Test tanpa `@tagged` otomatis bertag `standard` dan `at_install`.
- `@tagged` adalah decorator **class**, tidak berpengaruh pada method.
- Tag buatan sendiri (misal `@tagged('library_slow')`) bisa dipilih lewat `--test-tags library_slow`.

---

## 4. Common Test Setup

```python
# tests/common.py
from odoo.tests import TransactionCase

class LibraryTestCommon(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        # Data test yang dipakai bersama
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

## 5. Test Model: CRUD dan Logic

```python
# tests/test_book.py
from psycopg2 import IntegrityError

from odoo.tests import TransactionCase
from odoo.tools import mute_logger

class TestLibraryBook(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.category = cls.env['library.book.category'].create({
            'name': 'Fiction',
        })

    def test_create_book(self):
        """Buku bisa dibuat dengan field wajib."""
        book = self.env['library.book'].create({
            'name': 'New Book',
            'author': 'Author',
            'category_id': self.category.id,
        })
        self.assertTrue(book.id)
        self.assertEqual(book.name, 'New Book')
        self.assertTrue(book.active)

    @mute_logger('odoo.sql_db')
    def test_create_book_without_name_fails(self):
        """Membuat buku tanpa judul harus gagal (NOT NULL di database)."""
        with self.assertRaises(IntegrityError):
            self.env['library.book'].create({
                'category_id': self.category.id,
            })

    @mute_logger('odoo.sql_db')
    def test_isbn_unique_constraint(self):
        """ISBN ganda harus ditolak oleh constraint unik."""
        self.env['library.book'].create({
            'name': 'Book 1',
            'isbn': '978-1-111-11111-1',
            'category_id': self.category.id,
        })
        with self.assertRaises(IntegrityError):
            self.env['library.book'].create({
                'name': 'Book 2',
                'isbn': '978-1-111-11111-1',
                'category_id': self.category.id,
            })

    def test_computed_copy_stats(self):
        """total_copies dan available_copies dihitung benar."""
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

        self.assertEqual(book.total_copies, 2)
        self.assertEqual(book.available_copies, 1)

    def test_display_name(self):
        """display_name memuat nama penulis (lihat _compute_display_name, Bab 10)."""
        book = self.env['library.book'].create({
            'name': 'The Title',
            'author': 'The Author',
            'category_id': self.category.id,
        })
        self.assertIn('The Author', book.display_name)
```

Catatan:
- `assertRaises` milik Odoo otomatis membungkus blok `with` dalam savepoint, jadi error database (`IntegrityError`) tidak merusak transaksi test berikutnya.
- `mute_logger('odoo.sql_db')` hanya membungkam log error yang memang kita harapkan, supaya output test bersih.
- Test `display_name` menggantikan `name_get()` yang sudah deprecated sejak Odoo 17.
- `invalidate_recordset()` biasanya tidak perlu untuk field stored yang punya `@api.depends` yang benar. Pakai hanya jika kamu mengubah data lewat SQL langsung atau test gagal karena cache basi.

---

## 6. Test Loan: Workflow dan Business Logic

```python
# tests/test_loan.py
from odoo.exceptions import UserError, ValidationError
from .common import LibraryTestCommon

class TestLibraryLoan(LibraryTestCommon):

    def _create_loan(self, **kwargs):
        """Helper: buat loan dengan nilai default."""
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
        """Loan mendapat nomor urut otomatis."""
        loan = self._create_loan()
        self.assertNotEqual(loan.name, 'New')
        self.assertTrue(loan.name.startswith('LOAN/'))

    def test_loan_confirm(self):
        """Konfirmasi loan mengubah state loan dan state copy."""
        loan = self._create_loan()
        self.assertEqual(loan.state, 'draft')
        self.assertEqual(self.book_copy.state, 'available')

        loan.action_confirm()

        self.assertEqual(loan.state, 'active')
        self.assertEqual(self.book_copy.state, 'borrowed')

    def test_loan_confirm_without_lines_fails(self):
        """Konfirmasi loan kosong harus ditolak."""
        loan = self.env['library.loan'].create({
            'member_id': self.member.id,
            'loan_date': '2026-05-01',
            'due_date': '2026-05-15',
        })
        with self.assertRaises(UserError):
            loan.action_confirm()

    def test_loan_return(self):
        """Pengembalian buku memperbarui state."""
        loan = self._create_loan()
        loan.action_confirm()

        loan.action_return()

        self.assertEqual(loan.state, 'returned')
        self.assertTrue(loan.return_date)
        self.assertEqual(self.book_copy.state, 'available')
        # Catatan: due_date 2026-05-15 sudah lewat, jadi return ini
        # juga membuat record denda (library.fine). Lihat Latihan 2.

    def test_loan_cancel(self):
        """Pembatalan loan membebaskan buku."""
        loan = self._create_loan()
        loan.action_confirm()
        self.assertEqual(self.book_copy.state, 'borrowed')

        loan.action_cancel()

        self.assertEqual(loan.state, 'cancel')
        self.assertEqual(self.book_copy.state, 'available')

    def test_date_constraint(self):
        """due_date sebelum loan_date harus ditolak."""
        with self.assertRaises(ValidationError):
            self._create_loan(
                loan_date='2026-05-15',
                due_date='2026-05-01',
            )

    def test_max_books_exceeded(self):
        """Member tidak boleh melebihi batas buku (regular: 5)."""
        copies = []
        for i in range(6):
            copies.append(self.env['library.book.copy'].create({
                'barcode': f'MAX-{i:03d}',
                'book_id': self.book.id,
                'state': 'available',
            }))

        # 5 loan aktif (satu buku per loan)
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

## 7. Test dengan `Form` (Simulasi UI)

`Form` meniru interaksi user di form view (termasuk onchange dan field computed) tanpa browser, jauh lebih cepat dari `HttpCase`. Field yang kamu set harus ada di form view modelnya.

```python
# tests/test_loan_form.py
from datetime import date

from odoo.tests import Form
from .common import LibraryTestCommon

class TestLoanForm(LibraryTestCommon):

    def test_onchange_member_sets_due_date(self):
        """Memilih member mengisi due_date otomatis."""
        loan_form = Form(self.env['library.loan'])
        loan_form.member_id = self.member

        self.assertTrue(loan_form.due_date)

    def test_onchange_loan_date_updates_due_date(self):
        """Mengubah loan_date memperbarui due_date (+14 hari)."""
        loan_form = Form(self.env['library.loan'])
        loan_form.member_id = self.member
        loan_form.loan_date = date(2026, 6, 1)

        self.assertEqual(loan_form.due_date, date(2026, 6, 15))

    def test_add_line_via_form(self):
        """Menambah baris loan lewat form."""
        loan_form = Form(self.env['library.loan'])
        loan_form.member_id = self.member

        with loan_form.line_ids.new() as line:
            line.copy_id = self.book_copy

        loan = loan_form.save()
        self.assertEqual(len(loan.line_ids), 1)
        self.assertEqual(loan.line_ids.copy_id, self.book_copy)
```

---

## 8. Test dengan User Berbeda (Access Rights)

Gunakan `with_user()` untuk menjalankan operasi sebagai user lain. Group berasal dari Bab 6/10.

```python
# tests/test_security.py
from odoo.exceptions import AccessError
from odoo.tests import TransactionCase

class TestLibrarySecurity(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.category = cls.env['library.book.category'].create({
            'name': 'Test',
        })

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
        # Odoo 19: field `groups_id` pada res.users berganti nama menjadi `group_ids`
        # (terverifikasi di kode sumber 19.0). Di Odoo 18 tetap `groups_id`.

    def test_user_cannot_delete_book(self):
        """User biasa tidak boleh menghapus buku."""
        book = self.env['library.book'].create({
            'name': 'Test',
            'category_id': self.category.id,
        })
        book_as_user = book.with_user(self.user_librarian)
        with self.assertRaises(AccessError):
            book_as_user.unlink()

    def test_manager_can_delete_book(self):
        """Manager boleh menghapus buku."""
        book = self.env['library.book'].create({
            'name': 'Test',
            'category_id': self.category.id,
        })
        book_as_manager = book.with_user(self.user_manager)
        book_as_manager.unlink()
        self.assertFalse(book.exists())
```

---

## 9. Test HTTP Controller

`HttpCase` menjalankan server HTTP sungguhan, jadi biasanya diberi tag `post_install`. Route `/library/books` dari Bab 12 memakai `website=True`, jadi modul `website` harus ada di `depends`.

```python
# tests/test_controller.py
from odoo.tests import HttpCase, tagged

@tagged('post_install', '-at_install')
class TestLibraryController(HttpCase):

    def test_book_list_page_public(self):
        """Halaman daftar buku bisa dibuka tanpa login (auth='public')."""
        response = self.url_open('/library/books')
        self.assertEqual(response.status_code, 200)

    def test_api_requires_auth(self):
        """Endpoint API (auth='user') tidak boleh sukses tanpa login."""
        response = self.url_open(
            '/library/api/v1/books',
            data='{}',
            headers={'Content-Type': 'application/json'},
        )
        # Route JSON bisa membalas HTTP 200 berisi objek "error",
        # atau status error; keduanya berarti akses ditolak.
        denied = response.status_code != 200 or 'error' in response.json()
        self.assertTrue(denied)
```

`url_open` tanpa login berjalan sebagai user publik. Untuk login sebagai user tertentu, panggil `self.authenticate('admin', 'admin')` sebelum `url_open`.

---

## 10. Test Tour (Browser UI Test)

Tour adalah skenario klik otomatis di browser. Tulis di JavaScript, lalu panggil dari Python lewat `start_tour`.

```javascript
// static/tests/tours/library_tour.js
/** @odoo-module **/

import { registry } from "@web/core/registry";

registry.category("web_tour.tours").add("library_create_book", {
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
            trigger: ".o-autocomplete--dropdown-item",
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

Daftarkan file JS di manifest, di bundle khusus test:

```python
# __manifest__.py
'assets': {
    'web.assets_tests': [
        'library_management/static/tests/tours/*.js',
    ],
},
```

Panggil dari Python (di `tests/test_tour.py`, jangan lupa import di `tests/__init__.py`):

```python
from odoo.tests import HttpCase, tagged

@tagged('post_install', '-at_install')
class TestLibraryTour(HttpCase):

    def test_create_book_tour(self):
        self.start_tour("/odoo", "library_create_book", login="admin")
```

Catatan: tour memerlukan data kategori "Fiction" sudah ada (misalnya dari seed data Bab 10); sesuaikan teks `edit` dan selector dengan data/UI modulmu. Selector UI bisa berubah antar versi, jadi cek di browser (developer mode) bila tour macet.

> **Beda di Odoo 19:** Bundle `web.assets_tests` dan sintaks `--test-tags` yang sama terdokumentasi di Odoo 18 maupun 19. Selector UI dan detail API tour sebaiknya diverifikasi ulang saat pindah versi.

---

## 11. Test Berbasis Tanggal: `freeze_time`

Logic `library_management` banyak bergantung pada "hari ini": `action_return` membandingkan `due_date` dengan `fields.Date.today()`, `_create_fine` menghitung `days_late`, dan `is_overdue` dihitung terhadap hari ini (Bab 10). Test yang memakai tanggal hard-coded dan mengandalkan jam sistem akan hasilnya berubah seiring waktu. Solusinya: bekukan waktu.

Terverifikasi di kode sumber Odoo 18 (`odoo/tests/common.py`): ada class `freeze_time` buatan Odoo yang membungkus paket `freezegun` (tercantum di `requirements.txt` 18.0). Karena `odoo/tests/__init__.py` melakukan `from .common import *`, kamu bisa mengimpornya dari `odoo.tests`. Ia bisa dipakai sebagai decorator method, decorator class, atau context manager.

```python
# tests/test_loan_fine.py
from odoo.tests import freeze_time
from .common import LibraryTestCommon


class TestLoanFine(LibraryTestCommon):

    def _create_active_loan(self, due_date):
        loan = self.env['library.loan'].create({
            'member_id': self.member.id,
            'loan_date': '2026-05-01',
            'due_date': due_date,
            'line_ids': [(0, 0, {'copy_id': self.book_copy.id})],
        })
        loan.action_confirm()
        return loan

    @freeze_time('2026-05-20')
    def test_late_return_creates_fine(self):
        """Terlambat 5 hari: due 15 Mei, dikembalikan 20 Mei (waktu dibekukan)."""
        loan = self._create_active_loan('2026-05-15')

        loan.action_return()

        fine = self.env['library.fine'].search([('loan_id', '=', loan.id)])
        self.assertEqual(len(fine), 1)
        self.assertEqual(fine.days_late, 5)
        self.assertEqual(fine.amount, 5000)   # Rp 1.000 per hari (Bab 10)
        self.assertEqual(str(loan.return_date), '2026-05-20')

    @freeze_time('2026-05-15')
    def test_return_on_due_date_has_no_fine(self):
        """Dikembalikan tepat di due_date: tidak ada denda."""
        loan = self._create_active_loan('2026-05-15')

        loan.action_return()

        self.assertFalse(self.env['library.fine'].search([('loan_id', '=', loan.id)]))

    def test_is_overdue_changes_with_time(self):
        """Context manager: bandingkan dua 'hari ini' dalam satu test."""
        loan = self._create_active_loan('2026-05-15')

        with freeze_time('2026-05-14'):
            loan.invalidate_recordset(['is_overdue'])
            self.assertFalse(loan.is_overdue)

        with freeze_time('2026-05-16'):
            loan.invalidate_recordset(['is_overdue'])
            self.assertTrue(loan.is_overdue)
```

Catatan:
- Angka `5000` mengikuti `_create_fine` di Bab 10 (`days_late * 1000`). Kalau tarif di modulmu berbeda, sesuaikan.
- `is_overdue` adalah computed field tanpa `store=True`, tetapi hasilnya tetap di-cache di environment. Itu sebabnya ada `invalidate_recordset(['is_overdue'])` setiap kali waktu berganti.
- Test lama di bab ini yang memakai tanggal hard-coded masa lalu (`2026-05-15`) tetap aman selama hanya mengandalkan fakta "tanggal itu sudah lewat". Yang rapuh adalah test yang menghitung selisih terhadap hari ini, seperti `days_late`.
- Decorator class juga didukung: kode sumber 18 menyimpan nilainya di atribut class `freeze_time` dan `TransactionCase.setUpClass` memulai pembekuan itu. Dengan begitu data di `setUpClass` pun dibuat dalam waktu beku.
- Pastikan `freezegun` terpasang di environment test. Jika tidak, kode 18 hanya mencatat warning `freezegun package missing` dan waktu tidak dibekukan.

> **Beda di Odoo 19:** `freeze_time` tetap ada di `odoo/tests/common.py` (terverifikasi di 19.0) dengan signature `freeze_time(time_to_freeze=None, tz_offset=0, tick=False, as_kwarg='', auto_tick_seconds=0)`. Kode 19 juga mengganti `freezegun.freeze_time` dengan versi Odoo, jadi pemakaian di atas tidak perlu diubah.

### Mengganti Panggilan Eksternal dengan `self.patch`

Test tidak boleh bergantung pada jaringan atau layanan luar. `BaseCase` (induk `TransactionCase`) menyediakan `self.patch(obj, key, val)`: ia memanggil `unittest.mock.patch.object(obj, key, val)` lalu otomatis membatalkannya di akhir test (terverifikasi di 18.0 dan 19.0). Ada juga `classPatch` untuk `setUpClass` dan `startPatcher(patcher)` bila kamu butuh objek mock-nya.

Contoh berikut **hipotetis**: anggap `library.book` punya method `action_fetch_isbn_info` yang memanggil `requests.get` ke API ISBN. Modul `library_management` di Bab 10 belum punya method itu.

```python
from unittest.mock import MagicMock

import requests

from odoo.tests import TransactionCase


class TestIsbnLookup(TransactionCase):

    def test_fetch_isbn_info_without_network(self):
        fake_response = MagicMock(status_code=200)
        fake_response.json.return_value = {'title': 'Test Book'}
        # requests.get diganti selama test ini saja
        mocked_get = MagicMock(return_value=fake_response)
        self.patch(requests, 'get', mocked_get)

        book = self.env['library.book'].create({'name': 'Draft'})
        book.action_fetch_isbn_info()      # hipotetis

        mocked_get.assert_called_once()
```

Pola yang sama berlaku untuk pengiriman email atau webhook: ganti fungsi yang melakukan I/O, lalu periksa dengan `assert_called_once()`. Saya sengaja tidak memberi contoh patch method bawaan Odoo (misalnya server email) karena nama method internalnya berbeda antar versi dan tidak diverifikasi di bab ini.

---

## 12. CI/CD untuk Module Odoo

Test baru berguna kalau dijalankan otomatis setiap ada commit atau pull request. Idenya: siapkan PostgreSQL, jalankan container `odoo:18.0` dengan kode modulmu, install modul sambil menjalankan test, lalu gagalkan pipeline kalau ada test yang gagal.

Yang terverifikasi:
- Perintah `odoo -d <db> -i <module> --test-enable --test-tags /<module> --stop-after-init` memakai opsi yang terdokumentasi di referensi CLI 18.0 (`--test-enable`, `--test-tags`, `--stop-after-init`, `-i`). Menurut dokumentasi, `--test-tags` sendiri sudah mengaktifkan unit test.
- Entrypoint image resmi (`odoo/docker`, folder `18.0`) meneruskan argumen yang diawali `odoo` ke binary `odoo`, dan membaca koneksi PostgreSQL dari environment variable `HOST`, `PORT`, `USER`, `PASSWORD` (default host `db`, user dan password `odoo`).
- Config bawaan image memakai `addons_path = /mnt/extra-addons`, jadi modul cukup di-mount ke sana.
- Di kode 18, `odoo` keluar dengan exit code bukan nol bila laporan test tidak sukses (`rc += 1` di `preload_registries`), sehingga step CI otomatis gagal.

> **Peringatan:** pipeline di bawah adalah **ilustrasi dan belum dijalankan** di runner sungguhan. Sesuaikan nama modul, versi PostgreSQL, dan cara checkout dengan repository-mu, lalu uji dulu di branch percobaan.

```yaml
# .github/workflows/odoo-tests.yml
name: Odoo tests

on:
  push:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      db:
        image: postgres:16
        env:
          POSTGRES_USER: odoo
          POSTGRES_PASSWORD: odoo
          POSTGRES_DB: postgres
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U odoo"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10

    steps:
      - uses: actions/checkout@v4

      - name: Jalankan test module library_management
        run: |
          docker run --rm --network host \
            -e HOST=localhost -e PORT=5432 -e USER=odoo -e PASSWORD=odoo \
            -v "$GITHUB_WORKSPACE":/mnt/extra-addons/library_management \
            odoo:18.0 \
            odoo -d ci_test -i library_management \
              --test-enable --test-tags /library_management \
              --stop-after-init
```

Penjelasan:
- Repository diasumsikan berisi satu module di root-nya, jadi di-mount sebagai `/mnt/extra-addons/library_management`. Kalau repository berisi banyak module, mount foldernya ke `/mnt/extra-addons`.
- `--network host` membuat container bisa mencapai PostgreSQL di `localhost:5432` pada runner Linux.
- Database `ci_test` dibuat Odoo saat `-i` dijalankan; akun PostgreSQL `odoo` adalah superuser karena dibuat lewat `POSTGRES_USER`.
- Test `HttpCase` bertag `post_install` (bagian 9 dan 10) tetap bertag `standard`, jadi ikut terpilih oleh `--test-tags /library_management` dan dijalankan di akhir loading. Test tour (`start_tour`) butuh browser Chrome/Chromium; ketersediaannya di image resmi tidak diverifikasi di sini. Jika tour gagal karena itu, beri tag buatan sendiri pada test tour lalu kecualikan dengan awalan `-` (format `--test-tags` ada di bagian 3).
- Jika modulmu bergantung pada modul Odoo lain yang tidak ikut image (misalnya modul OCA), tambahkan repository itu ke `/mnt/extra-addons` dan install dependensi Python-nya; ini di luar contoh.

### Lint (opsional)

Lint tidak diwajibkan Odoo. Berikut contoh job tambahan memakai `ruff` sebagai **opsi**; boleh diganti `flake8` atau `pre-commit` sesuai kebiasaan timmu. Konfigurasi aturannya (mis. `ruff.toml`) kamu tentukan sendiri, dan contoh ini juga belum dijalankan.

```yaml
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install ruff
      - run: ruff check .
```

Jika memakai `pre-commit`, jalankan `pre-commit run --all-files` di job yang sama. Isi `.pre-commit-config.yaml` ditentukan timmu; bab ini tidak mengklaim ada konfigurasi lint standar dari Odoo.

---

## 13. Tips Testing

1. **`with_user(user)`** untuk test sebagai user berbeda (cek access rights).
2. **`Form()`** untuk simulasi UI tanpa browser, jauh lebih cepat dari `HttpCase`.
3. **`setUpClass` vs `setUp`**: `setUpClass` sekali per class (data yang tidak berubah), `setUp` tiap method.
4. **`assertRaises`**: selalu test error case, bukan hanya happy path. Sebutkan exception spesifik, bukan `Exception`.
5. **Test harus independen**: jangan bergantung pada urutan eksekusi.
6. **`HttpCase` lambat**: pakai seperlunya, dan beri `@tagged('post_install', '-at_install')`.

---

## Ringkasan

- `TransactionCase` adalah pilihan default; tiap method di-rollback. `SavepointCase` sudah tidak ada.
- Semua file test harus di-import di `tests/__init__.py` dan namanya diawali `test_`.
- Jalankan dengan `--test-enable` (atau `--test-tags`) bersama `-i`/`-u`; format tag `[-][tag][/module][:class][.method]`.
- Gunakan exception spesifik (`IntegrityError`, `UserError`, `ValidationError`, `AccessError`) dan `mute_logger('odoo.sql_db')` untuk error database yang diharapkan.
- `Form` menguji onchange tanpa browser; `with_user` menguji hak akses; `HttpCase` + `start_tour` menguji UI.
- Tour JS didaftarkan di bundle `web.assets_tests`; test HTTP/UI diberi tag `post_install`.
- `freeze_time` (dari `odoo.tests`, membungkus `freezegun`) membekukan "hari ini" sehingga test denda keterlambatan deterministik; `self.patch` mengganti panggilan eksternal dan otomatis dibatalkan.
- CI menjalankan `odoo -d <db> -i <modul> --test-enable --test-tags /<modul> --stop-after-init` di image `odoo:18.0` dengan service PostgreSQL; exit code bukan nol bila test gagal. Pipeline contoh belum dijalankan; lint hanyalah opsi.

## Latihan

1. Tambahkan test di `TestLibraryLoan` untuk memastikan member dengan `state` bukan `active` tidak bisa konfirmasi loan (`UserError`).
2. Tulis test yang memastikan `action_return` pada loan terlambat membuat record `library.fine` dengan `days_late` yang benar. Tantangan: buat tanggalnya tidak bergantung pada hari ini (hitung dari `fields.Date.today()`), atau bekukan waktu dengan `freeze_time` (bagian 11).
3. Jalankan hanya satu method test lewat `--test-tags /library_management:TestLibraryLoan.test_loan_confirm`, lalu rusak kodenya sengaja dan amati outputnya.
4. Dengan `freeze_time`, tulis test untuk keterlambatan 1 hari dan 30 hari, lalu periksa `days_late` dan `amount` pada `library.fine`.
5. Salin workflow di bagian 12 ke repository-mu, sesuaikan, dan jalankan di branch percobaan. Sengaja buat satu test gagal dan pastikan pipeline-nya merah.

## Lanjut ke

Bab 18: Debugging & Troubleshooting.
