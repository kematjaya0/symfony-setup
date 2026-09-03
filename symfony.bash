#!/usr/bin/env bash

# ==========================================
# Symfony Smart Project Generator (FrankenPHP Edition)
# ------------------------------------------
# Filosofi: satu-satunya prasyarat di HOST adalah Docker + Docker Compose v2.
# Tidak perlu PHP, Composer, Symfony CLI, atau Node terinstal di mesin lokal.
# Semua proses generate, composer require, migrasi, sampai testing dijalankan
# lewat container. Playwright disediakan lewat Docker profile (default) DAN
# tetap bisa dijalankan native kalau developer punya Node (opsional, lebih
# enak untuk UI mode / debugging).
# ==========================================

set -Eeuo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ==========================================
# Opsi versi Symfony: default install versi TERBARU, kecuali flag "--lts"
# diberikan (mis. `bash symfony.bash --lts`), yang mengunci ke rilis LTS
# terkini. Constraint LTS di bawah perlu di-update manual tiap kali Symfony
# merilis LTS baru (rilis *.4, mis. 6.4, 7.4, dst — lihat symfony.com/releases).
# ==========================================
SYMFONY_LTS=0
for arg in "$@"; do
    case "$arg" in
        --lts)
            SYMFONY_LTS=1
            ;;
    esac
done

SYMFONY_LTS_CONSTRAINT="^7.4"
SYMFONY_LATEST_CONSTRAINT="^8.1"

if [ "$SYMFONY_LTS" -eq 1 ]; then
    SYMFONY_SKELETON_CONSTRAINT="$SYMFONY_LTS_CONSTRAINT"
    SYMFONY_VERSION_LABEL="LTS ($SYMFONY_SKELETON_CONSTRAINT)"
else
    SYMFONY_SKELETON_CONSTRAINT="$SYMFONY_LATEST_CONSTRAINT"
    SYMFONY_VERSION_LABEL="terbaru ($SYMFONY_SKELETON_CONSTRAINT)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/symfony"
COMMON_TEMPLATE_DIR="$TEMPLATE_DIR/common"

# ==========================================
# Cleanup otomatis kalau gagal di tengah jalan — folder project separuh jadi
# DAN container yang sempat "docker compose up -d" dibersihkan, supaya host
# kembali persis seperti sebelum script dijalankan, bukan cuma exit dengan
# pesan error lalu meninggalkan sampah. CLEANUP_ON_FAILURE baru jadi 1
# setelah folder project benar-benar dibuat SENDIRI oleh run ini (lihat
# dekat "mkdir -p $PROJECT_NAME" di bawah) — supaya precondition check di
# awal (Docker belum ada, nama kosong, dst., sebelum apa pun dibuat) tidak
# memicu cleanup yang tidak perlu.
# ==========================================
ORIGINAL_DIR="$PWD"
PROJECT_DIR_ABS=""
CLEANUP_ON_FAILURE=0

cleanup_on_failure() {
    local exit_code=$?
    trap - ERR EXIT INT TERM

    if [ "$exit_code" -eq 0 ]; then
        return
    fi

    if [ "$CLEANUP_ON_FAILURE" -ne 1 ] || [ -z "$PROJECT_DIR_ABS" ] || [ ! -d "$PROJECT_DIR_ABS" ]; then
        exit "$exit_code"
    fi

    echo -e "\n${YELLOW}🧹 Membersihkan hasil setup yang gagal (folder + container)...${NC}"

    # docker compose down (bukan cuma rm -rf folder) supaya container/network/
    # volume bernama yang sempat dibuat "docker compose up -d" ikut hilang —
    # kalau tidak, mereka jadi orphan permanen (compose.yaml-nya sudah lenyap
    # bareng folder, tidak ada cara lain mengenalinya lagi). Image hasil
    # build SENGAJA tidak dihapus (tidak ada --rmi) — biar retry berikutnya
    # masih kena cache layer Docker, filosofinya sama seperti
    # COMPOSER_CACHE_HOST_DIR yang sengaja dipertahankan lintas-run.
    if [ -f "$PROJECT_DIR_ABS/compose.yaml" ]; then
        (cd "$PROJECT_DIR_ABS" && docker compose down -v --remove-orphans) 2>/dev/null || true
    fi

    cd "$ORIGINAL_DIR" 2>/dev/null || true
    rm -rf -- "$PROJECT_DIR_ABS"
    echo -e "${GREEN}✅ Folder '$PROJECT_NAME' dan container terkait sudah dibersihkan — kembali seperti sebelum script dijalankan.${NC}"

    exit "$exit_code"
}

trap cleanup_on_failure EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'echo -e "\n${RED}❌ Terjadi error pada baris $LINENO. Proses dihentikan.${NC}"' ERR

# ==========================================
# Helper: render file template dengan token literal "@@NAME@@" (BUKAN sed,
# BUKAN operator bash "${var//pat/repl}") supaya nilai yang mengandung "&"
# (mis. DATABASE_URL) tidak korup — lihat catatan panjang soal ini di bagian
# generate kredensial di bawah. Sintaks compose-time asli seperti
# "${HTTP_PORT:-8082}" dibiarkan apa adanya di file template karena template
# sekarang file statis biasa, bukan heredoc bash, jadi tidak butuh escaping.
# ==========================================
render_token() {
    local content="$1" token="$2" value="$3" result="" head
    while [[ "$content" == *"$token"* ]]; do
        head="${content%%"$token"*}"
        content="${content#*"$token"}"
        result+="$head$value"
    done
    printf '%s' "$result$content"
}

render_template() {
    # Usage: render_template <template_file> <output_file> [TOKEN VALUE]...
    local template="$1" output="$2"
    shift 2
    local content
    content="$(cat "$template")"
    while [ "$#" -gt 0 ]; do
        content="$(render_token "$content" "$1" "$2")"
        shift 2
    done
    printf '%s\n' "$content" > "$output"
}

echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}🚀 Symfony Smart Project Generator (FrankenPHP, full-Docker)${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "📌 Versi Symfony yang akan diinstal: ${YELLOW}$SYMFONY_VERSION_LABEL${NC}"
echo ""

# ==========================================
# CEK DEPENDENSI (hanya Docker yang wajib)
# ==========================================
echo -e "${BLUE}🔍 Mengecek dependensi sistem...${NC}"

if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker belum terinstal! Silakan instal dari https://docs.docker.com/get-docker/${NC}"
    exit 1
fi
echo -e "✅ ${GREEN}Docker terinstal${NC}"

if ! docker compose version >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker Compose v2 (plugin 'docker compose') tidak ditemukan!${NC}"
    exit 1
fi
echo -e "✅ ${GREEN}Docker Compose v2 terinstal${NC}"
echo ""

# ==========================================
# 1. Nama Project
# ==========================================
read -r -p "Masukkan nama project Anda (contoh: My Project): " RAW_NAME

if [ -z "${RAW_NAME// }" ]; then
    echo -e "${RED}Error: Nama project tidak boleh kosong!${NC}"
    exit 1
fi

PROJECT_NAME=$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+$//g')

if [ -z "$PROJECT_NAME" ]; then
    echo -e "${RED}Error: Nama project menghasilkan string kosong setelah sanitasi. Gunakan huruf/angka.${NC}"
    exit 1
fi

if [ -d "$PROJECT_NAME" ]; then
    echo -e "${RED}Error: Folder '$PROJECT_NAME' sudah ada. Pilih nama lain atau hapus folder tersebut.${NC}"
    exit 1
fi

echo -e "📁 Nama folder yang akan dibuat: ${YELLOW}$PROJECT_NAME${NC}\n"

# ==========================================
# 2. Tipe Project
# ==========================================
echo "Pilih tipe project:"
echo "1) REST API"
echo "2) Web Application (Symfony UX: Twig + Stimulus + Turbo + Live Components)"
echo "3) Full-stack: Symfony API + Next.js (auth + RBAC otomatis via kematjaya/auth-bundle + access-control-bundle)"
read -r -p "Masukkan pilihan Anda (1/2/3): " PROJECT_TYPE

case "$PROJECT_TYPE" in
    1) TYPE_NAME="REST API"; PROJECT_TYPE_DIR="api" ;;
    2) TYPE_NAME="Web Application"; PROJECT_TYPE_DIR="fullstack" ;;
    3) TYPE_NAME="Full-stack (Symfony API + Next.js)"; PROJECT_TYPE_DIR="bff-next" ;;
    *)
        echo -e "${RED}Error: Tipe project tidak valid.${NC}"
        exit 1
        ;;
esac

TYPE_TEMPLATE_DIR="$TEMPLATE_DIR/$PROJECT_TYPE_DIR"

# ==========================================
# 3. Database
# ==========================================
echo ""
echo "Pilih database yang digunakan:"
echo "1) MySQL"
echo "2) PostgreSQL"
read -r -p "Masukkan pilihan Anda (1/2): " DB_TYPE

case "$DB_TYPE" in
    1)
        DB_NAME="MySQL"
        DB_IMAGE="mysql:8.0"
        PHP_DB_EXTS="pdo_mysql mysqli"
        ;;
    2)
        DB_NAME="PostgreSQL"
        DB_IMAGE="postgres:16-alpine"
        PHP_DB_EXTS="pdo_pgsql pgsql"
        ;;
    *)
        echo -e "${RED}Error: Database tidak valid.${NC}"
        exit 1
        ;;
esac

echo -e "\n${BLUE}⏳ Memulai setup project '$PROJECT_NAME'...${NC}"
echo "--------------------------------------------------"

# ==========================================
# Generate kredensial acak (bukan hardcoded!)
# ==========================================
if command -v openssl >/dev/null 2>&1; then
    DB_PASSWORD=$(openssl rand -hex 16)
    DB_ROOT_PASSWORD=$(openssl rand -hex 16)
else
    # Fallback tanpa openssl: baca randomness asli dari /dev/urandom, BUKAN
    # hash dari timestamp (yang predictable / gampang ditebak rentang
    # waktunya oleh siapa pun yang tahu kapan script ini dijalankan).
    DB_PASSWORD=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 32)
    DB_ROOT_PASSWORD=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 32)
fi

DB_NAME_SCHEMA=$PROJECT_NAME

# DATABASE_URL dihitung SEKALI di sini lalu ditulis ke .env.local lewat
# `echo` biasa (bukan compose.yaml — lihat komentar di STEP 2). Sengaja TIDAK
# memakai placeholder + sed/bash "${var//search/replace}" untuk
# menyuntikkannya ke file mana pun: DATABASE_URL mengandung karakter "&"
# (dari query string ?...&charset=...), dan baik `sed` (replacement "&" =
# seluruh match) maupun operator bash "${var//pat/repl}" di Bash 5.2+
# (unescaped "&" di repl = teks yang match) sama-sama memperlakukan "&"
# secara spesial di posisi replacement — kalau dipakai di sana hasilnya jadi
# rusak/korup. Ekspansi variabel biasa ($VAR di heredoc/echo) tidak punya
# masalah ini, jadi paling aman.
if [ "$DB_TYPE" == "1" ]; then
    DB_USER="app"
    DATABASE_URL="mysql://$DB_USER:$DB_PASSWORD@database:3306/$DB_NAME_SCHEMA?serverVersion=8.0.32&charset=utf8mb4"
else
    DB_USER="postgres"
    DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@database:5432/$DB_NAME_SCHEMA?serverVersion=16&charset=utf8"
fi

mkdir -p "$PROJECT_NAME"
PROJECT_DIR_ABS="$ORIGINAL_DIR/$PROJECT_NAME"
CLEANUP_ON_FAILURE=1
cd "$PROJECT_NAME"

# Tipe 3 (bff-next) pakai layout backend/+frontend/ (monorepo split) —
# tipe lain tetap flat (skeleton Symfony langsung di root project).
# BACKEND_SUBDIR dipakai untuk path Docker (context/volume mount, cukup
# "." atau "backend", tanpa "./"). BACKEND_FILE_PREFIX dipakai untuk path
# file host-side biasa (cukup string kosong atau "backend/"). Untuk tipe
# 1/2 keduanya no-op — output identik dengan sebelum restructure ini.
if [ "$PROJECT_TYPE" == "3" ]; then
    BACKEND_SUBDIR="backend"
    BACKEND_FILE_PREFIX="backend/"
    COMPOSE_BUILD_CONTEXT="./backend"
    COMPOSE_VOLUME_SRC="./backend"
else
    BACKEND_SUBDIR="."
    BACKEND_FILE_PREFIX=""
    COMPOSE_BUILD_CONTEXT="."
    COMPOSE_VOLUME_SRC="./"
fi
mkdir -p "$BACKEND_SUBDIR"

# ==========================================
# STEP 1 — Generate project Symfony di DALAM Docker
# Wajib dilakukan sebelum menulis Dockerfile/compose,
# karena `composer create-project` menolak folder yang tidak kosong.
# Pakai image resmi `composer:2` sebagai builder sekali pakai.
# ==========================================
echo -e "🛠️  ${GREEN}Generating skeleton Symfony di dalam container sementara...${NC}"

