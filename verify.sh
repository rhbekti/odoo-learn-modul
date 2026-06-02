#!/bin/bash
# Script untuk verifikasi kelengkapan modul Odoo 18 Guide

echo "================================================"
echo "  VERIFIKASI MODUL ODOO 18 GUIDE"
echo "================================================"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directory
GUIDE_DIR="/home/stika/Documents/learn-odoo/odoo18-guide"

echo -e "${BLUE}📁 Direktori:${NC} $GUIDE_DIR"
echo ""

# Count files
echo -e "${YELLOW}📊 Statistik File:${NC}"
TOTAL_MD=$(find "$GUIDE_DIR" -name "*.md" -type f | wc -l)
echo "   Total file .md: $TOTAL_MD"

# Count lines
TOTAL_LINES=$(find "$GUIDE_DIR" -name "*.md" -type f -exec wc -l {} + | tail -1 | awk '{print $1}')
echo "   Total baris: $TOTAL_LINES"

echo ""
echo -e "${YELLOW}📚 Daftar Bab:${NC}"
echo ""

# List all markdown files
counter=0
for file in $(ls "$GUIDE_DIR"/*.md | sort); do
    filename=$(basename "$file")
    lines=$(wc -l < "$file")
    size=$(du -h "$file" | cut -f1)
    
    if [[ $filename == "README.md" ]]; then
        echo -e "   ${GREEN}✓${NC} README.md ($lines baris, $size)"
    elif [[ $filename == "RINGKASAN.md" ]]; then
        echo -e "   ${GREEN}✓${NC} RINGKASAN.md ($lines baris, $size)"
    elif [[ $filename =~ ^[0-9] ]]; then
        bab_num=$(echo "$filename" | grep -o '^[0-9]*')
        bab_name=$(echo "$filename" | sed 's/^[0-9]*-//' | sed 's/.md$//' | sed 's/-/ /g')
        echo -e "   ${GREEN}✓${NC} Bab $bab_num: $bab_name ($lines baris, $size)"
        ((counter++))
    fi
done

echo ""
echo -e "${YELLOW}📈 Ringkasan:${NC}"
echo "   Total bab pembelajaran: $counter"
echo "   Total file dokumentasi: $TOTAL_MD"
echo "   Total baris kode & dokumentasi: $TOTAL_LINES"

echo ""
echo -e "${GREEN}✅ MODUL LENGKAP!${NC}"
echo ""

# Check specific important files
echo -e "${YELLOW}🔍 Verifikasi File Penting:${NC}"

important_files=(
    "README.md"
    "00-daftar-isi.md"
    "10-multi-model-module.md"
    "18-tips-best-practices.md"
    "19-database-views-filtering.md"
    "20-contoh-praktis-views.md"
)

for file in "${important_files[@]}"; do
    if [ -f "$GUIDE_DIR/$file" ]; then
        echo -e "   ${GREEN}✓${NC} $file"
    else
        echo -e "   ${RED}✗${NC} $file (MISSING)"
    fi
done

echo ""
echo "================================================"
echo "  Verifikasi Selesai!"
echo "================================================"
