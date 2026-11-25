# Bab 18: Debugging & Troubleshooting

> **Tahap:** 5 Profesional | **Prasyarat:** Bab 2, Bab 10, Bab 17 | **Estimasi:** ± 3 jam | **Versi:** Odoo 18 (catatan Odoo 19)

Cepat atau lambat module yang kamu tulis akan error. Bab ini membahas alat bantu untuk mencari penyebabnya (developer mode, log, shell, debugger, akses database) dan daftar error yang paling sering muncul beserta solusinya. Contoh memakai module `library_management` dari Bab 10 dan setup Docker dari Bab 1–2 (service `odoo` dan `db`).

## Tujuan Belajar

Setelah bab ini kamu bisa:

- Mengaktifkan developer mode dan memakainya untuk memeriksa field, view, dan metadata record.
- Membaca dan mengatur log Odoo (`_logger`, `--log-level`, `--log-handler`).
- Memakai `odoo shell` dan `--dev` untuk mencoba kode tanpa bolak-balik restart.
- Memasang breakpoint (`breakpoint()`) dan menjalankannya di Docker.
- Mengenali penyebab dan memperbaiki error umum (access, field, external ID, XPath, constraint, view).
- Memakai profiler bawaan Odoo (dari developer mode atau kode Python) dan membaca hasilnya di speedscope.
- Menghitung jumlah query di test dengan `assertQueryCount` untuk mendeteksi masalah N+1.

---

## 1. Developer Mode

```
# Cara 1: via URL
http://localhost:8069/odoo?debug=1

# Cara 2: via Settings
Settings > General Settings > scroll ke bawah > Activate the developer mode

# Cara 3: dengan assets tidak diminifikasi (untuk debug JS/OWL)
http://localhost:8069/odoo?debug=assets

# Cara 4: untuk menjalankan tour/test JS di browser
http://localhost:8069/odoo?debug=tests
```

Matikan dengan `?debug=0`. Developer mode berguna untuk:

- Melihat nama teknis field (hover di label field pada form).
- Membuka menu Settings > Technical (models, views, actions, access rights, dll).
- Mengedit/melihat view langsung dari UI (ikon bug > Edit View / Open View).
- Melihat metadata record (ID, XML ID, tanggal buat) lewat menu "View Metadata".
- Debug JavaScript tanpa minifikasi (`debug=assets`).

---

## 2. Log

### 2.1 Menulis Log dengan `_logger`

Pakai `logging`, bukan `print()`. Deklarasikan logger sekali di level module.

```python
import logging

from odoo import models

_logger = logging.getLogger(__name__)


class LibraryLoan(models.Model):
    _inherit = 'library.loan'

    def action_confirm(self):
        _logger.info('action_confirm dipanggil, ids=%s', self.ids)
        for loan in self:
            _logger.debug('Loan %s (id=%s) state=%s', loan.name, loan.id, loan.state)
        return super().action_confirm()
```

Gunakan format `%s` sebagai argumen logger (bukan f-string) agar string hanya dibentuk jika level log aktif.

### 2.2 Melihat dan Mengatur Log

```bash
# Log realtime
docker compose logs -f odoo

# Filter dengan grep
docker compose logs -f odoo 2>&1 | grep "library"
```

Level log bisa diatur lewat `odoo.conf` (Bab 2) atau opsi CLI:

```ini
# odoo.conf
log_level = debug
log_handler = :INFO,odoo.addons.library_management:DEBUG
```

```bash
# Via CLI (proses terpisah, contoh untuk update module)
docker compose exec odoo odoo -d odoo -u library_management --stop-after-init \
    --log-handler=odoo.addons.library_management:DEBUG
```

| Opsi | Fungsi |
|------|--------|
| `--log-level=debug` | Naikkan level log secara umum (juga ada `info`, `warn`, `error`, `critical`) |
| `--log-handler=LOGGER:LEVEL` | Atur level untuk satu logger; tanda `:` wajib, boleh diulang |
| `--log-sql` | Tampilkan semua query SQL (setara `--log-handler=odoo.sql_db:DEBUG`) |
| `--log-web` | Tampilkan request/response HTTP (setara `--log-handler=odoo.http:DEBUG`) |

Jika `--log-level` dan `--log-handler` bertabrakan, yang dipakai adalah `--log-handler`.

