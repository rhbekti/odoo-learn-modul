# Ringkasan Cepat: Odoo 18 (dengan catatan Odoo 19)

Dokumen ini dipakai untuk mengulang materi dan sebagai cheat sheet perbedaan versi. Detail dan contoh lengkap ada di bab masing-masing.

---

## Ringkasan per Tahap

### Tahap 1: Persiapan (Bab 1–3)

- **Bab 1:** Odoo dan PostgreSQL berjalan sebagai dua container lewat Docker Compose; data disimpan di named volume.
- **Bab 2:** `odoo.conf` mengatur database, addons path, dan mode; CLI (`-i`, `-u`, `--stop-after-init`) dipakai untuk install/update module.
- **Bab 3:** satu module = folder dengan `__manifest__.py`, `__init__.py`, dan subfolder `models/`, `views/`, `security/`. Urutan `data` di manifest penting.

### Tahap 2: Inti Pengembangan (Bab 4–10)

- **Bab 4:** model mewarisi `models.Model`; field computed memakai `@api.depends`; relasi memakai Many2one/One2many/Many2many; create/write memakai `Command`.
- **Bab 5:** tampilan dibangun dari view XML (form, list, search, kanban, dan lainnya) yang dibungkus action dan menu. Kondisi tampilan ditulis inline: `invisible="state != 'draft'"`.
- **Bab 6:** tiga lapis keamanan: access rights (`ir.model.access.csv`), record rules (`ir.rule`), dan group.
- **Bab 7:** data awal lewat XML/CSV, sequence untuk penomoran otomatis, cron untuk tugas terjadwal.
- **Bab 8:** tiga jenis inheritance: extension (`_inherit`), prototype (`_inherit` + `_name`), delegation (`_inherits`); view diubah dengan xpath.
- **Bab 9:** wizard = `TransientModel` yang dibuka sebagai dialog (`target='new'`).
- **Bab 10:** menyatukan semuanya dalam module Library dengan 6 model.

### Tahap 3: Fitur Lanjutan (Bab 11–14)

- **Bab 11:** report PDF = action + template QWeb, dirender wkhtmltopdf.
- **Bab 12:** controller menangani request HTTP/JSON; selalu tentukan `auth` dan jangan membuka `sudo()` tanpa filter.
- **Bab 13:** frontend memakai OWL; file JS di `static/src` didaftarkan lewat key `assets` di manifest.
- **Bab 14:** string Python dibungkus `_()`, field `translate=True`; multi-company memakai `company_id` dan record rule.

### Tahap 4: Data & Analitik (Bab 15–16)

- **Bab 15:** SQL view = model `_auto = False` yang dibuat di `init()`; materialized view perlu di-refresh (misalnya lewat cron).
- **Bab 16:** contoh dashboard penjualan lengkap dengan pivot dan graph.

### Tahap 5: Profesional (Bab 17–21)

- **Bab 17:** `TransactionCase` untuk logika, `HttpCase` untuk controller dan tour, `Form` untuk menguji onchange.
- **Bab 18:** developer mode, Odoo shell, log, `pdb`, dan daftar error umum.
- **Bab 19:** akses dari luar lewat XML-RPC/JSON-RPC; Odoo tidak punya REST API bawaan.
- **Bab 20:** production = workers, `proxy_mode`, Nginx dengan SSL dan websocket, tuning PostgreSQL, backup.
- **Bab 21:** konvensi, pola yang dianjurkan, anti-pattern, dan checklist akhir.

---

## Cheat Sheet Perbedaan Versi

Hanya hal yang sudah dicek ke dokumentasi resmi atau kode sumber Odoo yang dicantumkan.

### View & XML

| Hal | Cara lama | Odoo 18 dan 19 |
|-----|-----------|----------------|
| Tag daftar | `<tree>` | `<list>`; `view_mode="list,form"` |
| Kondisi tampilan | `attrs="{'invisible': [...]}"`, `states="..."` | `invisible="state != 'draft'"`, `readonly=`, `required=`, `column_invisible=` |
| Chatter | blok `div.oe_chatter` manual | `<chatter/>` |
| Template kanban | `kanban-box` | `t-name="card"` |
| Output QWeb | `t-raw`, `t-esc` | `t-out` |

### Python & ORM

| Hal | Odoo 18 | Odoo 19 |
|-----|---------|---------|
| Nama tampilan record | `_compute_display_name` (`name_get()` sudah ditinggalkan) | sama |
| Aggregator field | `aggregator` (pengganti `group_operator`) | sama |
| Constraint SQL | `_sql_constraints` | `models.Constraint`, `models.Index`, `models.UniqueIndex` |
| Domain terprogram | list domain | list domain tetap didukung; kelas `odoo.fields.Domain` terdokumentasi |
| Agregasi | `read_group` terdokumentasi | hanya `_read_group` yang terdokumentasi |
| Group milik user | `res.users.groups_id` | `res.users.group_ids` |
| Terjemahan string Python | `from odoo import _` | dokumentasi menampilkan `self.env._("...")` |
| Cek hak akses | `check_access(operation)` | sama |
| Query SQL aman | `odoo.tools.SQL`, `env.execute_query` | ada; `%` harus ditulis `%%`; `filtered()` menerima `Domain` |
| Cache registry | `@tools.ormcache`, `ormcache_context(keys=)` | `ormcache_context` dan `skiparg` deprecated; ada cache `'stable'` |
| Test tanggal | `freeze_time` dari `odoo.tests` | ada, signature lebih lengkap |
| Cron | `ir.cron` tanpa `numbercall`/`doall` | sama |

### Web, API & Infrastruktur

| Hal | Odoo 18 | Odoo 19 |
|-----|---------|---------|
| Route JSON | `@http.route(type='json')` | dokumentasi menyebut `type='jsonrpc'` |
| External API | XML-RPC dan JSON-RPC | JSON-2 (`POST /json/2/<model>/<method>`, bearer API key); XML-RPC dan JSON-RPC deprecated, penghapusan dijadwalkan di Odoo 22 / Online 21.1 |
| JS di `static/src` | otomatis menjadi module Odoo | sama |
| RPC di OWL | `import { rpc } from "@web/core/network/rpc"` | sama |
| Asset | key `assets` di manifest | sama |
| Python | 3.10+ | 3.10+ |
| PostgreSQL | 12+ | 13+ |
| Prefix versi manifest | `18.0.x.y.z` | `19.0.x.y.z` |

### Yang Berubah Sebelum Odoo 18

- `attrs=` dan `states=` di view sudah tidak dipakai sejak Odoo 17.
- `name_get()` ditinggalkan sejak Odoo 17.
- `@api.multi` sudah tidak ada sejak Odoo 11.

---

## Hal yang Perlu Dicek Sendiri

Beberapa hal sengaja tidak ditegaskan di materi karena belum bisa diverifikasi. Cek dulu sebelum dipakai di Odoo 19:

- Apakah `type='json'` masih diterima sebagai alias di Odoo 19.
- Struktur kategori/privilege group di Odoo 19 untuk `groups.xml`.
- Selector dan API tour JavaScript di Odoo 19.
- Perubahan sintaks QWeb/report antara 18 dan 19 (belum ditemukan, tapi belum diuji).

---

## Dokumen Terkait

- [00-daftar-isi.md](00-daftar-isi.md): peta jalur belajar dan prasyarat per bab.
- [README.md](README.md): gambaran umum dan changelog.

*Last updated: 2026-11-24*
