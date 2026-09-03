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
# Nama folder project = nama yang di-sanitasi symfony.bash dari input user —
# dipakai di bawah supaya judul API Platform tidak generic "API".
PROJECT_NAME="$(basename "$ROOT_DIR")"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage: bash bin/user-setup.sh

Dev-only bootstrap from host (tipe project: Full-stack Symfony API + Next.js):
- starts Docker Compose
- installs API Platform (JSON:API contract the Next.js frontend consumes)
- installs kematjaya/auth-bundle, runs its own vendor/.../setup.sh
  (writes User entity/repository/manager, JWT config+keypair, .env vars)
- installs kematjaya/access-control-bundle, runs bin/access-control-setup.sh
  (writes RBAC config + starter permission manifest)
- writes UserFixtures (root@example.com / user@example.com) + loads them
- prints the ONE manual step neither bundle automates (security.yaml merge)
- prints the next command: bash bin/frontend-setup.sh
HELP
    exit 0
fi

echo -e "📦 ${YELLOW} == Dev setup from host == ${NC}"
docker compose up -d

docker compose exec -T php git config --global --add safe.directory /app

fix_ownership() {
    docker compose exec -T php sh -c "chown -R $(id -u):$(id -g) /app/src /app/tests /app/config" 2>/dev/null || true
    mkdir -p backend/config/packages backend/config/routes
    chmod -R u+rwX backend/src backend/tests backend/config 2>/dev/null || true
}

echo -e "📦 ${YELLOW} == Menginstal API Platform (kontrak JSON:API untuk frontend Next.js)...${NC}"

docker compose exec php composer require api-platform/symfony api-platform/doctrine-orm symfony/twig-bundle symfony/expression-language nelmio/cors-bundle --no-interaction

echo -e "📦 ${YELLOW} == Ensure project files are writable from host == ${NC}"
fix_ownership

echo -e "📝 ${YELLOW} == Menulis config/packages/api_platform.yaml...${NC}"
cat > backend/config/packages/api_platform.yaml <<YAML
api_platform:
    title: $PROJECT_NAME API
    version: 1.0.0
    enable_swagger_ui: true
    formats:
        jsonld: ['application/ld+json']
        json: ['application/json']
    defaults:
        stateless: true
        pagination_client_items_per_page: true
        pagination_items_per_page: 30
        pagination_maximum_items_per_page: 50
        cache_headers:
            vary: ['Content-Type', 'Authorization', 'Origin']
YAML

echo -e "📝 ${YELLOW}== Mendaftarkan route API Platform...${NC}"
cat > backend/config/routes/api_platform.yaml <<'YAML'
api_platform:
    resource: .
    type: api_platform
    prefix: /api
YAML

echo -e "📝 ${YELLOW} == Setup nelmio/cors-bundle (frontend Next.js beda origin)...${NC}"
# nelmio/cors-bundle punya Flex recipe sendiri yang ikut menulis
# config/packages/nelmio_cors.yaml (root-owned) — chown ulang sebelum host
# menimpanya, lihat catatan fix_ownership() di atas.
fix_ownership
cat > backend/config/packages/nelmio_cors.yaml <<'YAML'
nelmio_cors:
    defaults:
        origin_regex: true
        allow_origin: ['%env(CORS_ALLOW_ORIGIN)%']
        allow_methods: ['GET', 'OPTIONS', 'POST', 'PUT', 'PATCH', 'DELETE']
        allow_headers: ['Content-Type', 'Authorization']
        expose_headers: ['Link']
        max_age: 3600
    paths:
        '^/api/': null
YAML

echo -e "📦 ${YELLOW} == Setup kematjaya/auth-bundle...${NC}"

docker compose exec php composer require kematjaya/auth-bundle kematjaya/access-control-bundle --no-interaction --no-scripts

echo -e "🔧 ${YELLOW} == Mendaftarkan GesdinetJWTRefreshTokenBundle (Flex contrib recipe di-skip saat non-interaktif)...${NC}"
if grep -q 'GesdinetJWTRefreshTokenBundle::class' backend/config/bundles.php; then
    echo -e "${YELLOW}--${NC} skipped config/bundles.php (entry sudah ada)"
else
    docker compose exec -T php php -r '
        $file = "config/bundles.php";
        $contents = file_get_contents($file);
        $entry = "    Gesdinet\\JWTRefreshTokenBundle\\GesdinetJWTRefreshTokenBundle::class => [\x27all\x27 => true],\n";
        $updated = preg_replace("/return \[\n/", "return [\n" . $entry, $contents, 1, $count);
        if ($count !== 1) { fwrite(STDERR, "gagal edit config/bundles.php\n"); exit(1); }
        file_put_contents($file, $updated);
    '
