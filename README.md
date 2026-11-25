# Panduan Lengkap Odoo 18 Development

![Odoo 18](https://img.shields.io/badge/Odoo-18.0-714B67?style=for-the-badge&logo=odoo)
![Odoo 19](https://img.shields.io/badge/Catatan-Odoo%2019.0-714B67?style=for-the-badge&logo=odoo)
![Python](https://img.shields.io/badge/Python-3.10+-3776AB?style=for-the-badge&logo=python&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12%2B%20(18)%20%7C%2013%2B%20(19)-336791?style=for-the-badge&logo=postgresql&logoColor=white)

Panduan belajar pengembangan Odoo dari dasar sampai production, dalam Bahasa Indonesia. Contoh kode memakai **Odoo 18**; perbedaan di **Odoo 19** ditandai dengan kotak `Beda di Odoo 19` di tiap bab.

---

## Mulai dari Mana?

1. Buka [00-daftar-isi.md](00-daftar-isi.md) untuk peta jalur belajar lengkap (5 tahap, 21 bab).
2. Pemula: kerjakan Bab 1 sampai 10 berurutan. Bab 10 adalah proyek akhir Tahap 2.
3. Sudah berpengalaman: pilih bab sesuai kebutuhan; setiap bab mencantumkan prasyaratnya.
4. Migrasi dari Odoo 17 atau lebih lama: lihat tabel perbedaan versi di [RINGKASAN.md](RINGKASAN.md).

## Jalur Belajar

| Tahap | Bab | Isi |
|-------|-----|-----|
| 1. Persiapan | 1–3 | Docker, `odoo.conf` & CLI, struktur module |
| 2. Inti Pengembangan | 4–10 | Models & ORM, views, security, data & cron, inheritance, wizard, proyek Library |
| 3. Fitur Lanjutan | 11–14 | QWeb report PDF, controller, OWL, i18n & multi-company |
| 4. Data & Analitik | 15–16 | SQL view, materialized view, Sales Analytics |
| 5. Profesional | 17–21 | Testing, debugging, external API, deployment, best practices |

Estimasi total: ± 61 jam belajar aktif.

### Rencana 6 Minggu (contoh)

| Minggu | Bab | Target |
|--------|-----|--------|
| 1 | 1–4 | Environment jalan, module pertama punya satu model |
| 2 | 5–7 | Model punya view, hak akses, dan data awal |
| 3 | 8–10 | Inheritance, wizard, dan proyek Library selesai |
| 4 | 11–14 | Report PDF, endpoint, komponen OWL, terjemahan |
| 5 | 15–17 | Dashboard SQL view dan test otomatis |
| 6 | 18–21 | Debugging, API, deployment, review checklist |

---

## Quick Start

```bash
# 1. Siapkan environment (detail di Bab 1)
docker compose up -d

# 2. Buka Odoo
# http://localhost:8069

# 3. Buat module pertama (detail di Bab 3)
mkdir -p addons/library_management/{models,views,security}
touch addons/library_management/__init__.py addons/library_management/__manifest__.py
```

Seluruh contoh memakai satu module bernama `library_management`. Nama ini konsisten dari Bab 3 sampai Bab 21.

---

## Cakupan Versi

| Hal | Odoo 18 (utama) | Odoo 19 (catatan) |
|-----|-----------------|--------------------|
| Python | 3.10+ | 3.10+ |
| PostgreSQL | 12+ | 13+ |
| Tag daftar di view | `<list>` | `<list>` |
| Constraint SQL | `_sql_constraints` | `models.Constraint`, `models.Index`, `models.UniqueIndex` |
| External API | XML-RPC & JSON-RPC | JSON-2 (`/json/2/...`); XML-RPC/JSON-RPC deprecated |

Daftar lengkap ada di [RINGKASAN.md](RINGKASAN.md). Semua klaim versi dicek ke dokumentasi resmi Odoo 18 dan 19 serta kode sumber 18.0/19.0 di GitHub. Klaim yang tidak bisa diverifikasi sengaja tidak ditulis sebagai fakta.

---

## Format Tiap Bab

Setiap bab memakai kerangka yang sama supaya mudah dipelajari:

1. **Meta:** tahap, prasyarat, estimasi waktu, versi.
2. **Tujuan Belajar:** apa yang bisa kamu lakukan setelah bab selesai.
3. **Isi:** dari konsep sederhana ke kompleks.
4. **Beda di Odoo 19:** kotak catatan singkat bila relevan.
5. **Ringkasan:** poin-poin yang perlu diingat.
6. **Latihan:** 2–3 soal praktik kecil.
7. **Lanjut ke:** bab berikutnya.

## Verifikasi Materi

```bash
./verify.sh
```

Skrip mengecek kelengkapan 21 bab, kesesuaian judul dengan nomor file, tautan antar-berkas, sisa sintaks lama, dan konsistensi nama module.

---

## Kontribusi

Panduan ini bersifat open source. Kontribusi diterima untuk perbaikan typo, koreksi kode, contoh tambahan, atau pembaruan versi. Cara umum: fork, buat branch, commit, lalu pull request. Sertakan sumber (dokumentasi resmi atau kode sumber Odoo) untuk setiap klaim perbedaan versi.

## Sumber Resmi

- [Dokumentasi Odoo 18](https://www.odoo.com/documentation/18.0/)
- [Dokumentasi Odoo 19](https://www.odoo.com/documentation/19.0/)
- [Odoo di GitHub](https://github.com/odoo/odoo)

## Lisensi

Dokumentasi ini open source dan bebas dipakai untuk pembelajaran pribadi, training internal, referensi project, dan dibagikan ke komunitas. Tidak diperbolehkan dijual kembali tanpa izin atau diklaim sebagai karya sendiri.

---

## Changelog

### Version 3.0 (2026-11-24)
- Jalur belajar disusun ulang menjadi 5 tahap; urutan bab berubah (Security → Bab 6, Data Files → Bab 7, Inheritance → Bab 8, Wizards → Bab 9, QWeb → Bab 11, Controllers → Bab 12, i18n → Bab 14, Database Views → Bab 15, Contoh Praktis → Bab 16, Testing → Bab 17, Debugging → Bab 18, External API → Bab 19, Deployment → Bab 20, Tips → Bab 21).
- Setiap bab diseragamkan: meta, tujuan belajar, ringkasan, latihan, kotak Odoo 19.
- Seluruh contoh disesuaikan dengan Odoo 18: `<list>`, `<chatter/>`, atribut inline, `_compute_display_name`, `aggregator`, dan sebagainya.
- Koreksi: `models.Constraint` dan `odoo.fields.Domain` adalah fitur Odoo 19 (sebelumnya tertulis 18 dan 17).
- Nama module studi kasus diseragamkan menjadi `library_management`.
- Perbaikan banyak bug pada contoh kode (lihat laporan revisi).
- `verify.sh` diperluas.
- Topik baru: operasi recordset (Bab 4), query aman `odoo.tools.SQL` (Bab 15), record rule per-company dan inter-company (Bab 14), `freeze_time` dan CI/CD (Bab 17), profiling dan `assertQueryCount` (Bab 18), cache ORM, monitoring, install tanpa Docker, dan migrasi antar versi (Bab 20).

### Version 2.1 (2026-10-08)
- Tambah bab i18n & Multi-Company; klarifikasi Bab External API (Odoo tidak punya REST API bawaan); perbaikan `verify.sh`.

### Version 2.0 (2026-05-19)
- Tambah bab Database Views & Filtering dan Contoh Praktis Sales Analytics.

### Version 1.0 (2024-01-01)
- 18 bab fundamental hingga advanced dan studi kasus Library Management System.

---

*Last updated: 2026-11-24 | Version: 3.0*
