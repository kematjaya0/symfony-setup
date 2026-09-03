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

# Git Bash/MSYS di Windows: cmd.exe & PowerShell tidak paham file tanpa
# ekstensi (shebang bash) dan tidak pernah baca PATH dari ~/.bashrc, jadi
# butuh shim .cmd terpisah + registrasi ke User PATH Windows asli.
IS_WINDOWS=0
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
esac

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
# "symfony-new". Subcommand:
#   symfony-new [create]  -> generate project (default kalau tanpa argumen).
#                             Tetap git pull dulu (best-effort, diam-diam,
#                             SAMA seperti sebelumnya) biar generator selalu
#                             versi terbaru tanpa user perlu mikirin update.
#   symfony-new update    -> update EKSPLISIT, TIDAK diam-diam — sukses/gagal/
#                             sudah-terbaru semuanya dilaporkan jelas, plus
#                             exit code jelas (berguna dipakai di script lain).
#   symfony-new uninstall -> hapus clone repo + command ini sendiri (dengan
#                             konfirmasi, kecuali -y/--yes). Project Symfony
#                             yang SUDAH di-generate tidak disentuh sama sekali.
#   symfony-new --help    -> bantuan.
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/symfony-new" <<WRAPPER
#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="$INSTALL_DIR"
SELF="$BIN_DIR/symfony-new"

show_help() {
    cat <<'HELP'
Usage: symfony-new [create|update|uninstall|--help]

  create      Generate project Symfony baru (default kalau dipanggil tanpa argumen)
  update      Update generator ini ke versi terbaru (git pull), lalu berhenti
              -- TIDAK ikut menjalankan generator
  uninstall   Hapus clone repo generator + command "symfony-new" ini sendiri.
              Project Symfony yang SUDAH di-generate TIDAK disentuh.
              Pakai -y/--yes untuk skip konfirmasi.
  --help      Tampilkan bantuan ini

Argumen tambahan setelah "create" diteruskan apa adanya ke symfony.bash.
HELP
}

update_generator() {
    if [ ! -d "\$INSTALL_DIR/.git" ]; then
        echo "Error: \$INSTALL_DIR bukan git repo, tidak bisa update." >&2
        exit 1
    fi
    echo "==> Mengecek update di \$INSTALL_DIR..."
    local before after
    before="\$(git -C "\$INSTALL_DIR" rev-parse HEAD)"
    if ! git -C "\$INSTALL_DIR" pull --ff-only; then
        echo "❌ Gagal update (cek koneksi, atau ada perubahan lokal yang bentrok)." >&2
        exit 1
    fi
    after="\$(git -C "\$INSTALL_DIR" rev-parse HEAD)"
    if [ "\$before" = "\$after" ]; then
        echo "✅ Sudah versi terbaru (\${before:0:7})."
    else
        echo "✅ Terupdate: \${before:0:7} -> \${after:0:7}"
    fi
}

uninstall_generator() {
    local skip_confirm=0
    for arg in "\$@"; do
        case "\$arg" in
            -y|--yes) skip_confirm=1 ;;
        esac
    done

    echo "Ini akan menghapus:"
    echo "  - \$INSTALL_DIR (clone repo generator)"
    echo "  - \$SELF (command \"symfony-new\" ini sendiri)"
    echo ""
    echo "Project Symfony yang SUDAH di-generate sebelumnya TIDAK akan disentuh."
    echo "(Cache Composer di ~/.cache/symfony-generator/composer juga TIDAK ikut"
    echo "dihapus — hapus manual kalau perlu, dipakai bersama lintas-project.)"
    echo ""

    if [ "\$skip_confirm" -ne 1 ]; then
        read -r -p "Lanjutkan? (y/N) " confirm
        case "\$confirm" in
            y|Y|yes|YES) ;;
            *)
                echo "Dibatalkan."
                exit 0
                ;;
        esac
    fi

    rm -rf "\$INSTALL_DIR"
    echo "✅ Terhapus: \$INSTALL_DIR"

    echo "✅ Terhapus: \$SELF"
    echo "symfony-new sudah tidak terpasang. Sampai jumpa!"
    rm -f "\$SELF"
}

CMD="\${1:-create}"
case "\$CMD" in
    create)
        shift || true
        # Best-effort, diam-diam (sama seperti perilaku lama) — kalau mau
        # tahu jelas berhasil/gagal update, pakai "symfony-new update".
        if [ -d "\$INSTALL_DIR/.git" ]; then
            git -C "\$INSTALL_DIR" pull --ff-only --quiet || true
        fi
        exec bash "\$INSTALL_DIR/symfony.bash" "\$@"
        ;;
    update)
        update_generator
        ;;
    uninstall)
        shift || true
        uninstall_generator "\$@"
        ;;
    --help|-h|help)
        show_help
        ;;
    *)
        echo "Error: perintah tidak dikenal: \$CMD" >&2
        show_help >&2
        exit 1
        ;;
esac
WRAPPER
chmod +x "$BIN_DIR/symfony-new"

if [ "$IS_WINDOWS" -eq 1 ] && command -v cygpath >/dev/null 2>&1; then
    BASH_EXE_WIN="$(cygpath -w "$(command -v bash)")"
    # symfony-new (tanpa ekstensi) tak pernah dikenali cmd.exe/PowerShell
    # sebagai command; %~dp0 = folder .cmd ini sendiri = $BIN_DIR.
    cat > "$BIN_DIR/symfony-new.cmd" <<CMDWRAPPER
@echo off
"$BASH_EXE_WIN" "%~dp0symfony-new" %*
CMDWRAPPER
    echo -e "${GREEN}✅ symfony-new.cmd dibuat (supaya bisa dipanggil dari cmd.exe/PowerShell juga).${NC}"
fi

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo -e "${YELLOW}⚠️  $BIN_DIR belum ada di PATH. Tambahkan baris berikut ke ~/.bashrc atau ~/.zshrc:${NC}"
        echo -e "    export PATH=\"$BIN_DIR:\$PATH\""
        ;;
esac

if [ "$IS_WINDOWS" -eq 1 ] && command -v cygpath >/dev/null 2>&1 && command -v powershell.exe >/dev/null 2>&1; then
    WIN_BIN_DIR="$(cygpath -w "$BIN_DIR")"
    PS_SCRIPT="$(mktemp --suffix=.ps1 2>/dev/null || echo "${TMPDIR:-/tmp}/symfony-gen-path-$$.ps1")"
    cat > "$PS_SCRIPT" <<PS
\$dir = '$WIN_BIN_DIR'
\$p = [Environment]::GetEnvironmentVariable('Path','User')
if (-not \$p) { \$p = '' }
\$parts = \$p -split ';' | Where-Object { \$_ -ne '' }
if (\$parts -notcontains \$dir) {
    [Environment]::SetEnvironmentVariable('Path', ((\$parts + \$dir) -join ';'), 'User')
    Write-Host "PATH User Windows diperbarui: \$dir ditambahkan."
} else {
    Write-Host "PATH User Windows sudah berisi: \$dir"
}
PS
    echo -e "${BLUE}==> Mendaftarkan $WIN_BIN_DIR ke User PATH Windows (permanen)...${NC}"
    if powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(cygpath -w "$PS_SCRIPT")"; then
        echo -e "${YELLOW}   Buka jendela cmd/PowerShell BARU supaya PATH ter-refresh.${NC}"
    else
        echo -e "${YELLOW}⚠️  Gagal update PATH Windows otomatis. Tambahkan manual lewat 'Edit environment variables for your account': $WIN_BIN_DIR${NC}"
    fi
    rm -f "$PS_SCRIPT"
fi

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
