#!/usr/bin/env bash
set -Eeuo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

trap 'echo -e "\n${RED}❌ Terjadi error pada baris $LINENO. Proses dihentikan.${NC}"' ERR

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# Nama folder project = nama yang di-sanitasi symfony.bash dari input user
# (mkdir -p "$PROJECT_NAME" && cd "$PROJECT_NAME" di generator utama) — dipakai
# di bawah supaya package.json frontend & judul API Platform tidak generic.
PROJECT_NAME="$(basename "$ROOT_DIR")"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage: bash bin/frontend-setup.sh

Dev-only bootstrap from host (tipe project: Full-stack Symfony API + Next.js).
Jalankan SETELAH bash bin/user-setup.sh (backend harus sudah bisa diakses).

- generate Next.js app fresh (create-next-app, di dalam container Node
  sementara — host tidak butuh Node terinstal)
- npm install: @kematjaya/auth-ui, @kematjaya/access-control-ui,
  @kematjaya/bootstrap-ui-kit, react-hook-form, zod, dst
- menyalin src/ generik (BFF routes, login/register, dashboard shell,
  proxy.ts) ke frontend/src/ — TIDAK ADA satu pun file bisnis-spesifik
- menulis frontend/Dockerfile + compose.override.yaml (service "frontend")
- build & jalankan container frontend
- generate frontend/src/types/api.generated.ts dari OpenAPI backend
HELP
    exit 0
fi

if [[ ! -f backend/bin/console ]]; then
    echo -e "${RED}Error: backend/bin/console tidak ditemukan. Jalankan bin/user-setup.sh dulu, dan jalankan script ini dari root project.${NC}"
    exit 1
fi

if [[ -d frontend ]]; then
    echo -e "${RED}Error: folder 'frontend' sudah ada. Hapus dulu kalau mau generate ulang.${NC}"
    exit 1
fi

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bff-next-template/frontend" 2>/dev/null && pwd || true)"
if [[ -z "$TEMPLATE_DIR" ]]; then
    echo -e "${RED}Error: template frontend tidak ditemukan (bff-next-template/frontend). Script ini dipanggil dari lokasi yang salah.${NC}"
    exit 1
fi

NODE_IMAGE="node:24-alpine"

run_node() {
    docker run --rm -u "$(id -u)":"$(id -g)" -e HOME=/tmp -e PROJECT_NAME="$PROJECT_NAME" -v "$ROOT_DIR":/workspace -w /workspace "$NODE_IMAGE" "$@"
}

run_node_in_frontend() {
    docker run --rm -u "$(id -u)":"$(id -g)" -e HOME=/tmp -e PROJECT_NAME="$PROJECT_NAME" -v "$ROOT_DIR/frontend":/app -w /app "$NODE_IMAGE" "$@"
}

# ==========================================
# STEP 1 — Generate Next.js skeleton fresh (bukan copy dari template lama —
# supaya selalu ikut versi Next.js terbaru, lihat catatan di bff-next/README.md
# soal kenapa clone tarball dihindari).
# ==========================================
echo -e "🛠️  ${GREEN}Generating skeleton Next.js di dalam container sementara...${NC}"
run_node npx --yes create-next-app@latest frontend \
    --typescript --eslint --app --src-dir --import-alias "@/*" \
    --no-tailwind --no-turbopack --use-npm --yes

# ==========================================
# STEP 2 — Install dependency tambahan (auth-ui, access-control-ui, dst —
# package independen bervers sendiri, lihat README soal kenapa ini tidak
# mengunci ke 1 versi Next.js tertentu).
# ==========================================
echo -e "📦 ${GREEN}Menginstal @kematjaya/auth-ui, access-control-ui, bootstrap-ui-kit, dst...${NC}"
# zod di-pin eksplisit ke v4 — tanpa ini npm kadang keburu resolve zod@3.x
# (dari peerOptional package lain) SEBELUM sempat lihat @kematjaya/auth-ui
# mensyaratkan zod@>=4, lalu gagal ERESOLVE karena conflict versi mayor.
run_node_in_frontend npm install \
    @kematjaya/auth-ui @kematjaya/access-control-ui @kematjaya/bootstrap-ui-kit \
    bootstrap bootstrap-icons react-hook-form @hookform/resolvers "zod@^4"

echo -e "📦 ${GREEN}Menginstal openapi-typescript (dev)...${NC}"
run_node_in_frontend npm install --save-dev openapi-typescript

echo -e "📦 ${GREEN}Menginstal vitest + testing-library (dev, untuk tests/unit/*)...${NC}"
# tests/unit/bff.test.ts di-copy dari template di STEP 3 di bawah, tapi
# vitest/testing-library TIDAK datang dari create-next-app — tanpa ini
# testnya ke-copy tapi tidak pernah bisa dijalankan (no test runner).
run_node_in_frontend npm install --save-dev vitest @vitejs/plugin-react jsdom \
    @testing-library/react @testing-library/jest-dom @testing-library/user-event

