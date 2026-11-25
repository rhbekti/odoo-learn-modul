# Panduan Lengkap Odoo 18 Development (dengan catatan Odoo 19)

> **Versi materi:** 3.0 | **Target:** Odoo 18 (kode utama) dengan kotak "Beda di Odoo 19" | **Diperbarui:** 2026-11-24

Materi ini dibagi menjadi **5 tahap**. Setiap bab punya format yang sama: tujuan belajar, prasyarat, estimasi waktu, isi, ringkasan, latihan, dan petunjuk bab berikutnya. Ikuti urutan nomor kalau kamu pemula.

---

## Peta Jalur Belajar

| Tahap | Bab | Fokus | Estimasi |
|-------|-----|-------|----------|
| 1. Persiapan | 1–3 | Environment Docker, konfigurasi, struktur module | ± 4 jam |
| 2. Inti Pengembangan | 4–10 | Model, view, security, data, inheritance, wizard, proyek akhir | ± 21 jam |
| 3. Fitur Lanjutan | 11–14 | Report PDF, controller, OWL, i18n & multi-company | ± 13 jam |
| 4. Data & Analitik | 15–16 | SQL view, materialized view, query SQL aman, dashboard | ± 6,5 jam |
| 5. Profesional | 17–21 | Testing & CI/CD, debugging & profiling, API, deployment & migrasi, best practices | ± 16,5 jam |

Total estimasi: ± 61 jam belajar aktif (di luar waktu mengerjakan latihan tambahan).

---

## Tahap 1: Persiapan (Bab 1–3)

| Bab | Topik | Prasyarat | Estimasi |
|-----|-------|-----------|----------|
| [1](01-docker-setup.md) | Docker Setup: compose, volume, perintah harian | Tidak ada | ± 1 jam |
| [2](02-install-config.md) | Install & Konfigurasi: `odoo.conf`, CLI, database | Bab 1 | ± 1,5 jam |
| [3](03-module-structure.md) | Struktur Module: `__manifest__.py`, folder, install & update | Bab 1, 2 | ± 1,5 jam |

## Tahap 2: Inti Pengembangan (Bab 4–10)

| Bab | Topik | Prasyarat | Estimasi |
|-----|-------|-----------|----------|
| [4](04-models-orm.md) | Models & ORM: field, compute, constraint, CRUD, domain, operasi recordset | Bab 3 | ± 3,5 jam |
| [5](05-views-xml.md) | Views XML: form, list, search, kanban, action, menu | Bab 3, 4 | ± 3 jam |
| [6](06-security-access-rights.md) | Security: access rights, group, record rule | Bab 4, 5 | ± 2 jam |
| [7](07-data-files-sequences.md) | Data Files, Sequences & Automated Actions (cron) | Bab 3, 4, 6 | ± 3 jam |
| [8](08-inheritance-override.md) | Inheritance & Override: extension, prototype, delegation, view | Bab 3, 4, 5 | ± 3 jam |
| [9](09-wizards-dialogs.md) | Wizards & Dialogs: TransientModel, multi-step | Bab 4, 5, 6, 8 | ± 2,5 jam |
| [10](10-multi-model-module.md) | **Proyek akhir Tahap 2:** Library Management (6 model) | Bab 3–9 | ± 4 jam |

## Tahap 3: Fitur Lanjutan (Bab 11–14)

| Bab | Topik | Prasyarat | Estimasi |
|-----|-------|-----------|----------|
| [11](11-qweb-reports.md) | QWeb Reports (PDF): template, paper format, parser | Bab 4, 5, 10 | ± 3 jam |
| [12](12-controllers-routing.md) | Controllers & Routing: HTTP, JSON, auth, website | Bab 3, 4, 6, 10, 11 | ± 3 jam |
| [13](13-owl-javascript.md) | OWL & JavaScript: komponen, service, asset | Bab 3, 5, 10, 12 | ± 4 jam |
| [14](14-i18n-multi-company.md) | i18n (`.po`, `translate=True`), Multi-Company, record rule per-company, inter-company | Bab 4, 6, 13 | ± 3 jam |