---

## 3. Mode `--dev`

Opsi `--dev` hanya untuk development, **jangan dipakai di production**.

```bash
# Semua fitur dev
odoo -d odoo --dev=all

# Kombinasi pilihan
odoo -d odoo --dev=reload,xml,qweb
```

| Nilai | Efek (Odoo 18) |
|-------|----------------|
| `reload` | Server restart otomatis saat file Python berubah |
| `xml` | Template QWeb dibaca langsung dari file XML, bukan dari database |
| `qweb` | Berhenti di debugger jika node QWeb memakai `t-debug='debugger'` |
| `pdb` | Jalankan debugger Python saat terjadi error tak terduga (juga `ipdb`/`updb`) |
| `werkzeug` | Tampilkan traceback lengkap di halaman web saat exception |
| `all` | Mengaktifkan semua nilai di atas |

Catatan penting:

- `--dev=xml` hanya memengaruhi **template QWeb**. Perubahan pada view (`ir.ui.view`) tetap butuh update module (`-u library_management`) atau tombol upgrade di Apps.
- `--dev=all` di Odoo 18 ikut mengaktifkan `pdb`: kalau ada error, proses akan berhenti menunggu input debugger. Kalau container tidak punya terminal interaktif, request akan menggantung. Pakai `--dev=reload,xml` jika hanya butuh auto-reload.
- `--dev` bukan pengganti `-u` setelah menambah/mengubah field di model.

---

## 4. Odoo Shell

Shell interaktif dengan environment Odoo yang sudah siap (`env`). Cocok untuk mencoba query, memeriksa data, dan menguji method tanpa membuka UI.

```bash
# Dengan Docker
docker compose exec odoo odoo shell -d odoo

# Tanpa Docker
./odoo-bin shell -d odoo
```

> Shell berjalan dalam satu transaksi. Semua perubahan **dibatalkan saat keluar** kecuali kamu memanggil `env.cr.commit()`. Jika gagal terhubung ke database, periksa pengaturan `db_host`/`db_user` di `odoo.conf` (Bab 2).

### Operasi Umum

```python
# Cek record
>>> env['library.book'].search([])
library.book(1, 2, 3)

>>> env['library.book'].search_read([], ['name', 'author'], limit=5)
[{'id': 1, 'name': 'Book 1', 'author': 'Author 1'}, ...]

# Cek definisi field
>>> env['library.book']._fields['name'].required
True

# Cek module terpasang
>>> env['ir.module.module'].search([('state', '=', 'installed')]).mapped('name')

# Cek XML ID
>>> env.ref('library_management.category_fiction')
library.book.category(1,)

# Cek access rights model
>>> env['ir.model.access'].search([('model_id.model', '=', 'library.book')])

# Coba method
>>> loan = env['library.loan'].browse(1)
>>> loan.action_confirm()

# Buat data uji
>>> env['library.book'].create({'name': 'Test', 'category_id': 1})
>>> env.cr.commit()     # simpan permanen (hati-hati)

# Batalkan perubahan sebelum commit
>>> env.cr.rollback()
```

Ingin menjalankan sebagai user tertentu? Gunakan `env['library.book'].with_user(user)`. Untuk bypass sementara saat investigasi, `sudo()` boleh dipakai di shell tapi jangan dibiarkan di kode production (Bab 6).

### Memeriksa Struktur View

```python
# View final setelah semua inheritance digabung
>>> view = env.ref('library_management.view_library_book_form')
>>> print(view._get_combined_arch())

# Daftar view yang meng-inherit view ini
>>> for child in env['ir.ui.view'].search([('inherit_id', '=', view.id)]):
...     print(child.name, child.xml_id)
```

---

## 5. Breakpoint (pdb)

```python
def action_confirm(self):
    breakpoint()          # eksekusi berhenti di sini
    return super().action_confirm()
```

| Perintah | Fungsi |
|----------|--------|
| `n` | Baris berikutnya |
| `s` | Masuk ke dalam fungsi |
| `c` | Lanjut sampai breakpoint berikutnya |
| `p var` / `pp var` | Cetak / cetak rapi variabel |
| `l` | Tampilkan kode di sekitar baris |
| `q` | Keluar dari debugger |
| `h` | Bantuan |

