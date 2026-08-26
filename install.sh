#!/usr/bin/env bash

# ==========================================
# Installer untuk Symfony Smart Project Generator
# ------------------------------------------
# Dipakai lewat:
#   curl -fsSL https://raw.githubusercontent.com/kematjaya0/symfony-setup/main/install.sh | bash
#
# symfony.bash BUKAN file tunggal — dia butuh folder sibling "symfony/"
# (template Docker/Symfony, ratusan KB) yang tidak mungkin ikut lewat pipe
# `curl | bash`. Jadi installer ini hanya bertugas: clone/update seluruh
# repo ke cache lokal, pasang command pendek "symfony-new" di PATH, lalu
# exec symfony.bash yang asli dari disk.
# ==========================================

set -Eeuo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

REPO_URL="https://github.com/kematjaya0/symfony-setup.git"
INSTALL_DIR="${SYMFONY_GEN_HOME:-$HOME/.local/share/symfony-generator}"
BIN_DIR="${SYMFONY_GEN_BIN_DIR:-$HOME/.local/bin}"

if ! command -v git >/dev/null 2>&1; then
    echo -e "${RED}Error: git belum terinstal. Install git dulu, lalu jalankan lagi.${NC}" >&2
    exit 1
fi

echo -e "${BLUE}==> Mengambil/memperbarui Symfony Smart Project Generator...${NC}"
if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" pull --ff-only --quiet
else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone --depth 1 --quiet "$REPO_URL" "$INSTALL_DIR"
fi

if [ ! -f "$INSTALL_DIR/symfony.bash" ]; then
    echo -e "${RED}Error: symfony.bash tidak ditemukan di $INSTALL_DIR setelah clone.${NC}" >&2
    exit 1
fi

# Command pendek supaya lain kali tidak perlu curl lagi — cukup ketik
# "symfony-new". Wrapper ini selalu git pull dulu (best-effort) biar versi
# generator tetap terbaru tiap dipakai.
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/symfony-new" <<WRAPPER
#!/usr/bin/env bash
set -Eeuo pipefail
if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" pull --ff-only --quiet || true
fi
exec bash "$INSTALL_DIR/symfony.bash" "\$@"
WRAPPER
chmod +x "$BIN_DIR/symfony-new"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo -e "${YELLOW}⚠️  $BIN_DIR belum ada di PATH. Tambahkan baris berikut ke ~/.bashrc atau ~/.zshrc:${NC}"
        echo -e "    export PATH=\"$BIN_DIR:\$PATH\""
        ;;
esac

echo -e "${GREEN}✅ Terpasang di $INSTALL_DIR${NC}"
echo -e "${GREEN}   Lain kali cukup jalankan: symfony-new${NC}\n"

# curl | bash membuat stdin script INI adalah pipe dari curl (sudah habis
# terbaca), bukan terminal. symfony.bash penuh `read -p` interaktif, jadi
# stdin WAJIB di-reattach eksplisit ke /dev/tty sebelum exec — kalau tidak,
# semua prompt langsung EOF/gagal tanpa sempat nanya apa pun ke user.
if ( : < /dev/tty ) 2>/dev/null; then
    exec bash "$INSTALL_DIR/symfony.bash" "$@" < /dev/tty
else
    echo -e "${RED}Error: tidak ada TTY interaktif untuk mode prompt.${NC}" >&2
    echo -e "${YELLOW}Jalankan manual: bash $INSTALL_DIR/symfony.bash${NC}" >&2
    exit 1
fi
