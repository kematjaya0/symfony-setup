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

echo "== Dev setup from host =="
docker compose up -d

# docker compose exec berjalan sebagai root di dalam container, sementara
# /app dimiliki UID host (dari composer:2 builder container yang -u
# $(id -u):$(id -g)) — tanpa ini, tiap `composer require` mencetak warning
# "detected dubious ownership" (noise, tidak fatal, tapi mengotori output).
docker compose exec -T php git config --global --add safe.directory /app

# `composer require` di dalam container jalan sebagai root, dan Flex recipe
# paket yang di-require sering ikut menulis file baru di config/ (mis.
# nelmio/cors-bundle menulis config/packages/nelmio_cors.yaml sendiri) —
# file itu jadi root-owned. Dipanggil ULANG setelah TIAP composer require
# yang diikuti host-side heredoc write (bukan cuma sekali di awal), karena
# tiap require bisa menciptakan file root-owned baru.
fix_ownership() {
    docker compose exec -T php sh -c "chown -R $(id -u):$(id -g) /app/src /app/tests /app/config" 2>/dev/null || true
    mkdir -p backend/config/packages backend/config/routes
    chmod -R u+rwX backend/src backend/tests backend/config 2>/dev/null || true
}

echo -e "📦 ${GREEN}Menginstal API Platform (kontrak JSON:API untuk frontend Next.js)...${NC}"
# symfony/twig-bundle WAJIB ikut di sini (bukan cuma api-platform/symfony +
# api-platform/doctrine-orm) — Swagger UI (/api/docs, halaman HTML-nya,
# BUKAN endpoint JSON-LD) di-render lewat Twig oleh ApiPlatform\Symfony\
# Bundle\SwaggerUi\SwaggerUiProcessor. Tanpa ini /api/docs 500 dengan pesan
# "The documentation cannot be displayed since the Twig bundle is not
# installed." — diverifikasi manual lewat generate nyata.
docker compose exec php composer require api-platform/symfony api-platform/doctrine-orm symfony/twig-bundle --no-interaction

echo "== Ensure project files are writable from host =="
fix_ownership

echo -e "📝 ${GREEN}Menulis config/packages/api_platform.yaml...${NC}"
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

echo -e "📝 ${GREEN}Mendaftarkan route API Platform...${NC}"
cat > backend/config/routes/api_platform.yaml <<'YAML'
api_platform:
    resource: .
    type: api_platform
    prefix: /api
YAML

echo -e "📝 ${GREEN}Menginstal nelmio/cors-bundle (frontend Next.js beda origin)...${NC}"
docker compose exec php composer require nelmio/cors-bundle --no-interaction
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

echo -e "\n${BLUE}==================================================${NC}"
echo -e "📦 ${GREEN}Menginstal kematjaya/auth-bundle...${NC}"
echo -e "${BLUE}==================================================${NC}"
# --no-scripts WAJIB di sini: composer.json app punya post-update-cmd yang
# otomatis jalankan cache:clear begitu package ke-require. Tapi bundle ini
# butuh App\Security\UserManager (ditulis oleh setup.sh di bawah) untuk bisa
# compile container — kalau cache:clear jalan SEBELUM setup.sh, container
# gagal compile ("Cannot autowire ... UserManagerInterface but no such
# service exists") dan composer require ikut exit non-zero. Urutan yang
# benar: require dulu tanpa scripts, baru setup.sh menulis file yang hilang,
# baru compile container (setup.sh sendiri diakhiri dengan
# doctrine:schema:update --force yang otomatis mengompilasi container).
docker compose exec php composer require kematjaya/auth-bundle --no-interaction --no-scripts