Agar debugger bisa dipakai:

1. Jalankan Odoo dengan `workers = 0` (mode satu proses; ini sudah jadi setelan development di Bab 2). Dengan multiprocessing, debugger tidak mendapat terminal.
2. Di Docker, service harus punya terminal interaktif. Tambahkan di `docker-compose.yml`:

```yaml
services:
  odoo:
    stdin_open: true
    tty: true
```

3. Setelah `docker compose up -d`, sambungkan ke proses utama container dengan `docker attach odoo18_dev` (nama container dari Bab 1). Lepas tanpa mematikan container dengan `Ctrl+P` lalu `Ctrl+Q`.

Jangan menjalankan instance Odoo kedua dengan `docker compose exec` hanya untuk pdb: port 8069 sudah dipakai instance utama. Untuk proses sekali jalan (update module, shell) `exec` tetap tepat.

---

## 6. Inspect Database Langsung

```bash
# Masuk PostgreSQL (service db, user odoo, database odoo)
docker compose exec db psql -U odoo odoo
```

```sql
-- Daftar tabel dan struktur
\dt library_*
\d library_book

-- Query langsung
SELECT id, name, state FROM library_loan WHERE state = 'active';

-- Foreign key tabel library_loan
SELECT conname, conrelid::regclass, confrelid::regclass
FROM pg_constraint
WHERE conrelid = 'library_loan'::regclass AND contype = 'f';
```

Query langsung cukup untuk membaca. Jangan mengubah data lewat SQL kecuali kamu tahu dampaknya: ORM tidak tahu perubahan itu (cache, computed stored field, chatter).

---

## 7. Common Errors & Solusi

Teks error di bawah adalah contoh; kata persisnya bisa sedikit berbeda antar versi. Cari kata kuncinya di log.

### 7.1 AccessError

```
odoo.exceptions.AccessError: You are not allowed to access 'Library Book' (library.book) records.
```

**Penyebab:** model belum punya baris di `ir.model.access.csv`, user tidak ada di group yang benar, atau record rule memblokir.

```python
# Di shell: cek access rights dan group user
>>> env['ir.model.access'].search([('model_id.model', '=', 'library.book')])
>>> env.user.groups_id.mapped('full_name')   # Odoo 19: gunakan env.user.group_ids
```

Perbaiki di `security/ir.model.access.csv` (Bab 6), bukan dengan `sudo()` permanen.
### 7.2 Field tidak ditemukan di view

Pesan validasi view menyebut field `xxx` tidak ada pada model `library.book`.

**Penyebab:** field dipakai di XML tapi belum didefinisikan di Python, typo nama field, atau module belum di-update setelah menambah field.

```bash
docker compose exec odoo odoo -d odoo -u library_management --stop-after-init
```

### 7.3 External ID not found

```
ValueError: External ID not found in the system: library_management.view_xxx
```

**Penyebab:** XML ID belum di-load, urutan file `data` di `__manifest__.py` salah (file yang merujuk dimuat sebelum file yang didefinisikan), atau typo.

**Solusi:** cek urutan `data` di manifest (security, data, views, menu; Bab 3 dan 7) dan pastikan file XML-nya terdaftar. Ingat: ID tanpa prefix module dicari di module yang sama; dari module lain wajib `module.id`.

### 7.4 Constraint Violation

```
psycopg2.errors.UniqueViolation: duplicate key value violates unique constraint "library_book_category_name_parent_uniq"
```

**Penyebab:** data melanggar SQL constraint (misalnya `name_parent_uniq` di Bab 10). Nama constraint di database = nama tabel + `_` + nama constraint.

**Solusi:** validasi sebelum create/write, atau tangkap error di dalam **savepoint** agar transaksi tidak rusak:

```python
from psycopg2 import IntegrityError
from odoo.exceptions import UserError
from odoo.tools import mute_logger

try:
    with mute_logger('odoo.sql_db'), self.env.cr.savepoint():
        category = self.env['library.book.category'].create(vals)
except IntegrityError:
    raise UserError('Kategori dengan nama itu sudah ada di parent yang sama!')
```

Jangan memanggil `self.env.cr.rollback()` di dalam method model: ia membatalkan **seluruh** transaksi, termasuk pekerjaan caller. Pesan untuk user biasanya lebih rapi bila diberikan lewat pesan constraint sendiri (argumen ketiga di `_sql_constraints`).

