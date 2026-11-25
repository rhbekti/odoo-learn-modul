# Bab 6: Security & Access Rights

> **Tahap:** 2 Inti Pengembangan | **Prasyarat:** Bab 4, 5 | **Estimasi:** ± 2 jam | **Versi:** Odoo 18 (catatan Odoo 19)

## Tujuan Belajar

Setelah bab ini kamu bisa:
- Mendefinisikan group (dengan kategori dan hierarki `implied_ids`) untuk modulmu.
- Menulis `ir.model.access.csv` dengan kolom dan permission yang benar.
- Membatasi record yang terlihat user dengan record rule (`ir.rule`) dan `domain_force`.
- Membatasi field, menu, dan tombol per group.
- Memahami kapan memakai `sudo()` dan cek group di Python, serta cara men-debug masalah akses.

> **Beda di Odoo 19:** Field group milik user, `res.users.groups_id` di Odoo 18, berganti nama menjadi `res.users.group_ids` di Odoo 19 (terverifikasi di kode sumber 19.0; `has_group()` tetap ada). Untuk sintaks `ir.model.access.csv` dan `ir.rule` di bab ini belum ada perbedaan yang terverifikasi. Cara pengelompokan/penamaan group di Odoo 19 bisa berbeda dari contoh di sini; cek release notes dan dokumentasi resmi versi 19 sebelum memigrasikan file `groups.xml`.

## Gambaran: Tiga Lapis Keamanan

| Lapis | Menjawab pertanyaan | Dibuat di |
|---|---|---|
| Group | Siapa user ini (peran apa)? | `security/groups.xml` |
| Access rights | Boleh baca/tulis/buat/hapus **model** ini? | `security/ir.model.access.csv` |
| Record rules | **Record mana** yang boleh disentuh? | `security/ir_rule.xml` |

Tambahan: `groups=` pada field, menu, dan tombol untuk mengatur tampilan per peran. Tanpa baris access rights, model tidak bisa diakses user biasa (hanya superuser yang lolos), jadi setiap model baru wajib punya minimal satu baris di CSV.

## Groups

Group dikelompokkan dalam kategori supaya tampil rapi di form user. Group yang lebih tinggi "mengimplikasikan" group di bawahnya lewat `implied_ids`.

```xml
<!-- security/groups.xml -->
<odoo>
    <record id="module_category_library" model="ir.module.category">
        <field name="name">Library</field>
        <field name="sequence">50</field>
    </record>

    <record id="group_library_viewer" model="res.groups">
        <field name="name">Viewer</field>
        <field name="category_id" ref="module_category_library"/>
        <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
    </record>

    <record id="group_library_user" model="res.groups">
        <field name="name">User</field>
        <field name="category_id" ref="module_category_library"/>
        <field name="implied_ids" eval="[(4, ref('group_library_viewer'))]"/>
    </record>

    <record id="group_library_manager" model="res.groups">
        <field name="name">Manager</field>
        <field name="category_id" ref="module_category_library"/>
        <field name="implied_ids" eval="[(4, ref('group_library_user'))]"/>
    </record>
</odoo>
```

Artinya: Manager otomatis juga User dan Viewer, dan semuanya adalah internal user (`base.group_user`). Di kode lain, group ini dirujuk dengan ID lengkap, misalnya `library_management.group_library_manager`.

## ir.model.access.csv

File ini mendefinisikan permission CRUD per model per group.

```
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_library_book_viewer,library.book viewer,model_library_book,library_management.group_library_viewer,1,0,0,0
access_library_book_user,library.book user,model_library_book,library_management.group_library_user,1,1,1,0
access_library_book_manager,library.book manager,model_library_book,library_management.group_library_manager,1,1,1,1
```

| Kolom | Fungsi |
|-------|--------|
| id | Unique identifier (konvensi: `access_<model>_<group>`) |
| name | Nama deskriptif |
| model_id:id | Referensi model: `model_` + nama model dengan titik jadi underscore (`model_library_book`). Untuk model modul lain: `modul.model_nama` |
| group_id:id | Referensi group; **kosong** berarti berlaku untuk semua user (termasuk portal/public), hati-hati |
| perm_read | Boleh membaca (1=ya, 0=tidak) |
| perm_write | Boleh mengubah |
| perm_create | Boleh membuat record baru |
| perm_unlink | Boleh menghapus |

Permission dari beberapa baris yang berlaku untuk satu user saling **menambah** (union). Daftarkan file ini di manifest setelah `groups.xml`, karena CSV merujuk group.

## Record Rules

