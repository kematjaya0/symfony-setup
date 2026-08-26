# setup-script

Generator interaktif untuk membuat project Symfony baru yang **full-Docker**
sejak awal. Satu-satunya prasyarat di host adalah **Docker + Docker Compose
v2** — tidak perlu PHP, Composer, Symfony CLI, atau Node terinstal di mesin
lokal. Semua proses (`composer require`, migrasi database, testing, sampai
`npm install` untuk frontend) dijalankan lewat container.

## Instalasi cepat (one-liner)

Tanpa perlu clone manual dulu:

```bash
curl -fsSL https://raw.githubusercontent.com/kematjaya0/symfony-setup/main/install.sh | bash
```

Perintah ini meng-clone repo ini ke `~/.local/share/symfony-generator`,
memasang command pendek `symfony-new` di `~/.local/bin`, lalu langsung
menjalankan generator secara interaktif. Lain kali, tidak perlu `curl` lagi —
cukup:

```bash
symfony-new
```

(`symfony-new` otomatis `git pull` dulu setiap dipanggil, jadi selalu pakai
versi generator terbaru.) Override lokasi instalasi lewat env var
`SYMFONY_GEN_HOME` / `SYMFONY_GEN_BIN_DIR` kalau perlu.

`symfony.bash` sendiri BUKAN file tunggal — dia butuh folder `symfony/`
(template Docker/Symfony) yang ikut ter-clone, jadi tidak bisa dijalankan
lewat `curl ... | bash` secara langsung (beda dari installer binary
single-file seperti opencode). `install.sh` di atas ada khusus untuk
menjembatani itu: dia yang di-`curl | bash`, bukan `symfony.bash`-nya.

## Prasyarat