### 7.5 RecursionError

```
RecursionError: maximum recursion depth exceeded
```

**Penyebab:** `@api.depends` melingkar, override yang memanggil dirinya sendiri (mis. `self.write()` di dalam `write()`), atau onchange yang saling memicu.

```python
def write(self, vals):
    # Jangan lupa super(); jangan write() lagi ke field yang sama di sini
    return super().write(vals)
```

### 7.6 XPath tidak ditemukan (inheritance view)

Pesan error menyebut elemen `<xpath expr="...">` tidak bisa ditemukan di parent view.

**Penyebab:** expression tidak cocok dengan struktur parent view (field dihapus/dipindah, atau modul yang menambahkannya belum menjadi dependency).

```python
# Lihat struktur parent view di shell
>>> print(env.ref('base.view_partner_form')._get_combined_arch())
```

Alternatif lewat UI (developer mode): Settings > Technical > User Interface > Views, cari view parent, lihat tab Architecture.

### 7.7 View lama setelah upgrade (`tree`, `attrs`)

Setelah memindahkan module dari Odoo 16 atau lebih lama ke 17/18, view sering gagal divalidasi. Dua penyebab paling umum:

- `<tree>` dan `view_mode="tree,form"` harus menjadi `<list>` dan `view_mode="list,form"`.
- Atribut `attrs="{'invisible': [...]}"` dan `states="..."` tidak lagi dipakai; ganti dengan `invisible="expr"`, `readonly="expr"`, `required="expr"` langsung di elemen.

Karena teks error pastinya berbeda-beda, cari kata `tree`, `attrs`, atau `states` di pesan dan di file XML.

### 7.8 Domain tidak valid

Jika pesan menyebut field tidak valid pada "leaf" domain, artinya satu tuple domain memakai nama field yang tidak ada di model (atau path relasinya salah, mis. `'category_id.nama'` padahal field-nya `name`). Cek `env['library.book']._fields` di shell.

### 7.9 Module tidak muncul / tidak bisa diinstall

**Penyebab:** `addons_path` tidak memuat folder module, ada syntax error di `__manifest__.py`, atau dependency belum terpasang. Module baru juga tidak muncul sampai daftar apps diperbarui.

```bash
# Cek addons_path di odoo.conf yang kamu pasang (Bab 2),
# lalu pastikan folder module ada di path itu
docker compose exec odoo ls /mnt/extra-addons

# Perbarui daftar apps: aktifkan developer mode, lalu
# Apps > Update Apps List
```

Perintah `-u base` tidak dipakai untuk ini; `-u` hanya meng-update module yang sudah terpasang.

### 7.10 KeyError pada `create`

```
KeyError: 'name'
```

**Penyebab:** `vals['name']` padahal key tidak ada. Sejak `create` menerima banyak record (Odoo 18: `@api.model_create_multi`), parameternya adalah **list** of dict.

```python
@api.model_create_multi
def create(self, vals_list):
    for vals in vals_list:
        name = vals.get('name', 'New')   # aman jika key tidak ada
    return super().create(vals_list)
```

### 7.11 Konflik transaksi (serialization / deadlock)

Log menampilkan error PostgreSQL seperti `could not serialize access due to concurrent update` (kelas `TransactionRollbackError`). Penyebabnya dua transaksi menulis record yang sama berbarengan.

Odoo biasanya mengulang request secara otomatis beberapa kali, jadi error ini hanya mengganggu bila transaksimu panjang atau mengandung efek samping yang tidak bisa diulang (kirim email, panggil API luar). Solusi: pendekkan transaksi, jangan lakukan efek samping sebelum `commit`, dan untuk kasus tertentu kunci baris:

```python
self.env.cr.execute(
    "SELECT id FROM library_book WHERE id = %s FOR UPDATE NOWAIT", (self.id,)
)
```

### 7.12 Perubahan JS/asset tidak tampil

**Penyebab:** bundle asset lama masih tersimpan di cache/database, atau file belum terdaftar di `assets` pada manifest (Bab 13).

