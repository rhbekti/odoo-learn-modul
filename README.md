# README - Panduan Lengkap Odoo 18 Development

![Odoo 18](https://img.shields.io/badge/Odoo-18.0-714B67?style=for-the-badge&logo=odoo)
![Python](https://img.shields.io/badge/Python-3.10+-3776AB?style=for-the-badge&logo=python&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?style=for-the-badge&logo=postgresql&logoColor=white)
![License](https://img.shields.io/badge/License-Open%20Source-green?style=for-the-badge)

Panduan komprehensif untuk belajar pengembangan Odoo 18 dari dasar hingga advanced, dalam Bahasa Indonesia.

---

## 📚 Daftar Isi Lengkap

### 🎯 Bagian 1: Fundamental (Bab 1-7)

| Bab | Topik | Deskripsi |
|-----|-------|-----------|
| [00](00-daftar-isi.md) | **Daftar Isi** | Navigasi lengkap semua bab |
| [01](01-docker-setup.md) | **Docker Setup** | Setup environment dengan Docker & Docker Compose |
| [02](02-install-config.md) | **Install & Config** | Konfigurasi Odoo, odoo.conf, environment variables |
| [03](03-module-structure.md) | **Struktur Module** | Struktur direktori, __manifest__.py, best practices |
| [04](04-models-orm.md) | **Models & ORM** | Field types, decorators, CRUD, domain filters |
| [05](05-views-xml.md) | **Views XML** | Form, tree, search, kanban, calendar, pivot, graph |
| [06](06-controllers-routing.md) | **Controllers** | HTTP/JSON endpoints, routing, authentication |
| [07](07-security-access-rights.md) | **Security** | Access rights, record rules, groups, permissions |

### 🚀 Bagian 2: Advanced Features (Bab 8-13)

| Bab | Topik | Deskripsi |
|-----|-------|-----------|
| [08](08-wizards-dialogs.md) | **Wizards** | TransientModel, dialog forms, multi-step wizards |
| [09](09-inheritance-override.md) | **Inheritance** | 3 jenis inheritance, override methods, view inheritance |
| [10](10-multi-model-module.md) | **Multi-Model** | Studi kasus Library Management System lengkap |
| [11](11-data-files-sequences.md) | **Data & Sequences** | XML/CSV data, sequences, cron jobs, email templates |
| [12](12-qweb-reports.md) | **QWeb Reports** | PDF reports, custom templates, paper formats |
| [13](13-owl-javascript.md) | **OWL JavaScript** | OWL 2.x components, frontend development |

### 💼 Bagian 3: Professional Development (Bab 14-21)

| Bab | Topik | Deskripsi |
|-----|-------|-----------|
| [14](14-testing.md) | **Testing** | Unit tests, integration tests, test coverage |
| [15](15-deployment-performance.md) | **Deployment** | Production setup, Nginx, SSL, performance tuning |
| [16](16-debugging-troubleshooting.md) | **Debugging** | Developer mode, Odoo shell, troubleshooting |
| [17](17-external-api.md) | **External API** | XML-RPC, JSON-RPC, custom REST-style endpoint |
| [18](18-tips-best-practices.md) | **Best Practices** | Patterns, anti-patterns, naming conventions |
| [19](19-database-views-filtering.md) | **Database Views** | SQL views, materialized views, filtering models |
| [20](20-contoh-praktis-views.md) | **Contoh Praktis** | Sales analytics dashboard lengkap |
| [21](21-i18n-multi-company.md) | **i18n & Multi-Company** ⭐ | Translasi (`.po`), `translate=True`, company rules |

**⭐ = Bab baru yang ditambahkan**

---

## 🎓 Untuk Siapa Panduan Ini?

### ✅ Pemula
- Belum pernah coding Odoo
- Ingin belajar dari nol
- Butuh panduan step-by-step

**Mulai dari:** Bab 1 → Bab 7 (Fundamental)

### ✅ Developer Berpengalaman
- Sudah familiar dengan Python/PostgreSQL
- Ingin migrasi ke Odoo 18
- Butuh reference cepat

**Langsung ke:** Bab yang relevan atau Bab 18 (Best Practices)

### ✅ Tim Development
- Butuh coding standard
- Perlu setup CI/CD
- Ingin optimize performance

**Focus pada:** Bab 14 (Testing), Bab 15 (Deployment), Bab 18 (Best Practices)

---

## 🚀 Quick Start

### 1. Setup Environment

```bash
# Clone atau download panduan ini
cd odoo18-guide

# Buat docker-compose.yml (lihat Bab 1)
docker compose up -d

# Akses Odoo
# http://localhost:8069
```

### 2. Buat Module Pertama

```bash
# Struktur module sederhana
mkdir -p addons/my_module
cd addons/my_module

# Buat file-file dasar
touch __init__.py __manifest__.py
mkdir models views security
```

### 3. Ikuti Studi Kasus

Panduan ini menggunakan **Library Management System** sebagai contoh praktis:
- Multiple models dengan relasi kompleks
- State machine (draft → active → returned)
- Wizards, reports, dan automated actions
- Security & access rights
- External API integration

**Lihat:** Bab 10 (Multi-Model Module)

---

## 📊 Statistik Panduan

```
📁 Total Bab: 22 (termasuk daftar isi)
📄 Total Halaman: 8,200+ baris dokumentasi
💻 Contoh Code: 200+ snippets
🎯 Studi Kasus: Library Management + Sales Analytics
🌐 Bahasa: Indonesia
```

---

## 🔥 Fitur Unggulan

### ✨ Odoo 18 Specific
- Syntax terbaru (invisible="expression" bukan attrs)
- OWL 2.x components
- Modern best practices
- Performance optimization

### 📖 Pembelajaran Terstruktur
- Dari basic ke advanced
- Contoh praktis di setiap bab
- Studi kasus lengkap
- Troubleshooting tips

### 🛠️ Production Ready
- Deployment guide
- Security best practices
- Performance tuning
- Testing strategies

### 🇮🇩 Bahasa Indonesia
- Mudah dipahami
- Istilah teknis dijelaskan
- Contoh relevan dengan konteks lokal

---

## 💡 Topik Khusus yang Dicakup

### Models & Data
- ✅ Field types lengkap (Char, Integer, Many2one, dll)
- ✅ Computed fields & dependencies
- ✅ Onchange & constraints
- ✅ SQL Views & Materialized Views ⭐
- ✅ Filtering inherited models ⭐
- ✅ Parent-child hierarchy
- ✅ Multi-company & multi-currency

### Views & UI
- ✅ Form, tree, search, kanban views
- ✅ Calendar, pivot, graph views
- ✅ Widgets (statusbar, progressbar, badge, dll)
- ✅ Conditional visibility (Odoo 18 syntax)
- ✅ Smart buttons
- ✅ Chatter integration

### Business Logic
- ✅ State machine pattern
- ✅ Header-line pattern
- ✅ Wizards & transient models
- ✅ Automated actions (cron)
- ✅ Email notifications
- ✅ Scheduled tasks

### Advanced Topics
- ✅ 3 jenis inheritance
- ✅ OWL JavaScript components
- ✅ QWeb reports & PDF
- ✅ External API (XML-RPC, JSON-RPC, custom REST-style endpoint)
- ✅ Database views untuk analytics
- ✅ Performance optimization
- ✅ Testing (unit, integration, HTTP)
- ✅ Internationalization (i18n) & translasi ⭐
- ✅ Multi-company (record rules, company-dependent fields) ⭐

### DevOps & Production
- ✅ Docker setup
- ✅ Nginx reverse proxy
- ✅ SSL/TLS configuration
- ✅ Multi-worker setup
- ✅ Database optimization
- ✅ Monitoring & logging

---

## 🎯 Roadmap Belajar

### Week 1-2: Fundamental
```
Day 1-2:  Bab 1-3  (Setup & Module Structure)
Day 3-5:  Bab 4-5  (Models & Views)
Day 6-7:  Bab 6-7  (Controllers & Security)
```

### Week 3-4: Advanced
```
Day 8-9:   Bab 8-9   (Wizards & Inheritance)
Day 10-11: Bab 10    (Multi-Model Module - Practice!)
Day 12-13: Bab 11-12 (Data Files & Reports)
Day 14:    Bab 13    (OWL JavaScript)
```

### Week 5-6: Professional
```
Day 15-16: Bab 14-15 (Testing & Deployment)
Day 17-18: Bab 16-17 (Debugging & API)
Day 19-20: Bab 18-20 (Best Practices & Database Views)
Day 21:    Bab 21 (i18n & Multi-Company)
Day 22:    Review & Build Your Own Module!
```

---

## 🛠️ Tools & Technologies

| Tool | Version | Purpose |
|------|---------|---------|
| Odoo | 18.0 | ERP Framework |
| Python | 3.10+ | Backend Language |
| PostgreSQL | 16 | Database |
| Docker | 24.0+ | Containerization |
| OWL | 2.x | Frontend Framework |
| wkhtmltopdf | 0.12.6 | PDF Generation |
| Nginx | Latest | Reverse Proxy |

---

## 📝 Contoh Module Lengkap

### Library Management System
Studi kasus utama dengan fitur:
- ✅ Book management (categories, copies)
- ✅ Member management
- ✅ Loan system (header-line pattern)
- ✅ Fine calculation
- ✅ State machine (draft → active → returned)
- ✅ Automated reminders
- ✅ Reports (loan receipt, member card)
- ✅ Dashboard & analytics

**Lihat:** Bab 10

### Sales Analytics Dashboard ⭐
Contoh baru dengan:
- ✅ SQL Views untuk reporting
- ✅ Materialized Views untuk performance
- ✅ VIP customer segmentation
- ✅ Product performance analytics
- ✅ Pivot & graph views
- ✅ Auto-refresh dengan cron

**Lihat:** Bab 19-20

---

## 🤝 Kontribusi

Panduan ini bersifat open source. Kontribusi sangat diterima!

### Cara Berkontribusi
1. Fork repository ini
2. Buat branch baru (`git checkout -b feature/improvement`)
3. Commit perubahan (`git commit -m 'Add some improvement'`)
4. Push ke branch (`git push origin feature/improvement`)
5. Buat Pull Request

### Yang Bisa Dikontribusi
- ✏️ Perbaikan typo atau grammar
- 📚 Tambahan contoh code
- 🐛 Perbaikan error di code
- 📖 Penjelasan lebih detail
- 🆕 Topik baru yang relevan

---

## 📞 Support & Community

### Butuh Bantuan?
- 📧 Email: [your-email@example.com]
- 💬 Telegram: [Odoo Indonesia Community]
- 🌐 Forum: [Odoo Forum Indonesia]

### Resources Tambahan
- [Odoo Official Documentation](https://www.odoo.com/documentation/18.0/)
- [Odoo GitHub](https://github.com/odoo/odoo)
- [Odoo Apps Store](https://apps.odoo.com/)

---

## ⚖️ Lisensi

Dokumentasi ini bersifat **open source** dan bebas digunakan untuk:
- ✅ Pembelajaran pribadi
- ✅ Training internal perusahaan
- ✅ Referensi project
- ✅ Sharing dengan komunitas

**Tidak diperbolehkan:**
- ❌ Dijual kembali tanpa izin
- ❌ Diklaim sebagai karya sendiri

---

## 🙏 Acknowledgments

Terima kasih kepada:
- Odoo SA untuk framework yang luar biasa
- Komunitas Odoo Indonesia
- Semua kontributor panduan ini

---

## 📈 Changelog

### Version 2.1 (2026-10-08) ⭐
- ✅ Tambah Bab 21: Internationalization (i18n) & Multi-Company
- ✅ Perbaikan: Bab 17 — klarifikasi bahwa Odoo tidak punya REST API bawaan
- ✅ Perbaikan: `verify.sh` (path hardcode & bug variabel warna)

### Version 2.0 (2026-05-19)
- ✅ Tambah Bab 19: Database Views & Filtering
- ✅ Tambah Bab 20: Contoh Praktis Sales Analytics
- ✅ Update best practices untuk Odoo 18
- ✅ Tambah materialized views examples
- ✅ Tambah filtering inherited models techniques

### Version 1.0 (2024-01-01)
- ✅ 18 bab fundamental hingga advanced
- ✅ Studi kasus Library Management System
- ✅ Dokumentasi lengkap dalam Bahasa Indonesia

---

## 🎯 Next Steps

Setelah menyelesaikan panduan ini, Anda bisa:

1. **Build Your Own Module**
   - Identifikasi kebutuhan bisnis
   - Design database schema
   - Implement dengan best practices

2. **Contribute to Odoo**
   - Join Odoo Community Association (OCA)
   - Contribute ke open source modules
   - Share knowledge dengan komunitas

3. **Become Odoo Expert**
   - Ambil sertifikasi Odoo official
   - Join Odoo partner program
   - Build commercial modules

---

## 🌟 Star This Repository!

Jika panduan ini membantu Anda, jangan lupa beri ⭐ star!

---

**Happy Coding! 🚀**

*Last updated: 2026-10-08*
*Version: 2.1*