Access rights berlaku untuk seluruh model; record rule menyaring **record mana** yang boleh diakses.

```xml
<!-- security/ir_rule.xml -->
<odoo>
    <data noupdate="1">
        <record id="library_book_rule_user" model="ir.rule">
            <field name="name">Library Book: User hanya buku miliknya</field>
            <field name="model_id" ref="model_library_book"/>
            <field name="domain_force">[('partner_id', '=', user.partner_id.id)]</field>
            <field name="groups" eval="[(4, ref('library_management.group_library_user'))]"/>
        </record>

        <record id="library_book_rule_manager" model="ir.rule">
            <field name="name">Library Book: Manager bisa semua</field>
            <field name="model_id" ref="model_library_book"/>
            <field name="domain_force">[(1, '=', 1)]</field>
            <field name="groups" eval="[(4, ref('library_management.group_library_manager'))]"/>
        </record>
    </data>
</odoo>
```

Hal penting:
- Rule berlaku untuk semua operasi (read/write/create/unlink), kecuali kamu mematikannya per operasi lewat field `perm_read`, `perm_write`, `perm_create`, `perm_unlink` (isi `eval="False"`).
- Rule **dengan group**: kalau satu user kena beberapa rule, hasilnya digabung dengan OR. Karena Manager juga User (lewat `implied_ids`), rule `[(1, '=', 1)]` milik Manager "menang" dan membuka semua record.
- Rule **tanpa group** (global) digabung dengan AND, dan selalu berlaku untuk semua user. Gunakan hati-hati.
- Superuser (admin teknis) melewati record rule.
- Record rule dalam `noupdate="1"` tidak ditimpa saat upgrade modul. Artinya kalau kamu mengubah `domain_force` di XML, perubahan itu tidak ikut ter-update di database yang sudah ada (cara mengatasinya dibahas di Bab 7).

### Sintaks `domain_force`

| Sintaks | Fungsi |
|--------|--------|
| `[(1, '=', 1)]` | Izinkan semua record |
| `[(0, '=', 1)]` | Tolak semua record |
| `[('user_id', '=', user.id)]` | Hanya record milik user yang login |
| `[('partner_id', '=', user.partner_id.id)]` | Filter berdasarkan partner user |
| `[('company_id', 'in', company_ids)]` | Filter berdasarkan company yang sedang aktif (multi-company, dibahas di Bab 14) |

Variabel yang tersedia di `domain_force`: `user` (record user saat ini), `company_id`, `company_ids` (company aktif), dan `time`.

## Field Access (Level Field)

Atribut `groups` pada field Python membuat field hanya terlihat/bisa diakses group tertentu. Untuk user lain, field disembunyikan dari view dan mengaksesnya lewat ORM menimbulkan `AccessError`.

```python
from odoo import fields, models


class LibraryBook(models.Model):
    _name = 'library.book'
    _description = 'Library Book'

    name = fields.Char(required=True)
    price = fields.Float(groups='library_management.group_library_manager')
    cost = fields.Float(groups='library_management.group_library_manager')
    internal_notes = fields.Text(
        groups='library_management.group_library_manager',
        help='Internal notes only visible to managers',
    )
```

## Menu dan Tombol Berdasarkan Group

Atribut `groups` di XML juga bisa dipasang pada `menuitem`, `button`, `field`, `page`, dan elemen view lain.

```xml
<menuitem id="menu_library_admin"
          name="Admin Settings"
          parent="menu_library_root"
          action="act_library_admin"
          groups="library_management.group_library_manager"/>
```

```xml
<form>
    <header>
        <button name="action_approve"
                string="Approve"
                class="btn-primary"
                type="object"
                groups="library_management.group_library_manager"/>

        <button name="action_archive_all"
                string="Archive All"
                type="object"
                groups="base.group_system"/>
    </header>
</form>
```

Penting: menyembunyikan menu/tombol hanya mengatur tampilan. Keamanan sebenarnya tetap ada di access rights dan record rules, jadi jangan hanya mengandalkan `groups=` di view.

## Cek Hak Akses di Python

```python
from odoo import models
from odoo.exceptions import AccessError, UserError


class LibraryBook(models.Model):
    _name = 'library.book'
    # ... field-field lain seperti di Bab 4

    def write(self, vals):
        if 'price' in vals and not self.env.user.has_group('library_management.group_library_manager'):
            raise AccessError('Hanya manager yang boleh mengubah harga!')
        return super().write(vals)

    def unlink(self):
        if not self.env.user.has_group('library_management.group_library_manager'):
            if any(book.state == 'done' for book in self):
                raise UserError('Buku berstatus done tidak boleh dihapus!')
        return super().unlink()
```