```bash
# 1. Buka dengan ?debug=assets dan hard refresh browser (Ctrl+Shift+R)
# 2. Jika masih lama, hapus bundle tersimpan dari shell:
docker compose exec odoo odoo shell -d odoo
>>> env['ir.attachment'].search([('url', 'like', '/web/assets/')]).unlink()
>>> env.cr.commit()
```

Jika file baru, pastikan sudah masuk `assets` di manifest dan jalankan `-u library_management`.

---

## 8. Profiling: Mencari Bagian yang Lambat

Kalau masalahnya bukan error tetapi lambat, jangan menebak. Odoo punya profiler terintegrasi yang merekam query SQL dan stack trace, lalu hasilnya bisa dilihat sebagai flamegraph di speedscope (semua poin di bagian ini mengacu pada dokumentasi resmi 18.0, halaman Performance bagian Profiling).

### 8.1 Dari Developer Mode (UI)

Cara ini hanya merekam request web. Langkahnya:

1. Aktifkan developer mode (bagian 1).
2. Aktifkan profiler secara global di database: buka menu alat developer mode lalu geser tombol **Enable profiling** dan pilih masa berlakunya di wizard, atau lewat Settings > General Settings > Performance pada field **Enable profiling until**.
3. Geser lagi tombol **Enable profiling** supaya profiler aktif untuk sesi browser-mu. Opsi bawaan yang aktif adalah **Record sql** dan **Record traces**.
4. Lakukan aksi yang lambat (misalnya buka list `library.loan` dengan banyak data).
5. Matikan profiling, lalu buka tombol di pojok kanan atas bagian profiling pada menu developer mode untuk melihat daftar record `ir.profile` per sesi. Tiap record punya link yang membuka hasil di speedscope.

Dokumentasi mencatat bahwa database Odoo Online tidak bisa diprofil. Pilihan tampilan speedscope antara lain **Combined** (SQL dan trace digabung), **sql (no gap)** (hanya query, untuk optimasi SQL), **sql (density)** (berguna melihat area yang berisi banyak query kecil yang bisa digabung), dan **frames** (hanya hasil periodic collector). Profiler punya overhead, jadi angka waktu di speedscope bukan angka murni.

### 8.2 Dari Kode Python

Untuk memprofil satu method, compute, atau test, panggil `Profiler` sebagai context manager (class `odoo.tools.profiler.Profiler`):

```python
from odoo.tools.profiler import Profiler


def action_return_many(self):
    with Profiler():
        for loan in self:
            loan.action_return()
```

Tanpa argumen, collector bawaannya adalah `sql` dan `traces_async` (periodic). Kamu bisa memilih sendiri lewat parameter `collectors`, misalnya `collectors=['sql']`. Parameter lain yang terdokumentasi: `db`, `profile_session`, `description`, `disable_gc`, `params`. Collector yang tersedia: `sql` (`SqlCollector`), `traces_async` (`PeriodicCollector`, interval bawaan 10 ms), `qweb` (`QwebCollector`), dan `traces_sync` (`SyncCollector`, tanpa tombol di UI).

Di dalam test, `BaseCase` punya shortcut `self.profile()` yang menyiapkan `description` dan sesi dari nama test (terverifikasi di kode 18.0 dan 19.0):

```python
def test_return_many_loans(self):
    with self.profile():
        loans.action_return()
```

Jika perulangan memanggil fungsi yang sama berkali-kali, bungkus tiap iterasi dengan `ExecutionContext(current_index=index)` supaya tiap pemanggilan terpisah di speedscope (tip dari dokumentasi). Saya tidak mencantumkan alamat import `ExecutionContext` karena dokumentasi tidak menyebutkannya; cek di `odoo/tools/profiler.py` versi yang kamu pakai.

### 8.3 Log SQL

Untuk sekadar melihat query apa yang jalan, `--log-sql` (bagian 2.2) sudah cukup: opsi ini setara `--log-handler=odoo.sql_db:DEBUG`. Output-nya sangat panjang, jadi pakai untuk skenario kecil, bukan seluruh sesi.

---

## 9. Menghitung Jumlah Query di Test dan Deteksi N+1

Masalah N+1 terjadi ketika kode menjalankan 1 query untuk mengambil daftar, lalu 1 query tambahan untuk setiap item. Dengan 5 loan tidak terasa, dengan 5.000 loan halaman membeku. Profiler (bagian 8) membantu menemukannya setelah terjadi; test dengan `assertQueryCount` mencegahnya kembali.