- Docker
- Docker Compose v2 (plugin `docker compose`, bukan `docker-compose` versi 1)
- git (hanya untuk metode instalasi one-liner di atas)
- python3 (opsional — dipakai `bin/security-setup.sh` tipe 2 dan
  `bin/user-setup.sh` tipe 3 untuk auto-merge `security.yaml`. Kalau tidak
  ada, bukan fatal — otomatis fallback ke instruksi merge manual, lihat
  [Error handling & cleanup](#error-handling--cleanup))

`symfony.bash` mengecek Docker & Docker Compose di awal dan berhenti dengan
pesan jelas kalau salah satu belum ada.

## Cara pakai (dari clone manual, interaktif)

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

## Struktur hasil generate (kerangka dasar, semua tipe)

Sebelum masuk ke detail per tipe — apa pun tipe project yang dipilih,
`symfony.bash` selalu menulis kerangka yang sama ini duluan (STEP 1 & 2 di
generator), baru setelah itu tipe-specific dependencies & helper script
ditambahkan di atasnya:

```
nama-project/
├── .docker/frankenphp/
│   ├── conf.d/app.ini
│   ├── conf.d/zzz-opcache-prod.ini
│   └── Caddyfile
├── .dockerignore
├── .env                  # kosong, placeholder (Symfony Flex convention)
├── .env.local             # DATABASE_URL + password acak (di-gitignore, TIDAK di compose.yaml)
├── bin/                    # helper setup pasca-generate — isinya beda per tipe, lihat di bawah
├── config/                 # config Symfony standar hasil Flex recipes
├── src/                    # kosong (cuma Kernel.php) sampai bin/*.sh dijalankan
├── tests/                  # PHPUnit, kosong sampai bin/*.sh dijalankan
├── Dockerfile               # multi-stage: base → dev → prod (FrankenPHP)
├── compose.yaml              # service: php, database, adminer (+ tambahan per tipe)
├── compose.prod.yaml
└── README.md                  # ditulis generator: kredensial, cara jalanin, next steps
```

`git init` juga sudah dijalankan di titik ini (belum ada commit — itu
keputusan user). Bagian di bawah ini fokus ke apa yang **berubah/bertambah**
dari kerangka dasar di atas untuk masing-masing tipe, termasuk file yang baru
muncul setelah helper script di `bin/` dijalankan.

## Tipe Project

### 1) REST API

Symfony minimal + Security, Serializer, Validator, `nelmio/cors-bundle`,
`nelmio/api-doc-bundle` (Swagger, BUKAN API Platform — endpoint ditulis
manual sebagai controller biasa), plus test-pack. Setelah generate:

```bash
cd nama-project
bash bin/user-setup.sh   # User entity + fixture + endpoint contoh GET /api/ping
bash bin/jwt-setup.sh    # JWT auth (lexik/jwt-authentication-bundle), keypair, firewall
```

- API: `http://localhost:8082`
- Dokumentasi API: `http://localhost:8082/api/doc`

**Struktur kode yang terbentuk** (`bin/user-setup.sh` lalu `bin/jwt-setup.sh`,
berurutan — kolom kanan menandai script mana yang menulis file itu):

```
nama-project/
├── bin/
│   ├── user-setup.sh              # dari symfony/api/setup.sh
│   └── jwt-setup.sh
├── config/
│   ├── jwt/                        # keypair RSA, dibuat lexik:jwt:generate-keypair  (jwt-setup.sh)
│   └── packages/
│       └── security.yaml            # firewall JWT untuk /api, ditulis ULANG total    (jwt-setup.sh)
├── src/
│   ├── Entity/User.php               # implements UserInterface                       (user-setup.sh)
│   ├── Repository/UserRepository.php                                                  (user-setup.sh)
│   ├── DataFixtures/UserFixtures.php  # admin@example.com / admin123                  (user-setup.sh)
│   └── Controller/Api/
│       ├── PingController.php         # GET /api/ping — public                        (user-setup.sh)
│       ├── LoginCheckController.php   # POST /api/login_check — dicegat json_login    (jwt-setup.sh)
│       └── MeController.php           # GET /api/me — contoh endpoint terproteksi     (jwt-setup.sh)
└── tests/
    └── UserFixturesTest.php                                                           (user-setup.sh)
```

`.env.local` juga dapat baris `JWT_PASSPHRASE` baru dari `jwt-setup.sh`
(generate acak, pola sama seperti `DB_PASSWORD` di kerangka dasar).

### 2) Web Application (Symfony UX)

`symfony/webapp-pack` + Stimulus/Turbo/Live Components (Twig, server-rendered,
tanpa API terpisah). Setelah generate:

```bash
cd nama-project
bash bin/user-setup.sh                                        # User entity + fixture, homepage redirect ke /login
docker compose exec php php bin/console make:security:form-login  # interaktif, generate SecurityController + login.html.twig
bash bin/security-setup.sh                                     # wiring backend + merge security.yaml
```

(Perintah `make:security:form-login` di tengah itu **wajib** dijalankan
manual sebelum `bin/security-setup.sh` — lihat instruksi yang dicetak di
akhir `bin/user-setup.sh`. `bin/security-setup.sh` men-diff bentuk default
hasil perintah itu; kalau formnya belum di-generate atau sudah di-custom,
auto-merge di-skip dan jatuh ke instruksi manual + `security-snippet.yaml`,
bukan mematikan script — lihat [Error handling](#error-handling--cleanup)
di bawah.)

- App: `http://localhost:8082`
- End-to-end testing (Playwright) sudah disiapkan, dua cara — lihat
  `README.md` di dalam project hasil generate untuk detailnya:
  - Docker: `docker compose --profile e2e run --rm playwright` (service
    `playwright` ini sudah ditambahkan langsung ke `compose.yaml` oleh
    `symfony.bash` sendiri, profile `e2e` supaya tidak ikut jalan otomatis
    saat `docker compose up`)
  - Native (kalau punya Node di host): `cd e2e && npm install && npx playwright test`

**Struktur kode yang terbentuk:**

```
nama-project/
├── bin/
│   ├── user-setup.sh                  # dari symfony/fullstack/setup.sh
│   └── security-setup.sh
├── e2e/                                 # Playwright — TERPISAH dari tests/ PHPUnit  (symfony.bash)
│   ├── package.json
│   ├── playwright.config.ts
│   └── tests/homepage.spec.ts
├── DESIGN.md                             # arah visual (dipakai prompt custom login) (symfony.bash)
├── config/
│   ├── packages/
│   │   ├── twig_component.yaml                                                      (symfony.bash)
│   │   └── security.yaml          # provider + form_login + access_control /backend (security-setup.sh)
│   └── routes.yaml                 # + import src/Controller/Backend/, prefix /backend (security-setup.sh)
├── src/
│   ├── Entity/User.php                                                              (user-setup.sh)
│   ├── Repository/UserRepository.php                                                (user-setup.sh)
│   ├── DataFixtures/UserFixtures.php                                                (user-setup.sh)
│   └── Controller/
│       ├── HomepageController.php     # "/" → redirect ke route "app_login"        (security-setup.sh)
│       ├── SecurityController.php     # dari make:security:form-login (manual)     (—)
│       └── Backend/DashboardController.php  # "/" dashboard, di-guard ROLE_ADMIN   (security-setup.sh)
├── templates/security/login.html.twig  # dari make:security:form-login, di-custom lewat
│                                          prompt AI Agent (instruksi dicetak di akhir security-setup.sh)
└── tests/UserFixturesTest.php                                                       (user-setup.sh)
```

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

**Struktur kode yang terbentuk** (backend FLAT di root — BUKAN folder
`backend/` — supaya `docker compose exec php ...` tetap jalan dari root
project seperti tipe lain):

```
nama-project/
├── bin/
│   ├── user-setup.sh                  # dari symfony/bff-next/user-setup.sh
│   ├── frontend-setup.sh
│   └── access-control-setup.sh        # dipanggil OTOMATIS dari dalam user-setup.sh
├── src/                                 # backend Symfony, flat
│   ├── Entity/User.php                                                       (vendor/kematjaya/auth-bundle/setup.sh)
│   ├── Security/UserManager.php         # UserManagerInterface                (auth-bundle/setup.sh)
│   └── DataFixtures/AppFixtures.php     # admin@example.com / user@example.com (user-setup.sh)
├── config/
│   ├── packages/
│   │   ├── api_platform.yaml                                                 (user-setup.sh)
│   │   ├── nelmio_cors.yaml                                                  (user-setup.sh)
│   │   ├── security.yaml           # JWT stateless, auto-merge (atau security-snippet.yaml manual)
│   │   └── kematjaya_access_control.yaml                                     (access-control-setup.sh)
│   ├── routes/
│   │   ├── api_platform.yaml        # prefix /api                            (user-setup.sh)
│   │   └── kematjaya_access_control.yaml                                     (access-control-setup.sh)
│   └── permissions/default.yaml      # manifest RBAC — menu "Admin" di-tambahkan (user-setup.sh)
├── tests/
├── frontend/                          # Next.js App Router — hasil create-next-app + template
│   ├── src/app/
│   │   ├── login/, register/, access-denied/                # halaman auth
│   │   ├── dashboard/                                          # layout + admin/access-control, profile
│   │   └── api/auth/*, api/me/*, api/permissions/*     # route handler BFF (proxy ke backend)
│   ├── src/lib/{bff,http,permissions,schemas}.ts       # helper BFF & validasi (zod)
│   ├── src/proxy.ts                                     # inti proxy request ke backend
│   ├── src/config/{auth,access-control}.ts              # env-driven, tidak perlu diedit manual
│   ├── scripts/generate-api-types.mjs                    # source utk `npm run api:types`
│   ├── tests/unit/bff.test.ts                            # Vitest
│   └── tests/e2e/{logout,navigation-role}.spec.ts        # Playwright
├── bff-next-template/frontend/         # SUMBER COPY untuk frontend-setup.sh — JANGAN diedit
│                                          manual, ke-timpa ulang tiap frontend-setup.sh dijalankan
├── compose.yaml                         # php, database, adminer               (symfony.bash)
├── compose.override.yaml                # + service frontend, playwright (profile e2e) (frontend-setup.sh)
├── compose.prod.yaml
└── Makefile                              # shortcut docker compose exec — lihat tabel di bawah
```

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

## Error handling & cleanup

Semua script di repo ini (`symfony.bash` dan seluruh `bin/*.sh` hasil
generate) pakai `set -Eeuo pipefail` + `trap ... ERR` yang sama: begitu ada
command yang gagal dan tidak sengaja dijaga (retry loop / `if`), proses
langsung berhenti dengan pesan `❌ Terjadi error pada baris N` — bukan lanjut
diam-diam dengan state yang setengah jadi.

**`symfony.bash` (generator utama) beda dari yang lain**: karena folder
project yang lagi di-generate dijamin baru dibuat SENDIRI oleh run itu (guard
"folder sudah ada" di awal), kegagalan di tengah jalan otomatis memicu
cleanup penuh lewat `trap ... EXIT` — bukan cuma pesan error:

- `docker compose down -v --remove-orphans` (kalau `compose.yaml` sudah
  sempat ditulis) — container, network, DAN volume database yang sempat
  dibuat `docker compose up -d` ikut hilang, supaya tidak jadi orphan
  permanen.
- `rm -rf` folder project yang gagal separuh jalan.
- Image Docker hasil build **sengaja tidak dihapus** (tidak ada `--rmi`) —
  biar percobaan berikutnya masih kena cache layer, sama seperti
  `COMPOSER_CACHE_HOST_DIR` yang sengaja dipertahankan lintas-run.
- Ctrl+C (`SIGINT`) dan `SIGTERM` di tengah proses ikut memicu cleanup yang
  sama, bukan cuma dibiarkan mati begitu saja.

Hasil akhirnya: kalau `symfony.bash` gagal di titik mana pun (network flaky,
port bentrok, dependency belum siap, dibatalkan manual), host kembali persis
seperti sebelum script dijalankan — tidak ada folder setengah jadi atau
container nyangkut yang perlu dibersihkan manual.

**`bin/*.sh` (helper pasca-generate: `user-setup.sh`, `jwt-setup.sh`,
`security-setup.sh`, `frontend-setup.sh`, `access-control-setup.sh`) SENGAJA
tidak melakukan hal yang sama.** Script-script ini jalan setelah project
sungguhan sudah berhasil di-generate — menghapus foldernya kalau salah satu
gagal di tengah jalan justru akan menghapus kerja Composer/Symfony yang
sudah valid. Sebagai gantinya:

- Tetap dapat pesan error yang jelas (`trap ... ERR`), tapi TIDAK ada
  `rm -rf` atau `docker compose down` otomatis.
- Semua ditulis idempotent by design (`cat >` overwrite penuh, guard
  `grep -q` sebelum `>>`, flag Doctrine seperti `--if-not-exists`/`--force`)
  — begitu root cause kegagalan diperbaiki, cukup jalankan ulang script yang
  sama, aman tanpa duplikasi.
- Kasus khusus: auto-merge `config/packages/security.yaml` (di
  `fullstack/security-setup.sh` dan `bff-next/user-setup.sh`) HANYA berlaku
  untuk bentuk default yang sudah diverifikasi. Kalau bentuknya beda (belum
  di-generate lewat `make:security:form-login`, atau sudah di-custom
  manual), auto-merge di-skip **tanpa mematikan script** — jatuh ke instruksi
  merge manual + file `security-snippet.yaml` yang ditulis di root project.

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