# Cache Composer di host (bukan di dalam container yang --rm) supaya
# antar-panggilan `composer require` dalam satu generate, DAN antar-project
# yang di-generate berkali-kali, tidak selalu download ulang paket dari nol.
COMPOSER_CACHE_HOST_DIR="${COMPOSER_CACHE_HOST_DIR:-$HOME/.cache/symfony-generator/composer}"
mkdir -p "$COMPOSER_CACHE_HOST_DIR"

COMPOSER_RUN=(docker run --rm
    -u "$(id -u)":"$(id -g)"
    -e COMPOSER_CACHE_DIR=/tmp/composer-cache
    -e HOME=/tmp
    -v "$COMPOSER_CACHE_HOST_DIR":/tmp/composer-cache
    -v "$PWD/$BACKEND_SUBDIR":/app -w /app
    composer:2)

cleanup_partial_project_dir() {
    local entries=()

    (
        cd "$BACKEND_SUBDIR" || exit 0
        shopt -s dotglob nullglob
        entries=(*)
        if [ ${#entries[@]} -gt 0 ]; then
            rm -rf -- "${entries[@]}"
        fi
        shopt -u dotglob nullglob
    )
    # Docker auto-create bind-mount source sebagai root-owned kalau tidak
    # ada — bikin COMPOSER_RUN (jalan sebagai -u $(id -u):$(id -g)) gagal
    # permission pada retry berikutnya. mkdir ulang di sini supaya folder
    # tetap ada dan tetap dimiliki user host.
    mkdir -p "$BACKEND_SUBDIR"
}

run_composer_create_project() {
    local max_attempts=5
    local sleep_seconds=10
    local attempt=1
    local tmpfile

    while true; do
        tmpfile=$(mktemp /tmp/symfony-create-project.XXXXXX)

        if "${COMPOSER_RUN[@]}" create-project symfony/skeleton:"$SYMFONY_SKELETON_CONSTRAINT" . --no-interaction > "$tmpfile" 2>&1; then
            cat "$tmpfile"
            rm -f "$tmpfile"

            if [ -f "$BACKEND_SUBDIR/bin/console" ]; then
                return 0
            fi

            echo -e "${YELLOW}⚠️  Symfony skeleton selesai tapi bin/console tidak ditemukan (${attempt}/${max_attempts}). Kemungkinan recipe Flex gagal parsial.${NC}" >&2

            if [ $attempt -ge $max_attempts ]; then
                echo -e "${RED}❌ bin/console tetap tidak ditemukan setelah ${max_attempts} percobaan.${NC}" >&2
                return 1
            fi

            echo -e "${YELLOW}⏳ Membersihkan hasil parsial lalu retry dalam ${sleep_seconds} detik...${NC}" >&2
            cleanup_partial_project_dir
            attempt=$((attempt + 1))
            sleep "$sleep_seconds"
            continue
        fi

        echo -e "${YELLOW}⚠️  Gagal generate skeleton Symfony (${attempt}/${max_attempts}). Output terakhir:${NC}" >&2
        cat "$tmpfile" >&2
        rm -f "$tmpfile"

        if [ $attempt -ge $max_attempts ]; then
            echo -e "${RED}❌ Gagal generate skeleton Symfony setelah ${max_attempts} percobaan.${NC}" >&2
            return 1
        fi

        echo -e "${YELLOW}⏳ Membersihkan hasil parsial lalu retry dalam ${sleep_seconds} detik...${NC}" >&2
        cleanup_partial_project_dir
        attempt=$((attempt + 1))
        sleep "$sleep_seconds"
    done
}

run_composer_create_project

if [ "$PROJECT_TYPE" == "1" ]; then
    echo -e "📦 ${GREEN}Menginstal dependencies REST API (ORM, Security, Serializer, Validator, CORS, Swagger, Test)...${NC}"
    # symfony/security-bundle WAJIB ikut dari awal (bukan cuma di jwt-setup.sh):
    # bin/user-setup.sh sudah membuat User entity + password hashing lewat
    # UserPasswordHasherInterface, yang datang dari paket ini.
    "${COMPOSER_RUN[@]}" require logger symfony/orm-pack symfony/security-bundle symfony/serializer-pack symfony/validator nelmio/cors-bundle symfony/maker-bundle nelmio/api-doc-bundle --no-interaction
    "${COMPOSER_RUN[@]}" require --dev symfony/test-pack dama/doctrine-test-bundle symfony/maker-bundle --no-interaction
elif [ "$PROJECT_TYPE" == "3" ]; then
    echo -e "📦 ${GREEN}Menginstal dependencies dasar (ORM, Security)...${NC}"
    # SENGAJA minimal di sini: api-platform/symfony, api-platform/doctrine-orm,
    # nelmio/cors-bundle, kematjaya/auth-bundle, kematjaya/access-control-bundle
    # semuanya dipasang belakangan oleh bin/user-setup.sh (lihat
    # symfony/bff-next/user-setup.sh) — biar tidak ke-install dobel/konflik.
    # symfony/security-bundle WAJIB ikut dari sini juga: bin/user-setup.sh
    # men-diff bentuk DEFAULT security.yaml recipe ini untuk auto-merge auth,
    # jadi bentuknya harus persis apa adanya dari recipe resmi paket ini.
    "${COMPOSER_RUN[@]}" require logger symfony/orm-pack symfony/security-bundle --no-interaction
    "${COMPOSER_RUN[@]}" require --dev symfony/test-pack dama/doctrine-test-bundle symfony/maker-bundle --no-interaction
else
    echo -e "📦 ${GREEN}Menginstal Symfony webapp-pack + UX (Stimulus, Turbo, Live Components)...${NC}"
    "${COMPOSER_RUN[@]}" require symfony/webapp-pack --no-interaction
    "${COMPOSER_RUN[@]}" require logger symfony/orm-pack symfony/ux-turbo symfony/ux-live-component --no-interaction --no-scripts

    mkdir -p config/packages
    cp "$TYPE_TEMPLATE_DIR/config/packages/twig_component.yaml" config/packages/twig_component.yaml

    "${COMPOSER_RUN[@]}" run-script post-update-cmd
    "${COMPOSER_RUN[@]}" require --dev symfony/test-pack dama/doctrine-test-bundle symfony/maker-bundle --no-interaction
fi

git init -q 2>/dev/null || true

echo -e "⚙️  ${GREEN}Menyiapkan .env.local (kredensial rahasia)...${NC}"
# .env.local otomatis diabaikan Git oleh .gitignore bawaan Symfony Flex.
# Kredensial database SENGAJA ditaruh di sini, BUKAN di compose.yaml,
# supaya compose.yaml aman untuk di-commit ke Git tanpa membocorkan
# password. compose.yaml sudah punya `env_file: [.env, .env.local]` untuk
# service php, dan `env_file: [.env.local]` untuk service database, jadi
# nilai di bawah otomatis ke-inject ke container tanpa perlu flag khusus.
cat <<'EOF' > "${BACKEND_FILE_PREFIX}.env.local"
# File ini untuk override variabel .env khusus environment lokal Anda.
# Otomatis diabaikan Git — jangan hapus baris kredensial di bawah ini.
EOF

{
    echo "DATABASE_URL=\"$DATABASE_URL\""
    if [ "$DB_TYPE" == "1" ]; then
        echo "MYSQL_ROOT_PASSWORD=$DB_ROOT_PASSWORD"
        echo "MYSQL_PASSWORD=$DB_PASSWORD"
    else
        echo "POSTGRES_PASSWORD=$DB_PASSWORD"
    fi
} >> "${BACKEND_FILE_PREFIX}.env.local"

touch "${BACKEND_FILE_PREFIX}.env"

# ==========================================
# STEP 2 — Tulis file-file Docker (setelah source Symfony ada)
# ==========================================
echo -e "🐳 ${GREEN}Menulis Dockerfile, compose.yaml, dan konfigurasi FrankenPHP...${NC}"

cp "$COMMON_TEMPLATE_DIR/dockerignore" "${BACKEND_FILE_PREFIX}.dockerignore"

mkdir -p "${BACKEND_FILE_PREFIX}.docker/frankenphp/conf.d"
cp "$COMMON_TEMPLATE_DIR/frankenphp/conf.d/app.ini" "${BACKEND_FILE_PREFIX}.docker/frankenphp/conf.d/app.ini"
cp "$COMMON_TEMPLATE_DIR/frankenphp/conf.d/zzz-opcache-prod.ini" "${BACKEND_FILE_PREFIX}.docker/frankenphp/conf.d/zzz-opcache-prod.ini"
cp "$COMMON_TEMPLATE_DIR/frankenphp/Caddyfile" "${BACKEND_FILE_PREFIX}.docker/frankenphp/Caddyfile"

# Dockerfile multi-stage: base -> dev -> prod. Langkah prod tambahan (mis.
# asset-map:compile untuk fullstack) hidup di $TYPE_TEMPLATE_DIR/Dockerfile.prod-extra
# (kosong untuk API) — lihat symfony/api/ vs symfony/fullstack/.
PROD_EXTRA_STEP="$(cat "$TYPE_TEMPLATE_DIR/Dockerfile.prod-extra" 2>/dev/null || true)"
render_template "$COMMON_TEMPLATE_DIR/Dockerfile.tpl" "${BACKEND_FILE_PREFIX}Dockerfile" \
    "@@PHP_DB_EXTS@@" "$PHP_DB_EXTS" \
    "@@PROD_EXTRA_STEP@@" "$PROD_EXTRA_STEP"

# compose.yaml — TIDAK berisi password apa pun (lihat .env.local di atas).
# Kredensial di-generate acak per project dan hanya hidup di .env.local
# (gitignored), jadi compose.yaml ini aman untuk di-commit ke Git.
# Untuk deployment sungguhan, tetap pindahkan ke secrets manager.
cat <<EOF > compose.yaml
services:
  php:
    build:
      context: $COMPOSE_BUILD_CONTEXT
      dockerfile: Dockerfile
      target: frankenphp_dev
    depends_on:
      database:
        condition: service_healthy
    environment:
      APP_ENV: \${APP_ENV:-dev}
      APP_DEBUG: \${APP_DEBUG:-1}
    volumes:
      - $COMPOSE_VOLUME_SRC:/app
      - caddy_data:/data
      - caddy_config:/config
    env_file:
      - ${BACKEND_FILE_PREFIX}.env
      - ${BACKEND_FILE_PREFIX}.env.local
    ports:
      - "\${HTTP_PORT:-8082}:8082"
      - "\${HTTPS_PORT:-443}:443"

  database:
    image: $DB_IMAGE
    env_file:
      - ${BACKEND_FILE_PREFIX}.env.local
EOF

if [ "$DB_TYPE" == "1" ]; then
cat <<EOF >> compose.yaml
    environment:
      MYSQL_DATABASE: "$DB_NAME_SCHEMA"
      MYSQL_USER: "$DB_USER"
    healthcheck:
      # Password dibaca dari env var MYSQL_PASSWORD di dalam container
      # (di-inject via env_file di atas), bukan literal di file ini.
      # "\$\$" -> docker compose meng-interpolasi jadi "\$" tunggal
      # sebelum command dijalankan oleh shell container.
      test: ["CMD-SHELL", "mysqladmin ping --protocol=TCP -h 127.0.0.1 -u $DB_USER --password=\$\$MYSQL_PASSWORD"]
      interval: 5s
      timeout: 5s
      retries: 10
    volumes:
      - db_data:/var/lib/mysql
EOF
else
cat <<EOF >> compose.yaml
    environment:
      POSTGRES_DB: "$DB_NAME_SCHEMA"
      POSTGRES_USER: "$DB_USER"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $DB_USER -d $DB_NAME_SCHEMA"]
      interval: 5s
      timeout: 5s
      retries: 10
    volumes:
      - db_data:/var/lib/postgresql/data
EOF
fi

cat <<EOF >> compose.yaml

  adminer:
    image: adminer:4
    restart: unless-stopped
    depends_on:
      - database
    environment:
      ADMINER_DEFAULT_SERVER: database
    ports:
      - "\${ADMINER_PORT:-9000}:8080"
EOF

# Service tambahan sesuai tipe project (mis. playwright hanya untuk
# fullstack) hidup di $TYPE_TEMPLATE_DIR/compose.extra-services.yaml —
# kosong untuk API, jadi tidak ada service yang tidak relevan ikut nyangkut.
if [ -s "$TYPE_TEMPLATE_DIR/compose.extra-services.yaml" ]; then
    cat "$TYPE_TEMPLATE_DIR/compose.extra-services.yaml" >> compose.yaml
fi

cat <<EOF >> compose.yaml

volumes:
  db_data:
  caddy_data:
  caddy_config:
EOF

# compose.prod.yaml — dipakai lewat: docker compose -f compose.yaml -f compose.prod.yaml up -d --build
cp "$COMMON_TEMPLATE_DIR/compose.prod.yaml" compose.prod.yaml

# ==========================================
# Helper: tunggu database benar-benar siap (TCP)
# ==========================================
wait_for_database_ready() {
    local max_attempts=20
    local sleep_seconds=3
    local attempt=1

    if [ "$DB_TYPE" == "1" ]; then
        # MySQL: ping via TCP, bukan Unix socket
        until docker compose exec -T database mysqladmin ping --protocol=TCP -h 127.0.0.1 -u "$DB_USER" --password="$DB_PASSWORD" >/dev/null 2>&1; do
            if [ $attempt -ge $max_attempts ]; then
                echo -e "${RED}❌ Database MySQL tidak siap setelah $((max_attempts * sleep_seconds)) detik. Periksa log: docker compose logs database${NC}"
                return 1
            fi
            echo -e "${YELLOW}⏳ Database belum siap, mencoba lagi (${attempt}/${max_attempts})...${NC}"
            attempt=$((attempt + 1))
            sleep "$sleep_seconds"
        done
    else
        # PostgreSQL
        until docker compose exec -T database pg_isready -U "$DB_USER" -d "$DB_NAME_SCHEMA" >/dev/null 2>&1; do
            if [ $attempt -ge $max_attempts ]; then
                echo -e "${RED}❌ Database PostgreSQL tidak siap setelah $((max_attempts * sleep_seconds)) detik. Periksa log: docker compose logs database${NC}"
                return 1
            fi
            echo -e "${YELLOW}⏳ Database belum siap, mencoba lagi (${attempt}/${max_attempts})...${NC}"
            attempt=$((attempt + 1))
            sleep "$sleep_seconds"
        done
    fi
}

# ==========================================
# Helper: buat schema database dengan retry
# ==========================================
run_doctrine_database_create() {
    local max_attempts=20
    local sleep_seconds=3
    local attempt=1
    local tmpfile

    tmpfile=$(mktemp /tmp/doctrine-create.XXXXXX)
    # Cleanup temp file on function return
    trap 'rm -f "${tmpfile:-}"' RETURN

    until docker compose exec php bin/console doctrine:database:create --if-not-exists > "$tmpfile" 2>&1; do
        if [ $attempt -ge $max_attempts ]; then
            echo -e "${RED}❌ Gagal membuat schema database setelah $((max_attempts * sleep_seconds)) detik.${NC}"
            cat "$tmpfile" >&2
            return 1
        fi
        echo -e "${YELLOW}⏳ Database belum siap untuk skema, mencoba lagi (${attempt}/${max_attempts})...${NC}"
        attempt=$((attempt + 1))
        sleep "$sleep_seconds"
    done

    # Success: output the captured result
    cat "$tmpfile"
}

# ==========================================
# STEP 3 — Build & jalankan stack
# ==========================================
echo -e "🐳 ${GREEN}Build image (target: dev)...${NC}"
docker compose build php

echo -e "🚀 ${GREEN}Menjalankan stack (php + database + adminer)...${NC}"
docker compose up -d

echo -e "⏳ ${GREEN}Menunggu database siap...${NC}"
wait_for_database_ready

echo -e "🗄️  ${GREEN}Membuat schema database...${NC}"
run_doctrine_database_create

if [ "$PROJECT_TYPE" == "2" ]; then
    echo -e "🎛️  ${GREEN}Menyiapkan AssetMapper/importmap...${NC}"
    docker compose exec php bin/console importmap:install
fi

# ==========================================
# STEP 4 — Setup folder e2e (Playwright), terpisah dari tests/ PHPUnit
# ==========================================
if [ "$PROJECT_TYPE" == "2" ]; then
    echo -e "🎭 ${GREEN}Menyiapkan folder e2e/ (Playwright)...${NC}"
    mkdir -p e2e/tests
    cp "$TYPE_TEMPLATE_DIR/e2e/package.json" e2e/package.json
    cp "$TYPE_TEMPLATE_DIR/e2e/playwright.config.ts" e2e/playwright.config.ts
    cp "$TYPE_TEMPLATE_DIR/e2e/tests/homepage.spec.ts" e2e/tests/homepage.spec.ts
fi

# ==========================================
# STEP 5 — README.md
# ==========================================
echo -e "📝 ${GREEN}Membuat README.md...${NC}"

cat <<EOF > README.md
# $PROJECT_NAME

Proyek ini di-generate otomatis dengan infrastruktur **FrankenPHP** (full-Docker,
tanpa dependensi PHP/Composer/Node di host).

- **Tipe Proyek:** $TYPE_NAME
- **Database Engine:** $DB_NAME
- **Server:** FrankenPHP (dev: classic mode, prod: worker mode)
- **PHP Version:** 8.4

## Kredensial database (di-generate acak, JANGAN dipakai untuk deployment nyata)

- User: \`$DB_USER\`
- Password: lihat file \`.env.local\` (di-gitignore, TIDAK ada di \`compose.yaml\`)
- Database: \`$DB_NAME_SCHEMA\`

Password sengaja hanya disimpan di \`.env.local\` (otomatis diabaikan Git),
bukan di \`compose.yaml\`, supaya \`compose.yaml\` aman untuk di-commit ke
repository. Untuk lingkungan production sungguhan, pindahkan kredensial ke
secrets manager (mis. Docker secrets, Vault, atau env var dari platform
hosting Anda) — jangan commit \`.env.local\` ke repository publik.

## Menjalankan aplikasi

\`\`\`bash
docker compose up -d
\`\`\`

Akses di **http://localhost:8082**.

## Menjalankan console / composer / migrasi

Semua dijalankan lewat container, tidak perlu PHP di host:

\`\`\`bash
docker compose exec php bin/console <perintah>
docker compose exec php composer require <package>
docker compose exec php bin/console doctrine:migrations:diff
docker compose exec php bin/console doctrine:migrations:migrate
\`\`\`

## PHPUnit

\`\`\`bash
docker compose exec php bin/phpunit
\`\`\`

Bundle \`dama/doctrine-test-bundle\` sudah ter-install — aktifkan dengan
menambahkan baris berikut ke \`<extensions>\` pada \`phpunit.xml.dist\`
(Symfony's test-pack recipe membuat file ini otomatis saat instalasi):

\`\`\`xml
<extensions>
    <bootstrap class="DAMA\\DoctrineTestBundle\\PHPUnit\\PHPUnitExtension" />
</extensions>
\`\`\`

Ini bikin setiap test method otomatis di-rollback dalam transaksi, jadi test
yang menyentuh database asli tidak saling mengotori data satu sama lain.

$( [ "$PROJECT_TYPE" == "3" ] && cat <<EOT
## Auth, RBAC, dan Frontend Next.js

Backend punya ORM + Security dasar — API Platform, JWT auth
(\`kematjaya/auth-bundle\`), dan RBAC (\`kematjaya/access-control-bundle\`)
sudah dipasang OTOMATIS oleh generator (\`symfony.bash\`) lewat dua script
di bawah, masing-masing dijalankan sendiri (tanpa campur tangan manual)
dengan retry maksimal 3x kalau sempat gagal — cek log generator di atas
untuk tahu apakah keduanya sukses:

\`\`\`bash
bash bin/user-setup.sh      # API Platform, auth-bundle, access-control-bundle,
                              # fixture user, auto-merge security.yaml
bash bin/frontend-setup.sh   # generate Next.js fresh + wiring auth-ui/access-control-ui
\`\`\`

Tidak ada langkah manual lagi — sudah diverifikasi end-to-end (register,
login, fixture, RBAC). Kedua perintah di atas hanya perlu dijalankan ULANG
secara manual kalau salah satunya gagal setelah 3x percobaan otomatis
(generator akan bilang jelas di output-nya kalau ini terjadi), atau kalau
Anda sengaja mau re-generate ulang (mis. setelah \`rm -rf frontend\`) —
jalankan berurutan, karena frontend-setup.sh butuh backend sudah hidup
untuk generate tipe API-nya.

### URL yang bisa diakses

| URL | Keterangan |
| --- | --- |
| http://localhost:3000 | Frontend Next.js (login/register/dashboard) |
| http://localhost:8082/api/docs | Swagger UI (API Platform) |
| http://localhost:8082/api | Root API Platform (JSON-LD/Hydra) |
| http://localhost:9000 | Adminer (login pakai kredensial di \`backend/.env.local\`) |

### Login

- \`root@example.com\` / \`admin123\` (ROLE_ADMIN)
- \`user@example.com\` / \`admin123\` (ROLE_USER)

Keduanya fixture, dibuat \`bin/user-setup.sh\` lewat
\`backend/src/DataFixtures/AppFixtures.php\`. Atau register user baru lewat
\`http://localhost:3000/register\`.

Database, nama project, dan folder project untuk backend+frontend semuanya
konsisten mengikuti nama \`$PROJECT_NAME\` yang dipilih di awal generator ini.

### Struktur folder

\`\`\`
$PROJECT_NAME/
├── bin/                    # user-setup.sh, frontend-setup.sh — dijalankan dari HOST
├── backend/                # Symfony (API Platform, auth-bundle, access-control-bundle)
│   ├── bin/                # bin/console (Symfony bawaan) + access-control-setup.sh
│   │                        # (dijalankan DARI DALAM container php, bukan dari host)
│   ├── src/                # Entity/, Repository/, Security/ (UserManager), DataFixtures/
│   ├── config/              # config Symfony + config/permissions/*.yaml (RBAC manifest)
│   ├── tests/               # PHPUnit
│   ├── Dockerfile
│   ├── .env / .env.local    # kredensial (gitignored)
│   └── security-snippet.yaml  # hanya muncul kalau auto-merge security.yaml gagal
├── frontend/               # Next.js (App Router) — login/register/dashboard/BFF routes
│   ├── src/app/            # halaman + route handler proxy ke backend (BFF)
│   ├── tests/unit/         # Vitest + Testing Library
│   └── tests/e2e/          # Playwright
├── compose.yaml            # service: php (context: ./backend), database, adminer
├── compose.override.yaml   # service: frontend (ditambahkan frontend-setup.sh)
├── compose.prod.yaml
├── package.json            # script npm, wrapper docker compose (lihat tabel di bawah)
└── Makefile                # shortcut perintah setara, gaya \`make\` (opsional, pilih salah satu)
\`\`\`

Root project TIDAK punya folder template tambahan apa pun — cuma
\`backend/\`+\`frontend/\` seperti di atas. Konsekuensinya: \`bin/frontend-setup.sh\`
butuh instalasi \`symfony.bash\` yang generate project ini masih ada di mesin
yang sama untuk bisa di-generate ULANG (mis. setelah \`rm -rf frontend\`) —
kalau generatornya sudah di-\`symfony-new uninstall\` atau project dipindah ke
mesin lain, \`bin/frontend-setup.sh\` akan berhenti dengan pesan error jelas +
instruksi install ulang generator (bukan silent-fail). Untuk generate ulang
SELURUH project (bukan cuma frontend), tetap bisa kapan saja lewat
\`symfony.bash\`/\`symfony-new\` di mesin mana pun.

### Perintah (\`make\` / \`npm run\`)

Dua cara setara — sama-sama cuma pembungkus tipis \`docker compose exec\`,
tidak perlu PHP/Composer/Node di host, pilih yang lebih familiar:

| \`make\` | \`npm run\` | Keterangan |
| --- | --- | --- |
| \`make dev\` | \`npm run dev\` | \`docker compose up -d --build\` |
| \`make down\` | \`npm run down\` | \`docker compose down\` |
| \`make logs\` | \`npm run logs\` | tail log semua service |
| \`make console <cmd>\` | \`npm run console -- <cmd>\` | \`bin/console <cmd>\`, mis. \`doctrine:migrations:diff\` |
| \`make composer <cmd>\` | \`npm run composer -- <cmd>\` | \`composer <cmd>\`, mis. \`require symfony/mailer\` |
| \`make cc\` | \`npm run cc\` | \`bin/console cache:clear\` |
| \`make migrate\` | \`npm run migrate\` | jalankan migration Doctrine |
| \`make schema-update\` | \`npm run schema:update\` | \`doctrine:schema:update --force\` (dev only, bukan migration) |
| \`make test-backend\` | \`npm run test:backend\` | \`bin/phpunit\` |
| \`make test-frontend\` | \`npm run test:frontend\` | \`npm test\` (Vitest) di container frontend |
| \`make test-e2e\` | \`npm run test:e2e\` | \`docker compose --profile e2e run --rm playwright\` |
| \`make lint\` | \`npm run lint\` | \`npm run lint\` (ESLint) di container frontend |

Tidak ada target lint untuk backend (php-cs-fixer/phpstan) karena keduanya
bukan bagian dari paket minimal yang di-install generator ini — tambahkan
manual dulu lewat \`make composer require --dev friendsofphp/php-cs-fixer\`
kalau perlu.

\`make test-e2e\` sengaja menjalankan container image resmi
\`mcr.microsoft.com/playwright\` (Debian), BUKAN service \`frontend\` yang
Alpine — browser Playwright tidak kompatibel dengan musl libc yang dipakai
Alpine. Container ini terpisah (profile \`e2e\`, tidak ikut \`docker compose up\`)
dan menghubungi service \`frontend\` yang sudah jalan lewat network internal.
EOT
)

$( [ "$PROJECT_TYPE" == "2" ] && cat <<'EOT'
## End-to-end testing (Playwright)

Dua cara menjalankan, pilih salah satu:

**A. Full Docker (tidak perlu Node di host):**
```bash
docker compose --profile e2e run --rm playwright
```

**B. Native (perlu Node.js di host, enak untuk UI mode/debugging):**
```bash
cd e2e
npm install
npx playwright install --with-deps
npx playwright test
# atau mode UI interaktif:
npx playwright test --ui
```

Test disimpan di `e2e/tests/` — terpisah dari `tests/` milik PHPUnit supaya
tidak tercampur dan `node_modules/` tidak numpuk di root project PHP.
EOT
)

## Production

Build & jalankan target production (worker mode aktif, source di-COPY ke
image, tanpa bind-mount):

\`\`\`bash
docker compose -f compose.yaml -f compose.prod.yaml up -d --build
\`\`\`

$( [ "$PROJECT_TYPE" == "1" ] && echo -e "## API Docs\n\nTersedia di \`http://localhost:8082/api/doc\`." )
EOF

echo -e "🔧 ${GREEN}Menyalin setup helper (khusus tipe $TYPE_NAME)...${NC}"
mkdir -p bin

if [ "$PROJECT_TYPE" == "2" ]; then
    DESIGN_DOC_SOURCE="$TYPE_TEMPLATE_DIR/DESIGN.md"
    SETUP_SCRIPT_SOURCE="$TYPE_TEMPLATE_DIR/setup.sh"
    SECURITY_SCRIPT_SOURCE="$TYPE_TEMPLATE_DIR/security-setup.sh"

    for required_file in "$SETUP_SCRIPT_SOURCE" "$SECURITY_SCRIPT_SOURCE" "$DESIGN_DOC_SOURCE"; do
        if [ ! -f "$required_file" ]; then
            echo -e "${RED}Error: File template tidak ditemukan: $required_file${NC}"
            exit 1
        fi
    done

    cp "$DESIGN_DOC_SOURCE" DESIGN.md
    cp "$SETUP_SCRIPT_SOURCE" bin/user-setup.sh
    cp "$SECURITY_SCRIPT_SOURCE" bin/security-setup.sh
    chmod 755 bin/user-setup.sh bin/security-setup.sh
elif [ "$PROJECT_TYPE" == "3" ]; then
    USER_SETUP_SOURCE="$TYPE_TEMPLATE_DIR/user-setup.sh"
    FRONTEND_SETUP_SOURCE="$TYPE_TEMPLATE_DIR/frontend-setup.sh"
    GENERATE_CRUD_SOURCE="$TYPE_TEMPLATE_DIR/generate-crud.sh"
    ACCESS_CONTROL_SETUP_SOURCE="$TYPE_TEMPLATE_DIR/backend/access-control-setup.sh"
    FRONTEND_TEMPLATE_SOURCE="$TYPE_TEMPLATE_DIR/frontend"
    MAKEFILE_SOURCE="$TYPE_TEMPLATE_DIR/Makefile"
    PACKAGE_JSON_SOURCE="$TYPE_TEMPLATE_DIR/package.json.tpl"

    for required_file in "$USER_SETUP_SOURCE" "$FRONTEND_SETUP_SOURCE" "$GENERATE_CRUD_SOURCE" "$ACCESS_CONTROL_SETUP_SOURCE" "$MAKEFILE_SOURCE" "$PACKAGE_JSON_SOURCE"; do
        if [ ! -f "$required_file" ]; then
            echo -e "${RED}Error: File template tidak ditemukan: $required_file${NC}"
            exit 1
        fi
    done
    if [ ! -d "$FRONTEND_TEMPLATE_SOURCE" ]; then
        echo -e "${RED}Error: Folder template tidak ditemukan: $FRONTEND_TEMPLATE_SOURCE${NC}"
        exit 1
    fi

    cp "$USER_SETUP_SOURCE" bin/user-setup.sh
    # frontend-setup.sh (BEDA dari user-setup.sh) di-render, bukan cp polos —
    # path absolut lokasi template frontend generator ($FRONTEND_TEMPLATE_SOURCE,
    # di mesin INI, saat generate INI) dibakar langsung ke dalamnya lewat token
    # @@FRONTEND_TEMPLATE_SOURCE@@. Konsekuensi sengaja diterima: project hasil
    # generate TIDAK simpan salinan template sendiri (root project jadi bersih,
    # cuma backend/+frontend/, tanpa folder template apa pun, tersembunyi
    # ataupun tidak) — tapi kalau nanti frontend/ dihapus dan mau di-generate
    # ulang, bin/frontend-setup.sh WAJIB masih bisa akses path yang dibakar itu
    # (generator belum di-`symfony-new uninstall`, project belum pindah mesin,
    # lokasi instalasi belum berubah). Kalau tidak, gagal jelas dengan instruksi
    # install ulang — lihat pengecekan TEMPLATE_DIR di frontend-setup.sh.
    render_template "$FRONTEND_SETUP_SOURCE" bin/frontend-setup.sh \
        "@@FRONTEND_TEMPLATE_SOURCE@@" "$FRONTEND_TEMPLATE_SOURCE"
    cp "$GENERATE_CRUD_SOURCE" bin/generate-crud.sh
    chmod 755 bin/user-setup.sh bin/frontend-setup.sh bin/generate-crud.sh

    # access-control-setup.sh BEDA dari 2 script di atas: dia dipanggil DARI
    # DALAM container php ("docker compose exec php bash bin/access-control-setup.sh",
    # lihat user-setup.sh), jadi harus ada di path yang ke-mount ke /app —
    # yaitu backend/bin/, BUKAN bin/ di root project (bin/ root isinya
    # khusus script yang dijalankan dari HOST).
    mkdir -p "${BACKEND_FILE_PREFIX}bin"
    cp "$ACCESS_CONTROL_SETUP_SOURCE" "${BACKEND_FILE_PREFIX}bin/access-control-setup.sh"
    chmod 755 "${BACKEND_FILE_PREFIX}bin/access-control-setup.sh"

    # Makefile dengan shortcut `make dev`/`make console ...`/`make test-backend`
    # dll — pembungkus `docker compose exec`, TIDAK butuh PHP/Node di host.
    # Lihat symfony/bff-next/Makefile untuk daftar lengkap target.
    cp "$MAKEFILE_SOURCE" Makefile

    # package.json root — orkestrasi setara Makefile tapi lewat `npm run`,
    # supaya bisa dipakai gabungan dengan script npm lain lintas folder
    # (backend+frontend). Sengaja tanpa dependencies (tidak butuh
    # "concurrently" dkk — paralelisme sudah ditangani docker compose
    # sendiri), jadi tidak ada node_modules/lockfile baru di root.
    render_template "$PACKAGE_JSON_SOURCE" package.json \
        "@@PROJECT_NAME@@" "$PROJECT_NAME"

    # ==========================================
    # STEP 6 (khusus tipe 3) — bin/user-setup.sh lalu bin/frontend-setup.sh
    # dulunya langkah manual ("masuk project, jalankan kedua script itu
    # sendiri"). Sekarang dijalankan otomatis dari sini. Tiap script dicoba
    # maksimal 3x kalau gagal; kalau tetap gagal setelah 3x, TIDAK
    # menghentikan symfony.bash (project sudah ter-generate valid) —
    # cetak peringatan lalu lanjut ke script berikutnya, sesuai
    # permintaan: retry maksimal 3x baru lanjut file selanjutnya.
    # ==========================================
    run_step_script_with_retry() {
        # Usage: run_step_script_with_retry <label> <script_path> [pre_retry_cleanup_fn]
        local label="$1" script_path="$2" pre_retry_fn="${3:-}"
        local max_attempts=3
        local attempt=1

        while [ "$attempt" -le "$max_attempts" ]; do
            echo -e "🔧 ${GREEN}${label} (percobaan ${attempt}/${max_attempts})...${NC}"
            if bash "$script_path"; then
                return 0
            fi

            echo -e "${YELLOW}⚠️  ${label} gagal (percobaan ${attempt}/${max_attempts}).${NC}" >&2

            if [ "$attempt" -ge "$max_attempts" ]; then
                echo -e "${RED}❌ ${label} tetap gagal setelah ${max_attempts} percobaan. Lanjut ke langkah berikutnya —${NC}" >&2
                echo -e "${RED}   jalankan manual belakangan: bash ${script_path}${NC}" >&2
                return 1
            fi

            if [ -n "$pre_retry_fn" ]; then
                "$pre_retry_fn"
            fi
            attempt=$((attempt + 1))
        done
    }

    cleanup_frontend_partial_before_retry() {
        # frontend-setup.sh menolak jalan kalau folder frontend/ atau
        # frontend-tmp/ (staging sementara) sudah ada — supaya retry
        # BENERAN mengulang dari awal (bukan langsung gagal di guard itu),
        # bersihkan dulu sisa percobaan sebelumnya. Aman: frontend-setup.sh
        # baru mv frontend-tmp -> frontend SETELAH semua langkah build
        # sukses, jadi "frontend/" yang dihapus di sini tidak pernah dalam
        # keadaan setengah jadi.
        rm -rf frontend frontend-tmp
    }

    echo ""
    echo -e "${BLUE}⏳ Menjalankan setup backend otomatis (API Platform, auth-bundle, access-control-bundle)...${NC}"
    USER_SETUP_STATUS=0
    run_step_script_with_retry "bin/user-setup.sh" bin/user-setup.sh || USER_SETUP_STATUS=$?

    echo ""
    echo -e "${BLUE}⏳ Menjalankan setup frontend otomatis (Next.js + wiring auth/RBAC UI)...${NC}"
    FRONTEND_SETUP_STATUS=0
    run_step_script_with_retry "bin/frontend-setup.sh" bin/frontend-setup.sh cleanup_frontend_partial_before_retry || FRONTEND_SETUP_STATUS=$?
else
    SETUP_SCRIPT_SOURCE="$TYPE_TEMPLATE_DIR/setup.sh"
    JWT_SCRIPT_SOURCE="$TYPE_TEMPLATE_DIR/jwt-setup.sh"

    for required_file in "$SETUP_SCRIPT_SOURCE" "$JWT_SCRIPT_SOURCE"; do
        if [ ! -f "$required_file" ]; then
            echo -e "${RED}Error: File template tidak ditemukan: $required_file${NC}"
            exit 1
        fi
    done

    cp "$SETUP_SCRIPT_SOURCE" bin/user-setup.sh
    cp "$JWT_SCRIPT_SOURCE" bin/jwt-setup.sh
    chmod 755 bin/user-setup.sh bin/jwt-setup.sh
fi

echo "--------------------------------------------------"
echo -e "${GREEN}✅ Setup selesai!${NC}"
echo -e "📁 Project: ${YELLOW}$PROJECT_NAME${NC}"
echo -e "🌐 Akses:   ${YELLOW}http://localhost:8082${NC}"
if [ "$PROJECT_TYPE" == "2" ]; then
    echo -e "🔧 masuk ke project dan jalankan: ${YELLOW}bash bin/user-setup.sh${NC}"
    echo -e "   lalu ikuti instruksi di akhirnya untuk ${YELLOW}bash bin/security-setup.sh${NC} (form login)"
elif [ "$PROJECT_TYPE" == "3" ]; then
    echo -e "🔧 bin/user-setup.sh dan bin/frontend-setup.sh sudah dijalankan otomatis (lihat log di atas)."
    if [ "${USER_SETUP_STATUS:-0}" -eq 0 ] && [ "${FRONTEND_SETUP_STATUS:-0}" -eq 0 ]; then
        echo -e "🌐 Frontend: ${YELLOW}http://localhost:3000${NC}"
    else
        echo -e "${RED}⚠️  Salah satu langkah di atas gagal setelah 3x percobaan — jalankan manual:${NC}"
        if [ "${USER_SETUP_STATUS:-0}" -ne 0 ]; then
            echo -e "   ${YELLOW}bash bin/user-setup.sh${NC}"
        fi
        if [ "${FRONTEND_SETUP_STATUS:-0}" -ne 0 ]; then
            echo -e "   ${YELLOW}bash bin/frontend-setup.sh${NC}"
        fi
    fi
else
    echo -e "🔧 masuk ke project dan jalankan: ${YELLOW}bash bin/user-setup.sh${NC}"
    echo -e "   lalu ikuti instruksi di akhirnya untuk ${YELLOW}bash bin/jwt-setup.sh${NC} (autentikasi JWT)"
fi
echo -e "📖 Baca ${YELLOW}README.md${NC} di dalam folder project untuk langkah selanjutnya."