# Di-pin (bukan "latest") supaya versi npm package ini SELALU cocok dengan
# tag image mcr.microsoft.com/playwright:v$PLAYWRIGHT_VERSION-noble yang
# dipakai service "playwright" one-off di compose.override.yaml (STEP 5) —
# browser yang di-bundle image itu harus persis sama versi dengan
# @playwright/test, kalau tidak playwright akan menolak jalan.
PLAYWRIGHT_VERSION="1.62.1"
echo -e "📦 ${GREEN}Menginstal @playwright/test@${PLAYWRIGHT_VERSION} (dev, untuk tests/e2e/*)...${NC}"
run_node_in_frontend npm install --save-dev "@playwright/test@${PLAYWRIGHT_VERSION}"

# ==========================================
# STEP 3 — Timpa file default create-next-app dengan template generik
# (login/register/dashboard/BFF routes/proxy.ts) — TIDAK ADA entity contoh
# di dalamnya, lihat bff-next/README.md.
# ==========================================
echo -e "📝 ${GREEN}Menyalin template frontend generik...${NC}"
cp -r "$TEMPLATE_DIR/src/." frontend/src/
cp "$TEMPLATE_DIR/Dockerfile" frontend/Dockerfile
cp "$TEMPLATE_DIR/.dockerignore" frontend/.dockerignore
mkdir -p frontend/scripts
cp "$TEMPLATE_DIR/scripts/generate-api-types.mjs" frontend/scripts/generate-api-types.mjs
cp "$TEMPLATE_DIR/scripts/generate-api-types-docker.sh" frontend/scripts/generate-api-types-docker.sh
chmod +x frontend/scripts/generate-api-types-docker.sh

# generate-api-types.mjs resolve backend lewat "../backend" (relatif dari
# frontend/scripts/) — sudah benar apa adanya karena project ini sekarang
# pakai layout backend/+frontend/ (bukan flat), jadi tidak perlu di-patch.

if [[ -d "$TEMPLATE_DIR/tests" ]]; then
    mkdir -p frontend/tests
    cp -r "$TEMPLATE_DIR/tests/." frontend/tests/
fi
if [[ -f "$TEMPLATE_DIR/vitest.config.ts" ]]; then
    cp "$TEMPLATE_DIR/vitest.config.ts" "$TEMPLATE_DIR/vitest.setup.ts" frontend/
fi
if [[ -f "$TEMPLATE_DIR/playwright.config.ts" ]]; then
    cp "$TEMPLATE_DIR/playwright.config.ts" frontend/
fi

echo -e "📝 ${GREEN}Menambahkan script api:types + nama project ke package.json...${NC}"
run_node_in_frontend node -e '
const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
pkg.name = `${process.env.PROJECT_NAME}-frontend`;
pkg.scripts = pkg.scripts || {};
pkg.scripts["api:types"] = "node scripts/generate-api-types.mjs";
pkg.scripts["api:types:check"] = "node scripts/generate-api-types.mjs --check";
pkg.scripts["test"] = "vitest run";
pkg.scripts["test:e2e"] = "playwright test";
fs.writeFileSync("package.json", JSON.stringify(pkg, null, 4) + "\n");
'

# ==========================================
# STEP 4 — src/config/auth.ts sudah env-driven (API_INTERNAL_URL/APP_ORIGIN),
# tidak perlu diedit — cukup pastikan compose.override.yaml set env yang
# sama seperti nama service backend ("php", bukan "backend" — lihat
# STEP 5 di bawah, beda dari compose.yaml.reference di bff-next/compose/).
# ==========================================

# ==========================================
# STEP 5 — compose.override.yaml: service "frontend" tambahan, TIDAK
# menyentuh compose.yaml yang sudah ditulis symfony.bash untuk backend —
# Docker Compose otomatis merge compose.yaml + compose.override.yaml kalau
# keduanya ada di direktori yang sama, tanpa perlu flag -f apa pun.
# ==========================================
FRONTEND_SERVICE_BLOCK='  frontend:
    build:
      context: ./frontend
      target: development
    depends_on:
      php:
        condition: service_started
    environment:
      NODE_ENV: development
      API_INTERNAL_URL: http://php:8082
      APP_ORIGIN: http://localhost:3000
      WATCHPACK_POLLING: "true"
    volumes:
      - ./frontend:/app
      - frontend_node_modules:/app/node_modules
      - frontend_next:/app/.next
    ports:
      - "3000:3000"
    command: ["npm", "run", "dev", "--", "--hostname", "0.0.0.0"]

  # Profile terpisah supaya TIDAK ikut jalan otomatis saat "docker compose up".
  # Jalankan eksplisit: docker compose --profile e2e run --rm playwright
  # (atau: make test-e2e). Image resmi Playwright dipakai (bukan service
  # "frontend" yang Alpine/musl) karena browser Playwright TIDAK kompatibel
  # dengan musl libc — lihat README.md.
  #
  # network_mode: service:frontend (BUKAN network biasa + hostname "frontend")
  # supaya Playwright bisa akses lewat "http://localhost:3000" — origin ini
  # HARUS persis sama dengan APP_ORIGIN service frontend di atas, karena BFF
  # route handler menolak request lintas-origin (proteksi CSRF). Kalau
  # Playwright mengakses via "http://frontend:3000", Origin header browser
  # jadi beda dari APP_ORIGIN dan semua POST (login/register/dst) ditolak 403.
  playwright:
    image: mcr.microsoft.com/playwright:v'"$PLAYWRIGHT_VERSION"'-noble
    profiles: ["e2e"]
    network_mode: "service:frontend"
    depends_on:
      - frontend
    working_dir: /app
    environment:
      PLAYWRIGHT_BASE_URL: http://localhost:3000
      PLAYWRIGHT_SKIP_WEB_SERVER: "1"
      PLAYWRIGHT_ADMIN_EMAIL: admin@example.com
      PLAYWRIGHT_ADMIN_PASSWORD: admin123
    volumes:
      - ./frontend:/app
      - playwright_node_modules:/app/node_modules
    command: sh -c "npm ci && npx playwright test"
