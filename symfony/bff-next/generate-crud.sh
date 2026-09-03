#!/usr/bin/env bash
set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

trap 'echo -e "\n${RED}Terjadi error pada baris $LINENO. Proses dihentikan.${NC}"' ERR

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || -z "${1:-}" ]]; then
    cat <<'HELP'
Usage: npm run generate -- <EntityName>
   or: bash bin/generate-crud.sh <EntityName>

Generate CRUD lengkap (backend API Platform + frontend Next.js) untuk satu
entity Doctrine yang SUDAH ADA (buat dulu lewat make:entity kalau belum).

<EntityName> harus persis nama class entity-nya (PascalCase, tanpa namespace),
mis. "Note" untuk App\Entity\Note — sama seperti nama file di
backend/crud-specs/ (lihat Category.json, News.json).
HELP
    if [[ -z "${1:-}" ]]; then
        echo -e "${RED}Error: nama entity wajib diisi.${NC}" >&2
        exit 1
    fi
    exit 0
fi

ENTITY="$1"

echo -e "🛠️  ${GREEN}[1/4] Generate backend CRUD (make:kmj-api-crud) untuk ${ENTITY}...${NC}"
docker compose exec php bin/console make:kmj-api-crud "$ENTITY"

SPEC_FILE="backend/crud-specs/${ENTITY}.json"
if [[ ! -f "$SPEC_FILE" ]]; then
    echo -e "${RED}Error: ${SPEC_FILE} tidak ditemukan setelah make:kmj-api-crud.${NC}" >&2
    echo -e "${YELLOW}Cek: nama entity harus PERSIS sama (case-sensitive) dengan nama class entity-nya.${NC}" >&2
    exit 1
fi

echo -e "🔧 ${GREEN}[2/4] Regenerate frontend/src/types/api.generated.ts dari OpenAPI backend...${NC}"
bash frontend/scripts/generate-api-types-docker.sh

echo -e "🛠️  ${GREEN}[3/4] Generate frontend CRUD UI (crud-ui-generator) untuk ${ENTITY}...${NC}"
(cd frontend && npx @kematjaya/crud-ui-generator "../${SPEC_FILE}")

echo -e "🛠️  ${GREEN}[3/4] Sync access control...${NC}"
docker compose exec php bin/console kematjaya:access-control:sync

echo ""
echo -e "${GREEN}Selesai.${NC} Cek next-steps yang di-print make:kmj-api-crud di atas (mis. #[ApiResource] manual kalau ada), lalu:"
echo -e "  ${YELLOW}npm run lint${NC}   # frontend/npm run format juga disarankan (file hasil generate belum di-Prettier)"
