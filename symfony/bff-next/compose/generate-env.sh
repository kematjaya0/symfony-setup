#!/usr/bin/env bash
set -euo pipefail

# Generates the root .env for the combined backend+frontend compose.yaml
# (compose/compose.yaml.reference + compose.override.yaml.reference) from
# compose/.env.example — filling APP_SECRET, POSTGRES_PASSWORD, and
# JWT_PASSPHRASE with fresh random values instead of leaving the placeholder
# text ("replace-with-a-strong-password" / "replace-with-a-random-secret") or
# an empty JWT_PASSPHRASE (lexik/jwt-authentication-bundle refuses to boot
# with an empty passphrase for its RS256 keypair).
#
# Uses the exact same openssl-with-/dev/urandom-fallback technique
# symfony.bash itself already uses for DB_PASSWORD/DB_ROOT_PASSWORD — kept
# consistent on purpose, not a new convention.
#
# Usage: bash compose/generate-env.sh [--force] [<target-dir>]
#   --force        overwrite an existing .env instead of skipping it
#   <target-dir>   directory containing .env.example (default: this script's dir)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

FORCE=0
TARGET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        *) TARGET_DIR="$(cd "$arg" && pwd)" ;;
    esac
done

EXAMPLE_FILE="$TARGET_DIR/.env.example"
ENV_FILE="$TARGET_DIR/.env"

if [[ ! -f "$EXAMPLE_FILE" ]]; then
    echo -e "${RED}Error: $EXAMPLE_FILE tidak ditemukan.${NC}"
    exit 1
fi

if [[ -f "$ENV_FILE" && "$FORCE" -eq 0 ]]; then
    echo -e "${YELLOW}--${NC} skipped $ENV_FILE (sudah ada, pakai --force untuk timpa)"
    exit 0
fi

random_hex() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 16
    else
        # Fallback tanpa openssl: baca randomness asli dari /dev/urandom,
        # BUKAN hash dari timestamp (predictable). Pola sama seperti
        # symfony.bash pakai untuk DB_PASSWORD/DB_ROOT_PASSWORD.
        head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 32
    fi
}

APP_SECRET_VALUE="$(random_hex)"
POSTGRES_PASSWORD_VALUE="$(random_hex)"
JWT_PASSPHRASE_VALUE="$(random_hex)"

echo -e "🔑 ${GREEN}Generating APP_SECRET, POSTGRES_PASSWORD, JWT_PASSPHRASE acak...${NC}"

cp "$EXAMPLE_FILE" "$ENV_FILE"

# Ganti baris per baris (bukan sed dengan nilai langsung di pattern replace)
# supaya karakter hex apa pun di nilai random tidak pernah ditafsirkan
# sebagai sed metacharacter (nilai hex aman untuk & / ini juga, tapi
# konsisten dengan prinsip "jangan taruh secret di posisi replace sed" yang
# sudah didokumentasikan panjang lebar di symfony.bash).
while IFS= read -r line; do
    case "$line" in
        POSTGRES_PASSWORD=*) printf 'POSTGRES_PASSWORD=%s\n' "$POSTGRES_PASSWORD_VALUE" ;;
        APP_SECRET=*) printf 'APP_SECRET=%s\n' "$APP_SECRET_VALUE" ;;
        JWT_PASSPHRASE=*) printf 'JWT_PASSPHRASE=%s\n' "$JWT_PASSPHRASE_VALUE" ;;
        *) printf '%s\n' "$line" ;;
    esac
done < "$EXAMPLE_FILE" > "$ENV_FILE"

echo -e "✅ ${GREEN}$ENV_FILE ditulis${NC} dengan APP_SECRET/POSTGRES_PASSWORD/JWT_PASSPHRASE acak."
echo -e "${YELLOW}   .env ini akan berisi secret nyata — jangan commit ke git.${NC}"
