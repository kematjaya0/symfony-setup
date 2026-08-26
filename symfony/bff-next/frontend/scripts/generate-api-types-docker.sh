#!/usr/bin/env bash
set -euo pipefail

# Docker-only alternative to `npm run api:types` for a bff-next-generated
# project. `npm run api:types` (frontend/scripts/generate-api-types.mjs)
# calls the `php` and `openapi-typescript` binaries directly via
# execFile() — fine when both are installed on the host (the assumption the
# original boilerplate this was copied from makes), but NOT fine here:
# setup-script's rule is Docker-only, and php (backend container) and Node
# (frontend container) are two separate containers with no shared binary.
#
# This script does the same 2 steps, each in the container that actually has
# the binary, with the OpenAPI JSON handed off via a host-side file (both
# containers bind-mount parts of the same project directory).
#
# Run from the PROJECT ROOT (parent of frontend/), after `docker compose up -d`.

GREEN='\033[0;32m'
NC='\033[0m'

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

echo -e "${GREEN}==>${NC} Exporting OpenAPI spec from backend (php container)..."
docker compose exec php php bin/console api:openapi:export --spec-version=3 --output=openapi.json --no-interaction

echo -e "${GREEN}==>${NC} Handing the spec off to the frontend container..."
# --output=openapi.json ditulis relatif ke WORKDIR container php (/app), yang
# di-mount dari backend/ (layout backend/+frontend/) — BUKAN dari project
# root. File-nya karena itu muncul di host sebagai backend/openapi.json.
mv backend/openapi.json frontend/openapi.json

echo -e "${GREEN}==>${NC} Generating frontend/src/types/api.generated.ts..."
docker compose exec frontend npx openapi-typescript openapi.json -o src/types/api.generated.ts

rm -f frontend/openapi.json
echo -e "${GREEN}==>${NC} Done: frontend/src/types/api.generated.ts regenerated."
