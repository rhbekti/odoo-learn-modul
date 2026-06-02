# Panduan Lengkap Odoo 18 Development

## Daftar Isi

### Bagian 1: Setup & Fundamental (Bab 1-7)

1. **[Docker Setup](01-docker-setup.md)**
   - Setup Docker & Docker Compose
   - Konfigurasi container Odoo 18
   - Tips development dengan Docker

2. **[Install & Konfigurasi](02-install-config.md)**
   - Konfigurasi odoo.conf
   - Environment variables
   - Database management
   - CLI commands

3. **[Struktur Module](03-module-structure.md)**
   - Struktur direktori module
   - __manifest__.py
   - __init__.py
   - Best practices naming

4. **[Models & ORM](04-models-orm.md)**
   - Field types (Char, Integer, Many2one, dll)
   - API decorators (@api.depends, @api.onchange)
   - CRUD operations
   - Domain filters
   - Lifecycle hooks

5. **[Views XML](05-views-xml.md)**
   - Form view
   - Tree view (list)
   - Search view
   - Kanban view
   - Calendar, Pivot, Graph views
   - Widgets

6. **[Controllers & Routing](06-controllers-routing.md)**
   - HTTP controllers
   - JSON-RPC endpoints
   - Authentication
   - Request/Response handling
   - Website integration

7. **[Security & Access Rights](07-security-access-rights.md)**
   - ir.model.access.csv
   - Record rules
   - Groups & permissions
   - Field-level security

---

### Bagian 2: Advanced Features (Bab 8-13)

8. **[Wizards & Dialogs](08-wizards-dialogs.md)**
   - TransientModel
   - Wizard views
   - Multi-step wizards
   - Context & default values

9. **[Inheritance & Override](09-inheritance-override.md)**
   - Class inheritance (extension)
   - Prototype inheritance
   - Delegation inheritance (_inherits)
   - Override methods dengan super()
   - View inheritance (xpath)

10. **[Multi-Model Module](10-multi-model-module.md)**
    - Studi kasus: Library Management System
    - Relasi antar model (Many2one, One2many, Many2many)
    - Header-line pattern
    - Parent-child hierarchy
    - Computed fields lintas model

11. **[Data Files & Sequences](11-data-files-sequences.md)**
    - XML data files
    - CSV data files
    - noupdate attribute
    - Sequences (auto-numbering)
    - Automated actions (cron jobs)
    - Email templates

12. **[QWeb Reports](12-qweb-reports.md)**
    - Report actions
    - QWeb templates
    - PDF generation
    - Custom paper formats
    - Report parser
    - Dynamic reports

13. **[OWL JavaScript](13-owl-javascript.md)**
    - OWL 2.x components
    - Component lifecycle
    - State management (useState)
    - Services (useService)
    - Custom widgets
    - Backend vs Frontend assets

---

### Bagian 3: Professional Development (Bab 14-19)

14. **[Testing](14-testing.md)**
    - TransactionCase
    - SingleTransactionCase
    - HttpCase
    - Form utility (test onchange)
    - Test coverage
    - Mock & patch

15. **[Deployment & Performance](15-deployment-performance.md)**
    - Production docker-compose
    - Nginx reverse proxy
    - SSL/TLS configuration
    - Workers & multi-processing
    - Database optimization
    - Caching strategies
    - Monitoring & logging

16. **[Debugging & Troubleshooting](16-debugging-troubleshooting.md)**
    - Developer mode
    - Odoo shell
    - Logging & breakpoints
    - PostgreSQL queries
    - Common errors & solutions
    - Performance profiling

17. **[External API](17-external-api.md)**
    - XML-RPC (Python, PHP, Node.js)
    - JSON-RPC
    - REST API (Odoo 18)
    - Authentication & security
    - Rate limiting
    - Webhooks

18. **[Tips & Best Practices](18-tips-best-practices.md)**
    - Naming conventions
    - Common patterns (state machine, header-line, smart buttons)
    - Anti-patterns (N+1 query, sudo abuse)
    - Recordset operations
    - Odoo 18 changes
    - Deployment checklist

19. **[Database Views & Filtering](19-database-views-filtering.md)** ⭐ NEW
    - SQL Views (read-only reporting)
    - Materialized Views (cached data)
    - Filtering inherited models
    - Record rules untuk filtering
    - Performance optimization
    - Best practices

---

## Cara Menggunakan Panduan Ini

### Untuk Pemula
Ikuti urutan dari Bab 1-7 untuk memahami fundamental Odoo development.

### Untuk Developer Berpengalaman
Langsung ke bab yang relevan dengan kebutuhan Anda:
- **Butuh reporting?** → Bab 12 (QWeb Reports) & Bab 19 (Database Views)
- **Butuh API?** → Bab 17 (External API)
- **Butuh frontend?** → Bab 13 (OWL JavaScript)
- **Butuh optimize performance?** → Bab 15 (Deployment) & Bab 19 (Views)

### Untuk Tim
Gunakan Bab 18 (Best Practices) sebagai coding standard dan Bab 14 (Testing) untuk quality assurance.

---

## Studi Kasus Lengkap

Panduan ini menggunakan **Library Management System** sebagai contoh praktis yang mencakup:

- ✅ Multiple models dengan relasi kompleks
- ✅ State machine (draft → active → returned)
- ✅ Header-line pattern (loan → loan lines)
- ✅ Parent-child hierarchy (book categories)
- ✅ Computed fields & aggregations
- ✅ Wizards & automated actions
- ✅ Reports & email notifications
- ✅ Security & access rights
- ✅ External API integration
- ✅ Database views untuk analytics

---

## Teknologi yang Digunakan

- **Odoo**: 18.0
- **Python**: 3.10+
- **PostgreSQL**: 16
- **Docker**: 24.0+
- **OWL**: 2.x
- **wkhtmltopdf**: 0.12.6

---

## Kontribusi & Feedback

Jika menemukan kesalahan atau ingin menambahkan materi:
1. Buat issue di repository
2. Submit pull request dengan perbaikan
3. Diskusi di forum komunitas Odoo Indonesia

---

## Lisensi

Dokumentasi ini bersifat open source dan bebas digunakan untuk pembelajaran.

---

**Selamat Belajar Odoo 18! 🚀**

*Last updated: 2026-05-19*