# Gap di auth-bundle/setup.sh: bundle ini bergantung ke 2 dependency Composer
# (lexik + gesdinet) yang masing-masing punya recipe Flex sendiri untuk
# registrasi bundle. lexik pakai recipe RESMI (selalu diterapkan otomatis),
# tapi gesdinet cuma punya recipe CONTRIB — dengan --no-interaction (wajib
# untuk installer non-interaktif) dan tanpa "allow-contrib": true, Flex
# DIAM-DIAM skip recipe itu ("IGNORING gesdinet/jwt-refresh-token-bundle").
# Harus didaftarkan manual SEBELUM vendor/kematjaya/auth-bundle/setup.sh
# jalan — soalnya setup.sh itu sendiri diakhiri dengan doctrine:schema:update
# yang butuh container compile, dan container gagal compile kalau bundle
# yang config fragmentnya (ditulis setup.sh) belum terdaftar.
echo -e "🔧 ${GREEN}Mendaftarkan GesdinetJWTRefreshTokenBundle (Flex contrib recipe di-skip saat non-interaktif)...${NC}"
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

echo -e "🔧 ${GREEN}Menjalankan installer bawaan bundle (User entity, JWT, .env)...${NC}"
docker compose exec php bash vendor/kematjaya/auth-bundle/setup.sh

echo -e "\n${BLUE}==================================================${NC}"
echo -e "📦 ${GREEN}Menginstal kematjaya/access-control-bundle...${NC}"
echo -e "${BLUE}==================================================${NC}"
docker compose exec php composer require kematjaya/access-control-bundle --no-interaction --no-scripts

echo -e "🔧 ${GREEN}Menjalankan installer RBAC (bin/access-control-setup.sh)...${NC}"
docker compose exec php bash bin/access-control-setup.sh
echo -e "\n📝 ${GREEN} Syncing the permissions manifest into the database"
php bin/console kematjaya:access-control:sync

# access-control-setup.sh sudah menulis config/permissions/default.yaml
# lengkap (Dashboard bawaan recipe bundle + Access Control ditambahkan
# access-control-setup.sh) dan sudah men-sync sendiri di akhir — tidak ada
# yang perlu ditambahkan lagi di sini.

echo -e "\n📝 ${GREEN}Membuat fixture user (root@example.com / user@example.com)...${NC}"
docker compose exec php composer require doctrine/doctrine-fixtures-bundle --dev --no-interaction
# Recipe doctrine/doctrine-fixtures-bundle sudah membuat stub kosong
# src/DataFixtures/AppFixtures.php (root, lewat docker compose exec) — chown
# ulang supaya host bisa menimpanya, lalu isi stub itu (bukan bikin file
# fixture baru) supaya cuma ada 1 fixture class.
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


# WAJIB clear cache dulu: recipe doctrine/doctrine-fixtures-bundle di atas
# sudah menjalankan cache:clear-nya sendiri TERHADAP stub kosong (constructor
# tanpa argumen) SEBELUM baris di atas menimpa file itu dengan constructor
# yang butuh UserPasswordHasherInterface. Tanpa clear ulang, container cache
# masih berisi definisi service lama -> ArgumentCountError saat fixtures:load.
docker compose exec php php bin/console cache:clear

echo -e "🔧 ${GREEN}menjalankan fixture load...${NC}"
docker compose exec php php bin/console doctrine:fixtures:load --no-interaction

echo ""
echo -e "${BLUE}🔐 Mencoba merge otomatis backend/config/packages/security.yaml...${NC}"
# Auto-merge HANYA untuk bentuk default persis yang ditulis recipe resmi
# symfony/security-bundle (diverifikasi manual sekali lewat generate nyata).
# Kalau bentuknya sudah beda (file di-custom manual), skip ke instruksi
# manual di bawah — jangan pernah menebak/menimpa buta.
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
    echo -e "📄 ${GREEN}backend/security-snippet.yaml${NC} ditulis — buka berdampingan"
    echo -e "   dengan ${GREEN}backend/config/packages/security.yaml${NC}, merge, lalu hapus file ini."
    echo ""
    echo -e "${GREEN}Setelah merge, restart php supaya security.yaml baru kepakai:${NC}"
    echo -e "   docker compose up -d --force-recreate php"
    echo ""
fi

echo -e "${YELLOW}============================================================${NC}"
echo -e "${YELLOW}✅ Backend siap. Langkah selanjutnya:${NC}"
echo -e "${YELLOW}============================================================${NC}"
echo -e "${GREEN}bash bin/frontend-setup.sh${NC}"
echo -e "${YELLOW}============================================================${NC}"
