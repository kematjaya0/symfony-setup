#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "📦 ${GREEN}Menginstal lexik/jwt-authentication-bundle...${NC}"
docker compose exec php composer require lexik/jwt-authentication-bundle --no-interaction

echo -e "🔑 ${GREEN}Menggenerate JWT_PASSPHRASE acak dan menyimpannya di .env.local...${NC}"
if command -v openssl >/dev/null 2>&1; then
    JWT_PASSPHRASE=$(openssl rand -hex 16)
else
    # Fallback tanpa openssl: baca randomness asli dari /dev/urandom, sama
    # seperti pola yang dipakai symfony.bash untuk DB_PASSWORD.
    JWT_PASSPHRASE=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 32)
fi

# .env.local sudah dipakai symfony.bash untuk kredensial database (gitignored,
# di-inject ke container php lewat env_file di compose.yaml). JWT_PASSPHRASE
# ditambahkan di sini dengan pola yang sama, bukan hardcode di file lain.
if grep -q '^JWT_PASSPHRASE=' .env.local 2>/dev/null; then
    tmp_env_local=$(mktemp)
    grep -v '^JWT_PASSPHRASE=' .env.local > "$tmp_env_local"
    mv "$tmp_env_local" .env.local
fi
echo "JWT_PASSPHRASE=$JWT_PASSPHRASE" >> .env.local

echo -e "🔄 ${GREEN}Recreate container php supaya JWT_PASSPHRASE baru ke-load...${NC}"
docker compose up -d --force-recreate php

echo -e "🔑 ${GREEN}Menggenerate JWT keypair...${NC}"
docker compose exec php php bin/console lexik:jwt:generate-keypair --overwrite

echo -e "🔐 ${GREEN}Menulis config/packages/security.yaml (firewall JWT untuk /api)...${NC}"
mkdir -p config/packages
cat > config/packages/security.yaml <<'YAML'
security:
    password_hashers:
        Symfony\Component\Security\Core\User\PasswordAuthenticatedUserInterface: 'auto'

    providers:
        app_user_provider:
            entity:
                class: App\Entity\User
                property: email

    firewalls:
        dev:
            pattern: ^/(_(profiler|wdt)|css|images|js)/
            security: false
        api_login:
            pattern: ^/api/login
            stateless: true
            json_login:
                check_path: /api/login_check
                username_path: email
                password_path: password
                success_handler: lexik_jwt_authentication.handler.authentication_success
                failure_handler: lexik_jwt_authentication.handler.authentication_failure
        api:
            pattern: ^/api
            stateless: true
            jwt: ~

    access_control:
        - { path: ^/api/login, roles: PUBLIC_ACCESS }
        - { path: ^/api/ping, roles: PUBLIC_ACCESS }
        - { path: ^/api, roles: ROLE_USER }

when@test:
    security:
        password_hashers:
            Symfony\Component\Security\Core\User\PasswordAuthenticatedUserInterface:
                algorithm: auto
                cost: 4
                time_cost: 3
                memory_cost: 10
YAML

echo -e "📝 ${GREEN}Mendaftarkan route eksplisit untuk /api/login_check...${NC}"
mkdir -p src/Controller/Api
cat > src/Controller/Api/LoginCheckController.php <<'PHP'
<?php

namespace App\Controller\Api;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

/**
 * Route ini SENGAJA didaftarkan meski secara konsep check_path json_login
 * biasanya tidak butuh controller — di Symfony 8 request ke path yang tidak
 * terdaftar di router bisa langsung 404 sebelum firewall "api_login" sempat
 * mencegat. Body method ini seharusnya TIDAK PERNAH benar-benar tereksekusi:
 * kalau sampai kepanggil berarti JsonLoginAuthenticator gagal mencegat.
 */
class LoginCheckController extends AbstractController
{
    #[Route('/api/login_check', name: 'api_login_check', methods: ['POST'])]
    public function __invoke(): JsonResponse
    {
        return $this->json(['message' => 'Invalid credentials.'], 401);
    }
}
PHP

echo -e "📝 ${GREEN}Membuat contoh endpoint terproteksi GET /api/me...${NC}"
mkdir -p src/Controller/Api
cat > src/Controller/Api/MeController.php <<'PHP'
<?php

namespace App\Controller\Api;

use App\Entity\User;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\CurrentUser;

class MeController extends AbstractController
{
    #[Route('/api/me', name: 'api_me', methods: ['GET'])]
    public function __invoke(#[CurrentUser] ?User $user): JsonResponse
    {
        return $this->json([
            'email' => $user?->getEmail(),
            'roles' => $user?->getRoles() ?? [],
        ]);
    }
}
PHP

echo -e "🔄 ${GREEN}Restart php supaya security.yaml baru kepakai...${NC}"
docker compose up -d --force-recreate php

echo ""
echo -e "${YELLOW}============================================================${NC}"
echo -e "${YELLOW}✅ JWT auth siap. Contoh pemakaian (fixture: admin@example.com / admin123):${NC}"
echo -e "${YELLOW}============================================================${NC}"
echo ""
echo -e "${GREEN}1. Login, ambil token:${NC}"
echo '   curl -s -X POST http://localhost:8082/api/login_check \'
echo '     -H "Content-Type: application/json" \'
echo '     -d '"'"'{"email":"admin@example.com","password":"admin123"}'"'"
echo ""
echo -e "${GREEN}2. Akses endpoint terproteksi pakai token dari langkah 1:${NC}"
echo '   curl -s http://localhost:8082/api/me -H "Authorization: Bearer <token>"'
echo ""
echo -e "${YELLOW}============================================================${NC}"