'

if [[ -f compose.override.yaml ]] && grep -q '^  frontend:' compose.override.yaml; then
    echo -e "${YELLOW}--${NC} skipped compose.override.yaml (service 'frontend' sudah ada)"
elif [[ -f compose.override.yaml ]]; then
    # Symfony Flex sendiri suka menulis compose.override.yaml (mis. recipe
    # doctrine/doctrine-bundle nambah expose port database) — jangan ditimpa,
    # sisipkan service "frontend" di bawah "services:" yang sudah ada.
    echo -e "📝 ${GREEN}compose.override.yaml sudah ada (ditulis Flex) — menyisipkan service frontend...${NC}"
    if ! grep -q '^services:' compose.override.yaml; then
        echo -e "${RED}Error: compose.override.yaml ada tapi tidak punya baris 'services:' di awal — cek manual.${NC}"
        exit 1
    fi
    awk -v block="$FRONTEND_SERVICE_BLOCK" '
        /^services:/ { print; print block; next }
        { print }
    ' compose.override.yaml > compose.override.yaml.tmp
    mv compose.override.yaml.tmp compose.override.yaml
    if ! grep -q '^volumes:' compose.override.yaml; then
        {
            echo ''
            echo 'volumes:'
            echo '  frontend_node_modules:'
            echo '  frontend_next:'
            echo '  playwright_node_modules:'
        } >> compose.override.yaml
    fi
else
    echo -e "📝 ${GREEN}Menulis compose.override.yaml (service frontend)...${NC}"
    {
        echo 'services:'
        printf '%s' "$FRONTEND_SERVICE_BLOCK"
        echo ''
        echo 'volumes:'
        echo '  frontend_node_modules:'
        echo '  frontend_next:'
    } > compose.override.yaml
fi

# ==========================================
# STEP 6 — Build & jalankan
# ==========================================
echo -e "🐳 ${GREEN}Build & menjalankan container frontend...${NC}"
docker compose up -d --build frontend

echo -e "⏳ ${GREEN}Menunggu Next.js dev server siap...${NC}"
max_attempts=20
attempt=1
until docker compose exec -T frontend node -e "fetch('http://127.0.0.1:3000/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" >/dev/null 2>&1; do
    if [ $attempt -ge $max_attempts ]; then
        echo -e "${RED}❌ Frontend tidak siap setelah $((max_attempts * 3)) detik. Periksa log: docker compose logs frontend${NC}"
        exit 1
    fi
    echo -e "${YELLOW}⏳ Frontend belum siap, mencoba lagi (${attempt}/${max_attempts})...${NC}"
    attempt=$((attempt + 1))
    sleep 3
done

# ==========================================
# STEP 7 — Generate api.generated.ts (Docker-only, lihat catatan di script itu)
# ==========================================
echo -e "🔧 ${GREEN}Generate frontend/src/types/api.generated.ts dari OpenAPI backend...${NC}"
bash frontend/scripts/generate-api-types-docker.sh

echo ""
echo -e "${YELLOW}============================================================${NC}"
echo -e "${YELLOW}✅ Setup selesai!${NC}"
echo -e "${YELLOW}============================================================${NC}"
echo -e "🌐 Frontend: ${GREEN}http://localhost:3000${NC}"
echo -e "🌐 Backend:  ${GREEN}http://localhost:8082/api/docs${NC} (Swagger UI)"
echo ""
if [[ -f security-snippet.yaml ]]; then
    echo -e "${RED}⚠️  Ingat: security-snippet.yaml belum di-merge ke config/packages/security.yaml${NC}"
    echo -e "${RED}   (lihat instruksi di akhir output bin/user-setup.sh). Sebelum itu selesai,${NC}"
    echo -e "${RED}   login/register belum akan berfungsi.${NC}"
    echo ""
fi
echo -e "Coba register user baru lewat ${GREEN}http://localhost:3000/register${NC}"
echo -e "atau login pakai fixture: ${GREEN}admin@example.com / admin123${NC} atau ${GREEN}user@example.com / admin123${NC}"
echo -e "${YELLOW}============================================================${NC}"
