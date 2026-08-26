# setup-script

Generator interaktif untuk membuat project Symfony baru yang **full-Docker**
sejak awal. Satu-satunya prasyarat di host adalah **Docker + Docker Compose
v2** — tidak perlu PHP, Composer, Symfony CLI, atau Node terinstal di mesin
lokal. Semua proses (`composer require`, migrasi database, testing, sampai
`npm install` untuk frontend) dijalankan lewat container.

## Prasyarat

- Docker
- Docker Compose v2 (plugin `docker compose`, bukan `docker-compose` versi 1)

`symfony.bash` mengecek keduanya di awal dan berhenti dengan pesan jelas
kalau salah satu belum ada.

## Cara pakai (interaktif)

```bash
bash symfony.bash
```

Script akan menanyakan 3 hal berurutan:

1. **Nama project** — bebas (boleh ada spasi/huruf besar), otomatis
   disanitasi jadi nama folder yang aman (lowercase, `-` sebagai pemisah).
   Nama ini juga dipakai konsisten untuk nama database dan (khusus tipe 3)
   nama package frontend serta judul API.
2. **Tipe project** — lihat [Tipe Project](#tipe-project) di bawah.
3. **Database** — `1` MySQL 8.0 atau `2` PostgreSQL 16.

Setelah dijawab, generator langsung: generate skeleton Symfony, install
dependency dasar sesuai tipe, tulis `Dockerfile`/`compose.yaml`/konfigurasi
FrankenPHP, generate kredensial acak (disimpan di `.env.local`, otomatis
di-gitignore — **bukan** di `compose.yaml`, jadi `compose.yaml` aman
di-commit), build & jalankan container, lalu tulis `README.md` di dalam
project yang baru dibuat.

## Cara pakai (non-interaktif / scripted)

Ketiga jawaban bisa langsung di-pipe lewat `printf`, urutannya sama seperti
prompt di atas (`nama\ntipe\ndatabase\n`):

```bash
# REST API + MySQL
printf 'nama-project\n1\n1\n' | bash symfony.bash

# Web Application (Symfony UX) + PostgreSQL
printf 'nama-project\n2\n2\n' | bash symfony.bash

# Full-stack (Symfony API + Next.js) + PostgreSQL
printf 'nama-project\n3\n2\n' | bash symfony.bash
```

Berguna untuk testing generator itu sendiri atau otomasi lain — lihat
`AGENTS.md` untuk pola smoke-test yang dipakai di repo ini.

## Tipe Project

### 1) REST API

Symfony minimal + API Platform-style stack: ORM, Security, Serializer,
Validator, `nelmio/cors-bundle`, `nelmio/api-doc-bundle`, plus test-pack.
Setelah generate:

```bash
cd nama-project
bash bin/user-setup.sh   # User entity + fixture + endpoint contoh GET /api/ping
bash bin/jwt-setup.sh    # JWT auth (lexik/jwt-authentication-bundle), keypair, firewall
```

- API: `http://localhost:8082`
- Dokumentasi API: `http://localhost:8082/api/doc`

### 2) Web Application (Symfony UX)

`symfony/webapp-pack` + Stimulus/Turbo/Live Components (Twig, server-rendered,
tanpa API terpisah). Setelah generate:

```bash
cd nama-project
bash bin/user-setup.sh       # User entity + fixture, homepage redirect ke /login
bash bin/security-setup.sh   # Form login Symfony
```

- App: `http://localhost:8082`
- End-to-end testing (Playwright) sudah disiapkan, dua cara — lihat
  `README.md` di dalam project hasil generate untuk detailnya:
  - Docker: `docker compose --profile e2e run --rm playwright`
  - Native (kalau punya Node di host): `cd e2e && npm install && npx playwright test`

### 3) Full-stack: Symfony API + Next.js

Backend API Platform + auth JWT (`kematjaya/auth-bundle`) + RBAC
(`kematjaya/access-control-bundle`) otomatis, plus frontend Next.js fresh
yang sudah di-wiring ke package tersebut (`@kematjaya/auth-ui`,
`@kematjaya/access-control-ui`, `@kematjaya/bootstrap-ui-kit`). Setelah
generate, jalankan **berurutan** (langkah kedua butuh backend sudah hidup):

```bash
cd nama-project
bash bin/user-setup.sh       # API Platform, auth-bundle, access-control-bundle,
                              # fixture user, auto-merge security.yaml
bash bin/frontend-setup.sh   # generate Next.js fresh + wiring auth-ui/access-control-ui
```

- Frontend: `http://localhost:3000`
- Backend Swagger UI: `http://localhost:8082/api/docs`
- Adminer: `http://localhost:9000`
- Login fixture: `admin@example.com` / `admin123` (ROLE_ADMIN) atau
  `user@example.com` / `admin123` (ROLE_USER), atau register user baru
  lewat `http://localhost:3000/register`.

Project hasil generate juga dapat `Makefile` (shortcut `make dev`,
`make console <cmd>`, `make composer <cmd>`, `make test-backend`,
`make test-frontend`, `make test-e2e`, `make lint`, dll — semuanya
pembungkus `docker compose exec`, tidak butuh PHP/Node di host). Detail
lengkap ada di `README.md` project hasil generate.

## Setelah generate (semua tipe)

- **Production**: `docker compose -f compose.yaml -f compose.prod.yaml up -d --build`
  (worker mode FrankenPHP aktif, source di-COPY ke image, tanpa bind-mount).
- **Console/Composer tanpa PHP di host**:
  ```bash
  docker compose exec php bin/console <perintah>
  docker compose exec php composer require <package>
  ```
- **Cleanup total** (hapus container + volume, termasuk data database):
  ```bash
  docker compose down -v
  ```

## Struktur repo ini

```
setup-script/
├── symfony.bash          # Generator utama — satu-satunya file yang dijalankan user
└── symfony/
    ├── common/            # File shared lintas tipe (Dockerfile base, FrankenPHP conf, dst)
    ├── api/                # Template + helper script khusus tipe 1 (REST API)
    ├── fullstack/          # Template + helper script khusus tipe 2 (Web Application)
    └── bff-next/           # Template + helper script khusus tipe 3 (Symfony API + Next.js)
```

Untuk kontribusi/development generator ini sendiri (konvensi kode, cara
testing perubahan pada `symfony.bash`), lihat `AGENTS.md`.