## Tahap 4: Data & Analitik (Bab 15–16)

| Bab | Topik | Prasyarat | Estimasi |
|-----|-------|-----------|----------|
| [15](15-database-views-filtering.md) | Database Views (SQL & materialized), query aman `odoo.tools.SQL`, filtering inherited model | Bab 4, 5, 6, 10 | ± 3,5 jam |
| [16](16-contoh-praktis-views.md) | Contoh praktis: Sales Analytics Dashboard | Bab 5, 6, 7, 15 | ± 3 jam |

## Tahap 5: Profesional (Bab 17–21)

| Bab | Topik | Prasyarat | Estimasi |
|-----|-------|-----------|----------|
| [17](17-testing.md) | Testing: TransactionCase, HttpCase, Form, tour, `freeze_time`, CI/CD | Bab 4, 6, 10 (Bab 12 untuk test controller) | ± 3,5 jam |
| [18](18-debugging-troubleshooting.md) | Debugging & Troubleshooting: dev mode, shell, log, profiling, error umum | Bab 2, 10, 17 | ± 3 jam |
| [19](19-external-api.md) | External API: XML-RPC & JSON-RPC (+ catatan JSON-2 di Odoo 19) | Bab 4, 10, 12 | ± 2,5 jam |
| [20](20-deployment-performance.md) | Deployment & Performance: Nginx, workers, PostgreSQL, cache ORM, monitoring, install tanpa Docker, migrasi versi | Bab 1, 2, 4, 10 | ± 5 jam |
| [21](21-tips-best-practices.md) | Tips, Best Practices & Checklist (bab penutup) | Bab 4, 5, 6, 8, 10, 15, 20 | ± 2,5 jam |

---

## Berkas Pendukung

- [README.md](README.md): gambaran umum, quick start, dan changelog.
- [RINGKASAN.md](RINGKASAN.md): ringkasan per tahap dan tabel perbedaan versi Odoo 17 / 18 / 19.
- [verify.sh](verify.sh): skrip pengecekan kelengkapan berkas materi.

---

## Cara Menggunakan Panduan Ini

**Pemula:** kerjakan Bab 1 sampai 10 berurutan. Bab 10 adalah proyek akhir Tahap 2; kalau kamu bisa membangun module itu sendiri, fondasimu sudah cukup.

**Developer berpengalaman:** langsung ke bab yang kamu butuhkan.

- Butuh report PDF → Bab 11
- Butuh endpoint HTTP/JSON → Bab 12
- Butuh frontend OWL → Bab 13
- Butuh multi-bahasa atau multi-company → Bab 14
- Butuh laporan/analitik dari SQL → Bab 15 dan 16
- Butuh integrasi dari luar Odoo → Bab 19
- Butuh naik ke production → Bab 20

**Tim:** pakai Bab 21 sebagai standar coding dan checklist, serta Bab 17 untuk quality assurance.

**Migrasi dari Odoo 17 atau lebih lama:** baca [RINGKASAN.md](RINGKASAN.md) bagian tabel perbedaan versi, lalu kotak "Beda di Odoo 19" di tiap bab.

---

## Studi Kasus

Seluruh contoh memakai satu module bernama `library_management` (Library Management System): buku, salinan, anggota, peminjaman (header-line), denda, laporan, dan wizard. Module dimulai kecil di Bab 3 dan dibangun penuh di Bab 10. Bab 15–16 memakai studi kasus kedua, Sales Analytics.

## Teknologi

| Komponen | Versi |
|----------|-------|
| Odoo | 18.0 (catatan 19.0) |
| Python | 3.10+ |
| PostgreSQL | 12+ (Odoo 18), 13+ (Odoo 19) |
| Docker | Compose v2 |
| OWL | 2.x |
| wkhtmltopdf | 0.12.6 |

---

*Last updated: 2026-11-24*