Sumber 18.0 dan 19.0 (`odoo/tests/common.py`) mendefinisikan di `BaseCase`:

```python
assertQueryCount(self, default=0, flush=True, **counters)
```

Ia context manager yang menghitung query di dalam blok `with`. Dipanggil dengan satu angka (`self.assertQueryCount(42)`) atau per user (`self.assertQueryCount(admin=3, demo=5)`, dipadukan dengan decorator `@users`). Perilaku yang perlu diketahui dari kodenya:

- Jika jumlah query **lebih banyak** dari yang diharapkan, test gagal dengan pesan `Query count more than expected ... X > Y`. Jika **lebih sedikit**, hanya dicatat di log (info), test tidak gagal.
- Sebelum dan sesudah blok, ORM di-flush (`flush=True` bawaan) supaya query tulis yang tertunda ikut terhitung.
- Hitungan hanya ditegakkan saat `self.warm` bernilai `True` (nilai bawaan). Decorator `warmup` menjalankan test sekali untuk memanaskan cache, lalu sekali lagi untuk menghitung.

Cara paling jujur mengisi angkanya: jalankan test dengan angka tebakan, baca angka sebenarnya dari pesan gagal, lalu periksa apakah angka itu masuk akal.

Untuk mendeteksi N+1, jangan mengunci satu angka mentah. Jalankan blok yang sama dengan jumlah data kecil dan besar, dan harapkan angka query yang sama:

```python
# tests/test_loan_queries.py
from .common import LibraryTestCommon


class TestLoanQueries(LibraryTestCommon):

    def _make_loans(self, count):
        loans = self.env['library.loan']
        for i in range(count):
            copy = self.env['library.book.copy'].create({
                'barcode': f'Q-{count}-{i}',
                'book_id': self.book.id,
                'state': 'available',
            })
            loans |= self.env['library.loan'].create({
                'member_id': self.member.id,
                'loan_date': '2026-05-01',
                'due_date': '2026-05-15',
                'line_ids': [(0, 0, {'copy_id': copy.id})],
            })
        return loans

    def _read_titles(self, loans):
        # Akses relasi di dalam loop: ORM harus mem-prefetch, bukan query per loan
        return [loan.line_ids.copy_id.book_id.name for loan in loans]

    def test_read_titles_query_count_is_constant(self):
        few, many = self._make_loans(2), self._make_loans(10)
        expected = 6   # contoh: isi dari hasil pengukuran pertama, jangan ditebak

        self.env.invalidate_all()
        with self.assertQueryCount(expected):
            self._read_titles(few)

        self.env.invalidate_all()
        with self.assertQueryCount(expected):   # angka sama walau datanya 5x lebih banyak
            self._read_titles(many)
```

Contoh ini **belum dijalankan**; angka `6` hanya penanda tempat. Jika kodenya mengalami N+1, blok kedua melaporkan `X > 6` dan test gagal, itulah sinyalnya. Dengan `invalidate_all()` cache dikosongkan supaya kedua blok mulai dari kondisi yang sama.

Pola N+1 yang paling sering di kode Odoo adalah memecah recordset di dalam loop, sehingga prefetch ORM tidak bekerja untuk seluruh recordset:

```python
# N+1: tiap browse/search di loop membuat query sendiri
for loan_id in loan_ids:
    loan = self.env['library.loan'].browse(loan_id)
    print(loan.member_id.name)

# Lebih baik: satu recordset, ORM mem-prefetch field untuk semua record sekaligus
for loan in self.env['library.loan'].browse(loan_ids):
    print(loan.member_id.name)
```

Dokumentasi profiling juga menyebut kombinasi yang berguna: `with self.profile():` di luar, `with self.assertQueryCount(...)` di dalam, supaya profiler ikut menangkap query saat flush ketika blok selesai. Profiler tidak menggantikan test query: profiler untuk menemukan penyebab, `assertQueryCount` untuk menjaga agar tidak kambuh.

> **Beda di Odoo 19:** `assertQueryCount(default=0, flush=True, **counters)` dan `self.profile()` ada di `odoo/tests/common.py` 19.0 dengan signature yang sama. Halaman dokumentasi dan tampilan UI profiling untuk 19 tidak diverifikasi di bab ini.