fi

echo -e "🔧 ${YELLOW}== Menjalankan installer bawaan bundle (User entity, JWT, .env)...${NC}"
docker compose exec php bash vendor/kematjaya/auth-bundle/setup.sh

echo -e "📦 ${YELLOW} Setup kematjaya/access-control-bundle...${NC}"
docker compose exec php composer require  --no-interaction --no-scripts

echo -e "🔧 ${YELLOW}== Menjalankan installer RBAC (bin/access-control-setup.sh)...${NC}"
docker compose exec php bash bin/access-control-setup.sh

echo -e "\n📝 ${YELLOW}== Membuat fixture user (root@example.com / user@example.com)...${NC}"
docker compose exec php composer require doctrine/doctrine-fixtures-bundle kematjaya/crud-maker-api-bundle --dev --no-interaction

echo -e "🔧 ${YELLOW} == Mendaftarkan CrudMakerApiBundle (Flex recipe di-skip saat non-interaktif)...${NC}"
if grep -q 'CrudMakerBundle\\\\Api\\\\CrudMakerApiBundle::class' backend/config/bundles.php; then
    echo -e "${YELLOW}--${NC} skipped config/bundles.php (entry sudah ada)"
else
    docker compose exec -T php php -r '
        $file = "config/bundles.php";
        $contents = file_get_contents($file);
        $entry = "    Kematjaya\\\\CrudMakerBundle\\\\Api\\\\CrudMakerApiBundle::class => [\x27dev\x27 => true, \x27test\x27 => true],\n";
        $updated = preg_replace("/return \[\n/", "return [\n" . $entry, $contents, 1, $count);
        if ($count !== 1) { fwrite(STDERR, "gagal edit config/bundles.php\n"); exit(1); }
        file_put_contents($file, $updated);
    '
fi

fix_ownership
mkdir -p backend/src/DataFixtures
cat > backend/src/DataFixtures/AppFixtures.php <<'PHP'
<?php

namespace App\DataFixtures;

use App\Entity\User;
use Doctrine\Bundle\FixturesBundle\Fixture;
use Doctrine\Persistence\ObjectManager;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;

class AppFixtures extends Fixture
{
    public function __construct(private readonly UserPasswordHasherInterface $passwordHasher)
    {
    }

    public function load(ObjectManager $manager): void
    {
        $admin = new User('root@example.com');
        $admin->setRoles(['ROLE_ADMIN']);
        $admin->setPassword($this->passwordHasher->hashPassword($admin, 'admin123'));
        $manager->persist($admin);

        $user = new User('user@example.com');
        $user->setRoles(['ROLE_USER']);
        $user->setPassword($this->passwordHasher->hashPassword($user, 'admin123'));
        $manager->persist($user);

        $manager->flush();
    }
}
PHP


docker compose exec php php bin/console cache:clear

echo -e "🔧 ${YELLOW} Menjalankan fixture load...${NC}"
docker compose exec php php bin/console doctrine:fixtures:load --no-interaction
echo -e "\n📝 ${YELLOW} Syncing the permissions into the database"
docker compose exec php php bin/console kematjaya:access-control:sync

echo ""
echo -e "${YELLOW}🔐 Mencoba merge otomatis backend/config/packages/security.yaml...${NC}"

if python3 - <<'PY'
from pathlib import Path
import sys

path = Path('backend/config/packages/security.yaml')
text = path.read_text()

markers = [
    'providers:\n        users_in_memory: { memory: null }',
    'main:\n            lazy: true\n            provider: users_in_memory',
]
if not all(m in text for m in markers):
    sys.exit(1)

text = text.replace(
    'security:\n',
    'security:\n    role_hierarchy:\n        ROLE_ADMIN: ROLE_USER\n\n',
    1,
)
text = text.replace(
    '    providers:\n        users_in_memory: { memory: null }\n',
    '    providers:\n        app_user_provider:\n            entity:\n                class: App\\Entity\\User\n                property: email\n',
    1,
)

old_main = '''        main:
            lazy: true
            provider: users_in_memory

            # Activate different ways to authenticate:
            # https://symfony.com/doc/current/security.html#the-firewall

            # https://symfony.com/doc/current/security/impersonating_user.html
            # switch_user: true
'''
new_main = '''        main:
            stateless: true
            provider: app_user_provider
            entry_point: jwt
            json_login:
                check_path: kematjaya_auth_login
                username_path: email
                password_path: password
                success_handler: lexik_jwt_authentication.handler.authentication_success
                failure_handler: lexik_jwt_authentication.handler.authentication_failure
            refresh_jwt:
                check_path: kematjaya_auth_refresh
                invalidate_token_on_logout: true
            jwt: ~
'''
if old_main not in text:
    sys.exit(1)
