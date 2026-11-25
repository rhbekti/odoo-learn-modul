#!/bin/bash
# Verifikasi kelengkapan & konsistensi materi Odoo 18 Guide (dengan catatan Odoo 19)
# Pemakaian: ./verify.sh [direktori]

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

GUIDE_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
ERRORS=0

echo "================================================"
echo "  VERIFIKASI MATERI ODOO 18 GUIDE"
echo "================================================"
echo -e "${BLUE}Direktori:${NC} $GUIDE_DIR"
echo ""

# 1. Daftar bab yang diharapkan (urutan jalur belajar)
chapters=(
    "01-docker-setup.md"
    "02-install-config.md"
    "03-module-structure.md"
    "04-models-orm.md"
    "05-views-xml.md"
    "06-security-access-rights.md"
    "07-data-files-sequences.md"
    "08-inheritance-override.md"
    "09-wizards-dialogs.md"
    "10-multi-model-module.md"
    "11-qweb-reports.md"
    "12-controllers-routing.md"
    "13-owl-javascript.md"
    "14-i18n-multi-company.md"
    "15-database-views-filtering.md"
    "16-contoh-praktis-views.md"
    "17-testing.md"
    "18-debugging-troubleshooting.md"
    "19-external-api.md"
    "20-deployment-performance.md"
    "21-tips-best-practices.md"
)
support=("README.md" "00-daftar-isi.md" "RINGKASAN.md")

echo -e "${YELLOW}Daftar bab:${NC}"
total_lines=0
for file in "${chapters[@]}"; do
    path="$GUIDE_DIR/$file"
    if [ ! -f "$path" ]; then
        echo -e "   ${RED}✗${NC} $file (TIDAK ADA)"
        ((ERRORS++))
        continue
    fi
    lines=$(wc -l < "$path")
    total_lines=$((total_lines + lines))
    num=$(echo "$file" | grep -o '^[0-9]*' | sed 's/^0*//')
    title=$(head -1 "$path")
    # Judul harus "# Bab N:" sesuai nomor file
    if [[ "$title" =~ ^"# Bab ${num}:" ]]; then
        status="${GREEN}✓${NC}"
    else
        status="${RED}✗${NC}"
        ((ERRORS++))
    fi
    printf "   %b %-36s %5s baris  | %s\n" "$status" "$file" "$lines" "$title"
done

echo ""
echo -e "${YELLOW}Berkas pendukung:${NC}"
for file in "${support[@]}"; do
    if [ -f "$GUIDE_DIR/$file" ]; then
        echo -e "   ${GREEN}✓${NC} $file"
    else
        echo -e "   ${RED}✗${NC} $file (TIDAK ADA)"
        ((ERRORS++))
    fi
done

# 2. Tautan antar-berkas (.md) harus menunjuk ke berkas yang ada
echo ""
echo -e "${YELLOW}Tautan antar-berkas:${NC}"
broken=0
while IFS= read -r link; do
    target="${link%%#*}"
    if [ ! -f "$GUIDE_DIR/$target" ]; then
        echo -e "   ${RED}✗${NC} tautan rusak: $link"
        ((broken++))
    fi
done < <(grep -h -o -E '\]\([0-9A-Za-z_-]+\.md(#[^)]*)?\)' "$GUIDE_DIR"/*.md | sed -E 's/^\]\(//; s/\)$//' | sort -u)
if [ "$broken" -eq 0 ]; then
    echo -e "   ${GREEN}✓${NC} semua tautan valid"
else
    ERRORS=$((ERRORS + broken))
fi

# 3. Sintaks usang (Odoo <= 16) yang tidak boleh muncul di contoh kode.
#    Baris penjelasan perubahan versi (mengandung kata kunci di bawah) dikecualikan.
echo ""
echo -e "${YELLOW}Sintaks usang di contoh kode:${NC}"
legacy=$(grep -n -E '<tree[ >]|</tree>|attrs="|states="|name_get\(|oe_chatter|kanban-box|numbercall|SavepointCase|t-raw|@api\.multi' \
    "$GUIDE_DIR"/[0-2][0-9]-*.md 2>/dev/null \
    | grep -v -i -E 'dulu|lama|deprecated|sebelum|usang|dihapus|diganti|ganti|jangan|hindari|tidak|bukan|≤|<=|Odoo ?(<|≤)|\|' )
if [ -z "$legacy" ]; then
    echo -e "   ${GREEN}✓${NC} tidak ditemukan"
else
    echo "$legacy" | head -20
    echo -e "   ${YELLOW}!${NC} periksa baris di atas (mungkin penjelasan, mungkin sisa sintaks lama)"
fi

# 4. Konsistensi nama module studi kasus
echo ""
echo -e "${YELLOW}Konsistensi nama module:${NC}"
if grep -q "library_app" "$GUIDE_DIR"/[0-2][0-9]-*.md 2>/dev/null; then
    echo -e "   ${RED}✗${NC} masih ada 'library_app' (seharusnya library_management):"
    grep -n "library_app" "$GUIDE_DIR"/[0-2][0-9]-*.md | head -5
    ((ERRORS++))
else
    echo -e "   ${GREEN}✓${NC} 'library_management' dipakai konsisten"
fi

# 5. Setiap bab harus punya bagian wajib
echo ""
echo -e "${YELLOW}Bagian wajib per bab:${NC}"
missing=0
for file in "${chapters[@]}"; do
    path="$GUIDE_DIR/$file"
    [ -f "$path" ] || continue
    for section in "## Tujuan Belajar" "## Ringkasan" "## Latihan"; do
        if ! grep -q "^$section" "$path"; then
            echo -e "   ${RED}✗${NC} $file: tidak ada '$section'"
            ((missing++))
        fi
    done
done
if [ "$missing" -eq 0 ]; then
    echo -e "   ${GREEN}✓${NC} semua bab lengkap"
else
    ERRORS=$((ERRORS + missing))
fi

echo ""
echo "================================================"
echo "  Total baris bab: $total_lines"
if [ "$ERRORS" -eq 0 ]; then
    echo -e "  ${GREEN}Verifikasi selesai: tidak ada masalah${NC}"
else
    echo -e "  ${RED}Verifikasi selesai: $ERRORS masalah ditemukan${NC}"
fi
echo "================================================"
exit $((ERRORS > 0 ? 1 : 0))