---

## Tips Debugging

1. Baca log dulu; sebagian besar error sudah punya pesan dan traceback yang jelas. Mulai dari baris paling bawah traceback.
2. Pakai `--dev=reload,xml` saat menulis Python/QWeb; ingat view biasa tetap butuh `-u`.
3. Shell adalah teman terbaik: coba query dan logic tanpa menyentuh UI.
4. Persempit masalah: buat reproduksi sekecil mungkin (satu record, satu method).
5. `sudo()` hanya untuk diagnosis; jangan sampai terbawa ke kode production.
6. Backup database sebelum eksperimen lewat shell yang memakai `commit()`.
7. Pastikan versi module di database sudah ter-update (`-u`) sebelum menyimpulkan ada bug di kode.
8. Untuk masalah performa (bukan error), pakai profiler bawaan (bagian 8) dan kunci hasil perbaikannya dengan `assertQueryCount` (bagian 9).

> **Beda di Odoo 19:**
> - Dokumentasi CLI Odoo 19 mendaftar nilai `--dev`: `all` (alias `xml,reload,qweb,access`), `xml`, `reload`, `qweb`, `werkzeug`, `replica`, dan `access` (mencatat traceback di samping AccessError yang berujung 403). Nilai `pdb` tidak muncul di daftar itu, dan `all` tidak lagi mencakup `werkzeug`.
> - Nilai `access` tidak ada di daftar `--dev` Odoo 18.

## Ringkasan

- Developer mode (`?debug=1`, `debug=assets`, `debug=tests`) membuka menu Technical, metadata record, dan editor view.
- Gunakan `_logger` dengan argumen `%s`, lalu atur tingkat log lewat `--log-level`, `--log-handler`, `--log-sql`.
- `odoo shell` berjalan dalam satu transaksi; perubahan hilang kecuali `env.cr.commit()`.
- `--dev` hanya untuk development: `reload` (restart Python), `xml` (QWeb dari file), `pdb`, `werkzeug`; `all` di Odoo 18 mencakup semuanya, termasuk `pdb`.
- Debugger `breakpoint()` butuh `workers = 0` dan, di Docker, `stdin_open: true` + `tty: true` lalu `docker attach`.
- Error umum biasanya berakar di access rights, urutan file manifest, nama field/XPath yang salah, atau sintaks lama (`tree`, `attrs`).
- Jangan `rollback()` di method model; pakai savepoint.
- Profiler: aktifkan global lalu per sesi lewat menu developer mode (hanya request web), atau `with Profiler():` / `self.profile()` dari Python; hasil tersimpan sebagai `ir.profile` dan dibuka di speedscope.
- `assertQueryCount` gagal bila query lebih banyak dari yang diharapkan; membandingkan angka yang sama untuk data kecil dan besar adalah cara mendeteksi N+1.

## Latihan

1. Di `library_management`, tambahkan `_logger.info` di `action_confirm` milik `library.loan`. Atur `--log-handler=odoo.addons.library_management:DEBUG` lalu konfirmasi sebuah loan dan temukan barisnya di `docker compose logs odoo`.
2. Buka `odoo shell`, buat satu `library.book` dengan `create`, cek hasilnya dengan `search`, lalu `env.cr.rollback()` dan buktikan record-nya hilang. Ulangi dengan `commit()` dan lihat bedanya setelah shell ditutup.
3. Sengaja salahkan: ubah nama field di sebuah view menjadi typo, jalankan `-u library_management`, baca pesan errornya, lalu perbaiki. Lalu hapus satu baris di `ir.model.access.csv` dan lihat `AccessError` sebagai user biasa.
4. Aktifkan profiler dari developer mode, buka list `library.loan`, lalu cari record `ir.profile` yang terbentuk dan buka di speedscope. Coba tampilan **sql (density)**.
5. Tulis test seperti di bagian 9 untuk memastikan jumlah query konstan saat jumlah loan bertambah. Lalu sengaja buat N+1 (`browse` per id di dalam loop) dan amati test-nya gagal.

## Lanjut ke

Bab 19: External API, untuk mengakses data Odoo dari aplikasi lain lewat XML-RPC dan JSON-RPC.