text = text.replace(old_main, new_main, 1)

old_ac = '''    access_control:
        # - { path: ^/admin, roles: ROLE_ADMIN }
        # - { path: ^/profile, roles: ROLE_USER }
'''
new_ac = '''    access_control:
        - { path: ^/api/docs, roles: PUBLIC_ACCESS }
        - { path: ^/api/register$, roles: PUBLIC_ACCESS }
        - { path: ^/api/login$, roles: PUBLIC_ACCESS }
        - { path: ^/api/token/refresh$, roles: PUBLIC_ACCESS }
        - { path: ^/api/logout$, roles: PUBLIC_ACCESS }
        - { path: ^/api, roles: ROLE_USER }
'''
if old_ac not in text:
    sys.exit(1)
text = text.replace(old_ac, new_ac, 1)

path.write_text(text)
PY
then
    echo -e "✅ ${GREEN}backend/config/packages/security.yaml berhasil di-merge otomatis.${NC}"
    echo -e "🔄 ${GREEN}Restart php supaya security.yaml baru kepakai...${NC}"
    docker compose up -d --force-recreate php
else
    echo -e "${YELLOW}============================================================${NC}"
    echo -e "${YELLOW}⚠️  LANGKAH MANUAL WAJIB: merge security.yaml${NC}"
    echo -e "${YELLOW}============================================================${NC}"
    echo -e "${BLUE}backend/config/packages/security.yaml sudah beda dari bentuk default${NC}"
    echo -e "${BLUE}symfony/security-bundle (mungkin sudah di-custom) — auto-merge${NC}"
    echo -e "${BLUE}di-skip supaya tidak menimpa buta. Merge manual, bandingkan:${NC}"
    echo ""
    echo -e "  ${GREEN}backend/config/packages/security.yaml${NC} (punya app)"
    echo -e "  ${GREEN}vs. backend/security-snippet.yaml${NC} yang ditulis installer ini di bawah"
    echo ""
    cat > backend/security-snippet.yaml <<'YAML'
# NOT auto-merged — deliberately manual. Merge blok di bawah ke
# config/packages/security.yaml (ganti, bukan tambah, kalau nama block sudah
# ada dari recipe symfony/security-bundle: role_hierarchy, password_hashers,
# providers, firewalls.dev, firewalls.main, access_control).
#
# Catatan: hanya rule access_control PERTAMA yang cocok yang dipakai — rule
# "^/api" harus tetap PALING BAWAH.

security:
    role_hierarchy:
        ROLE_ADMIN: ROLE_USER

    password_hashers:
        Symfony\Component\Security\Core\User\PasswordAuthenticatedUserInterface: 'auto'

    providers:
        app_user_provider:
            entity:
                class: App\Entity\User
                property: email

    firewalls:
        dev:
            pattern: ^/(_profiler|_wdt|assets|build)/
            security: false
        main:
            stateless: true
            provider: app_user_provider
            entry_point: jwt
            json_login:
                check_path: kematjaya_auth_login
                username_path: email
                password_path: password
                success_handler: lexik_jwt_authentication.handler.authentication_success
                failure_handler: lexik_jwt_authentication.handler.authentication_failure
            refresh_jwt:
                check_path: kematjaya_auth_refresh
                invalidate_token_on_logout: true
            jwt: ~

    access_control:
        - { path: ^/api/docs, roles: PUBLIC_ACCESS }
        - { path: ^/api/register$, roles: PUBLIC_ACCESS }
        - { path: ^/api/login$, roles: PUBLIC_ACCESS }
        - { path: ^/api/token/refresh$, roles: PUBLIC_ACCESS }
        - { path: ^/api/logout$, roles: PUBLIC_ACCESS }
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
    echo -e "📄 ${GREEN} backend/security-snippet.yaml${NC} ditulis — buka berdampingan"
    echo -e "   dengan ${GREEN}backend/config/packages/security.yaml${NC}, merge, lalu hapus file ini."
    echo ""
    echo -e "${GREEN} Setelah merge, restart php supaya security.yaml baru kepakai:${NC}"
    echo -e "   docker compose up -d --force-recreate php"
    echo ""
fi

echo -e "${YELLOW}============================================================${NC}"
echo -e "${YELLOW}✅ Backend siap. Langkah selanjutnya:${NC}"
echo -e "${YELLOW}============================================================${NC}"
echo -e "${GREEN}bash bin/frontend-setup.sh${NC}"
echo -e "${YELLOW}============================================================${NC}"