Cek di Python dilakukan **sebagai tambahan** untuk aturan bisnis; untuk aturan akses dasar, pakai group, CSV, dan record rule. Method `write` dan `unlink` bekerja pada recordset, jadi loop atau `any(...)` dibutuhkan (jangan akses `self.state` langsung kalau `self` bisa berisi banyak record). Pola override `write`/`unlink` dijelaskan lebih lanjut di Bab 8.

## sudo() dan with_user()

```python
def action_special(self):
    # Jalankan sebagai superuser: melewati access rights dan record rules
    return self.sudo().search([])

def action_as_admin(self):
    # Atau jalankan sebagai user tertentu
    return self.with_user(self.env.ref('base.user_admin')).read(['name'])
```

`sudo()` melewati semua pembatasan, jadi pakai seperlunya dan hanya setelah kamu memeriksa sendiri bahwa user memang berhak melakukan aksi tersebut. Jangan pernah mengembalikan hasil `sudo()` mentah ke user yang tidak berhak.

## Mengatur Group dari UI

1. Aktifkan developer mode.
2. Buka Settings > Users & Companies > Groups.
3. Pilih group yang mau diatur.
4. Edit tab "Access Rights" (atau tambah user di tab Users).

Untuk memberi user sebuah peran, buka Settings > Users & Companies > Users, pilih user, lalu pilih peran (group) di tab Access Rights.

## Debug Masalah Akses

Cek apakah user punya group tertentu (misalnya dari shell atau method model):

```python
user = self.env.user
print(f"User: {user.name}")
print(f"Is manager: {user.has_group('library_management.group_library_manager')}")
```

Gejala umum dan penyebabnya:

| Gejala | Kemungkinan penyebab |
|---|---|
| "You are not allowed to access ..." | Tidak ada baris CSV untuk group user, atau `perm_*` bernilai 0 |
| Record "hilang" di list | Record rule menyaringnya; tes dengan user lain atau `sudo()` |
| Field/tombol tidak muncul | `groups=` pada field/tombol tidak cocok dengan group user |
| Perubahan rule tidak berlaku setelah upgrade | Rule ada di `noupdate="1"`, update manual dari UI atau lihat Bab 7 |

## Struktur Security Lengkap

```
library_management/
├── __manifest__.py
├── security/
│   ├── groups.xml
│   ├── ir.model.access.csv
│   └── ir_rule.xml
├── models/
│   └── book.py
└── views/
    └── views.xml
```

Urutan di manifest: group dulu, lalu CSV, lalu rule, lalu views.

```python
'data': [
    'security/groups.xml',
    'security/ir.model.access.csv',
    'security/ir_rule.xml',
    'views/views.xml',
],
```

Isi `groups.xml` dan `ir.model.access.csv` yang dipakai adalah contoh di bagian Groups dan ir.model.access.csv di atas.

## Ringkasan

- Keamanan Odoo berlapis: group (siapa), access rights CSV (boleh apa di model), record rule (record mana).
- Group didefinisikan di `res.groups` dengan `category_id` dan `implied_ids` untuk hierarki peran.
- `ir.model.access.csv`: kolom `perm_read`, `perm_write`, `perm_create`, `perm_unlink`; tanpa baris CSV, user biasa tidak bisa mengakses model.
- Record rule memakai `domain_force`; rule berbasis group digabung OR, rule global digabung AND.
- `groups=` pada field, menu, dan tombol hanya mengatur tampilan dan akses field, bukan pengganti access rights.
- Gunakan `has_group()` untuk cek peran di Python dan `sudo()` secara hati-hati.

## Latihan

1. Buat `groups.xml` dengan kategori "Library" dan dua group (User dan Manager, Manager mengimplikasikan User), lalu `ir.model.access.csv` untuk model `library.book` (User: read/write/create; Manager: semua). Daftarkan di manifest dengan urutan yang benar, upgrade modul, lalu tes dengan dua user berbeda.
2. Tambahkan record rule agar User hanya melihat buku dengan `create_uid` miliknya, sedangkan Manager melihat semua. Buktikan bedanya dengan login sebagai kedua user.
3. Pasang `groups` pada field `cost` (hanya Manager) dan pada sebuah tombol di form (hanya Manager). Cek tampilannya sebagai User dan sebagai Manager.

## Lanjut ke

Bab 7: Data Files, Sequences & Automated Actions (`07-data-files-sequences.md`).
