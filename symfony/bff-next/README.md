# bff-next — Template & Rangkuman untuk Tipe Project "Symfony API + Next.js"

Dibuat: 2026-08-24, hasil analisa `~/Projects/PHP/boilerplate` (Symfony + Next.js
+ auth + RBAC yang sudah production-proven, baru saja dibersihkan dari entity
contoh Notes/News). Ini PROJECT_TYPE ke-3 `symfony.bash` (menu "3) Full-stack:
Symfony API + Next.js"), sejajar dengan `symfony/api/` (REST API) dan
`symfony/fullstack/` (Symfony+Twig) — tapi backend REST API + frontend
Next.js, **di-generate fresh** (bukan clone tarball boilerplate), supaya tidak
pernah terkunci ke 1 versi Symfony/Next.js tertentu. Sudah di-wire penuh dan
diverifikasi end-to-end — lihat bagian "Sudah di-wire" di bawah.

## Kenapa tidak clone tarball boilerplate

`~/Projects/PHP/boilerplate` adalah project nyata yang berkembang — kalau
di-tarball, hasil generate akan beku di versi Symfony/Next.js/dependency saat
tarball itu dibuat. Sebagai gantinya: backend tetap `composer create-project
symfony/skeleton` fresh (pola yang sama persis dengan `symfony.bash` yang
sudah ada), frontend `create-next-app` fresh — **auth & RBAC-nya baru datang
dari `kematjaya/auth-bundle` + `kematjaya/access-control-bundle` (Composer,
sudah publish) dan `@kematjaya/auth-ui` + `@kematjaya/access-control-ui` +
`@kematjaya/bootstrap-ui-kit` (npm, sudah publish)** — keempatnya package
independen dengan semver sendiri, jadi otomatis kompatibel dengan Symfony/Next
versi apa pun yang baru di-generate. Tidak ada snapshot yang dibekukan.

## Temuan penting: backend auth SUDAH ada installer-nya sendiri

`vendor/kematjaya/auth-bundle/setup.sh` (dibawa otomatis begitu
`composer require kematjaya/auth-bundle`) sudah mengotomasi ~90% wiring:
- Registrasi bundle di `config/bundles.php`
- Copy `lexik_jwt_authentication.yaml`, `gesdinet_jwt_refresh_token.yaml`,
  `kematjaya_auth_doctrine_types.yaml`, `config/routes/kematjaya_auth.yaml`
- **User entity + UserRepository + UserManager** (generic, dari template
  bundle sendiri — bukan hasil copy dari boilerplate ini)
- Wire `UserManagerInterface` binding di `config/services.yaml`
- Generate JWT keypair
- Tambah `JWT_*` env var ke `.env`
- `doctrine:schema:update --force`

**Langkah yang bundle ini sendiri anggap manual** (merge
`config/packages/kematjaya_auth_security.yaml.dist` ke `security.yaml` app)
ternyata BISA diotomasi untuk kasus paling umum: `user-setup.sh` mencoba
merge otomatis (Python patch) kalau `security.yaml` masih persis bentuk
default recipe `symfony/security-bundle` — sudah diverifikasi jalan nyata
end-to-end (login/register berfungsi tanpa sentuh file itu manual sama
sekali). Kalau bentuknya sudah beda (di-custom), otomatis fallback nulis
[`backend/security-snippet.yaml`](./backend/security-snippet.yaml) buat
di-merge manual — lihat bagian "Status" di bawah untuk detail.

`kematjaya/access-control-bundle` **tidak** punya `setup.sh` sendiri (cuma
README + `.recipe/` yang Flex-shaped tapi tidak pernah auto-apply karena
`allow-contrib: false` di `composer.json` app). Jadi saya buat
[`backend/access-control-setup.sh`](./backend/access-control-setup.sh) di
sini, meniru persis pola `copy_if_missing` dari `auth-bundle/setup.sh`,
untuk: registrasi bundle, copy `config/routes/kematjaya_access_control.yaml`
+ `config/permissions/default.yaml` **langsung dari `.recipe/` bundle itu
sendiri** (bukan dari boilerplate — jadi selalu ikut versi yang ter-install),
tulis `kematjaya_access_control.yaml`, `doctrine:schema:update`, dan
`kematjaya:access-control:sync`.

## Isi folder ini

```
bff-next/
├── README.md                          # file ini
├── user-setup.sh                      # -> bin/user-setup.sh di project hasil generate (backend: API
│                                        # Platform, auth-bundle, access-control-bundle, fixture, auto-merge
│                                        # security.yaml). Diverifikasi jalan end-to-end, lihat "Status" di bawah.
├── frontend-setup.sh                  # -> bin/frontend-setup.sh (create-next-app fresh, npm install
│                                        # auth-ui/access-control-ui/bootstrap-ui-kit, copy template frontend/
│                                        # di bawah, compose.override.yaml, generate api.generated.ts)
├── backend/
│   ├── access-control-setup.sh        # -> bin/access-control-setup.sh (installer buatan sendiri, lihat atas)
│   ├── security-snippet.yaml          # ditulis ULANG saat runtime oleh user-setup.sh (fallback kalau
│   │                                   # auto-merge security.yaml gagal) — salinan ini cuma referensi baca
│   └── config/
│       ├── packages/{api_platform,nelmio_cors,kematjaya_access_control}.yaml
│       └── routes/api_platform.yaml
├── frontend/                          # SELURUH src/ frontend boilerplate, apa adanya (sudah 100% generic
│   │                                   # sejak Notes/News dihapus — tidak ada 1 pun file bisnis-spesifik)
│   ├── src/
│   │   ├── app/
│   │   │   ├── layout.tsx, page.tsx, globals.css       # root shell + landing generic
│   │   │   ├── login/page.tsx, register/page.tsx       # re-export dari @kematjaya/auth-ui/pages
│   │   │   ├── access-denied/page.tsx
│   │   │   ├── dashboard/
│   │   │   │   ├── layout.tsx          # auth gate + getMenu() -> Sidebar/Header
│   │   │   │   ├── page.tsx            # shell kosong, tinggal isi widget
│   │   │   │   ├── profile/page.tsx    # re-export dari @kematjaya/auth-ui/pages
│   │   │   │   ├── admin/page.tsx      # contoh guard ROLE_ADMIN
│   │   │   │   └── admin/access-control/page.tsx  # <PermissionMatrix />
│   │   │   └── api/                    # BFF routes: auth/* (6 file, re-export createXRoute()),
│   │   │                                # permissions/*, me/* (proxy ke access-control-bundle)
│   │   ├── components/dashboard/{Header,Sidebar}.tsx   # dashboard shell, sudah branding-netral
│   │   ├── config/{auth,access-control}.ts             # defineAuthConfig() + AccessRule[]
│   │   ├── lib/{http,bff,api-shapes,schemas,ids,permissions}.ts  # BFF generic, TIDAK ada logic bisnis
│   │   ├── proxy.ts                    # createAuthProxy() edge middleware
│   │   └── types/api.ts                # TokenPair, Problem (generic) — TANPA api.generated.ts,
│   │                                     # itu WAJIB di-generate ulang per-project, jangan pernah di-copy
│   ├── scripts/generate-api-types.mjs  # generator api.generated.ts — butuh `php`+`openapi-typescript`
│   │                                    # di HOST (execFile langsung); TIDAK dipakai frontend-setup.sh
│   ├── scripts/generate-api-types-docker.sh  # alternatif Docker-only (2x docker compose exec, tanpa
│   │                                    # butuh php/Node di host) — INI yang dipanggil frontend-setup.sh
│   ├── tests/unit/bff.test.ts, tests/e2e/{logout,navigation-role}.spec.ts  # generic, tanpa entity contoh
│   ├── package.json.reference          # daftar dependency (bukan untuk di-copy, cuma referensi versi)
│   ├── tsconfig.json, next.config.ts, vitest.config.ts, vitest.setup.ts, playwright.config.ts
│   └── Dockerfile, .dockerignore
└── compose/
    ├── compose.yaml.reference          # referensi struktur service (postgres/backend/frontend/migrate)
    ├── compose.override.yaml.reference # referensi dev override (bind mount, target: development)
    ├── .env.example                    # daftar env var lengkap (placeholder utk secret, jangan dipakai langsung)
    └── generate-env.sh                 # cp .env.example -> .env + isi APP_SECRET/POSTGRES_PASSWORD/
                                          # JWT_PASSPHRASE acak (openssl, fallback /dev/urandom — pola sama
                                          # persis dgn generate kredensial DB di symfony.bash). Idempotent
                                          # (skip kalau .env sudah ada, --force utk timpa). Diverifikasi
                                          # jalan nyata (generate, re-run skip, --force overwrite beda nilai).
```

## Yang SENGAJA tidak di-copy / perlu diperlakukan beda

- **`api.generated.ts`** — dibuang dari copy. File ini harus selalu digenerate
  ulang (`npm run api:types`) dari OpenAPI spec backend yang baru, bukan
  dicopy — kalau dicopy, tipe-nya akan menunjuk ke skema API Platform milik
  boilerplate lama, bukan project baru.
- **`package.json.reference`** — bukan untuk ditimpakan begitu saja ke
  `package.json` hasil `create-next-app` (itu akan menghapus struktur default
  Next.js/ESLint/dst yang baru). Yang perlu diambil cuma daftar dependency-nya:
  `@kematjaya/auth-ui`, `@kematjaya/access-control-ui`,
  `@kematjaya/bootstrap-ui-kit`, `bootstrap`, `bootstrap-icons`,
  `react-hook-form`, `@hookform/resolvers`, `zod`, `openapi-typescript` (dev).
- **`compose.yaml.reference`/`compose.override.yaml.reference`** — struktur
  service-nya (postgres/backend/frontend + healthcheck + `migrate` profile)
  layak dicontoh, tapi isinya masih pakai `name: boilerplate` dan asumsi
  `./backend`/`./frontend` sebagai context — perlu di-render lewat mekanisme
  `render_template`/heredoc yang sama seperti `symfony.bash` pakai untuk
  Dockerfile/compose.yaml-nya sendiri (jangan taruh password/`&`-bearing
  string pakai `sed`, lihat catatan panjang soal itu di `symfony.bash`).
- **`backend/security-snippet.yaml`** — sudah diotomasi (lihat bagian
  "Status" di bawah), file di folder ini cuma referensi baca; yang benar-benar
  dipakai runtime ditulis ulang oleh `user-setup.sh` HANYA kalau auto-merge
  gagal (fallback, bukan jalur utama).
- **`compose/.env.example`** — jangan pernah dipakai langsung sebagai `.env`
  (masih placeholder `replace-with-a-strong-password` dst). Pakai
  `compose/generate-env.sh` untuk generate `.env` dengan
  APP_SECRET/POSTGRES_PASSWORD/JWT_PASSPHRASE acak — diverifikasi jalan
  nyata (generate, re-run idempotent skip, `--force` overwrite beda nilai).

## Status: `user-setup.sh` + `frontend-setup.sh` sudah ditulis & diverifikasi nyata

`bff-next/user-setup.sh` dan `bff-next/frontend-setup.sh` (akan jadi
`bin/user-setup.sh`/`bin/frontend-setup.sh` di project hasil generate, sama
seperti `symfony/api/setup.sh` → `bin/user-setup.sh`) sudah ditulis dan
**dites end-to-end sungguhan** (2026-08-24): generate project fresh lewat
`symfony.bash` (REST API + Postgres) → jalankan kedua script → hasilnya
login/register/dashboard-redirect semua berfungsi lewat curl nyata (bukan
cuma syntax check). 4 bug nyata ditemukan & diperbaiki lewat testing ini
(lihat komentar di masing-masing script untuk detail):

1. `composer require kematjaya/auth-bundle` tanpa `--no-scripts` memicu
   `cache:clear` OTOMATIS (Flex post-update-cmd) sebelum `setup.sh` sempat
   wiring `UserManagerInterface` → container gagal compile.
2. `gesdinet/jwt-refresh-token-bundle` recipe-nya CONTRIB-tier — dengan
   `--no-interaction` (wajib untuk installer non-interaktif), Flex diam-diam
   SKIP recipe itu, bundle tidak pernah terdaftar di `bundles.php`. Ditambal
   manual (daftarkan bundle sebelum `vendor/kematjaya/auth-bundle/setup.sh`
   jalan).
3. `kematjaya_access_control.yaml`'s `manifest_profile: '%env(PERMISSIONS_PROFILE)%'`
   butuh env var yang tidak otomatis ada di project fresh — ditambahkan ke
   `.env` oleh `access-control-setup.sh`.
4. `npm install ... zod` tanpa pin versi kadang resolve ke `zod@3.x`
   (konflik dengan `@kematjaya/auth-ui`'s peer `zod@>=4`) — di-pin eksplisit
   `zod@^4`.

**Auto-merge `security.yaml`**: ternyata bentuk default yang ditulis recipe
resmi `symfony/security-bundle` untuk skeleton fresh itu predictable/stabil,
jadi `user-setup.sh` MENCOBA merge otomatis (teknik Python patch, sama
seperti yang sudah dipakai `symfony/fullstack/security-setup.sh`) — kalau
bentuknya tidak cocok (misal file sudah di-custom manual), otomatis fallback
ke instruksi manual + `security-snippet.yaml` (tidak pernah menimpa buta).

## Sudah di-wire ke `symfony.bash` sebagai opsi ke-3 (2026-08-24)

Folder ini dipindah dari top-level `bff-next/` ke `symfony/bff-next/` supaya
konsisten dengan `symfony/api/` dan `symfony/fullstack/` — `symfony.bash`
sekarang punya menu "3) Full-stack: Symfony API + Next.js" yang:
- generate skeleton dengan paket MINIMAL (`symfony/orm-pack`,
  `symfony/security-bundle`, `symfony/maker-bundle`, test-pack — SENGAJA
  tanpa `api-platform/*`/`nelmio/cors-bundle`, itu dipasang `user-setup.sh`
  supaya tidak dobel-install/konflik)
- copy `user-setup.sh` → `bin/user-setup.sh`, `frontend-setup.sh` →
  `bin/frontend-setup.sh`, `backend/access-control-setup.sh` →
  `bin/access-control-setup.sh`, `frontend/` → `bff-next-template/frontend/`
- README.md project hasil generate dapat section "Auth, RBAC, dan Frontend
  Next.js" otomatis

**Diverifikasi ULANG end-to-end lewat jalur nyata** (`printf 'nama\n3\n2\n' |
bash symfony.bash`, bukan copy manual lagi) — ketemu 1 bug baru dari wiring
ini sendiri (fix di `user-setup.sh`, fungsi `fix_ownership`): Flex recipe
`nelmio/cors-bundle` ikut menulis `config/packages/nelmio_cors.yaml` sendiri
(root-owned, karena `docker compose exec` jalan sebagai root) SETELAH chown
pertama di awal script — bikin `cat >` dari host kena `Permission denied`.
Sekarang `fix_ownership` dipanggil ulang setelah tiap `composer require` yang
diikuti host-side write, bukan cuma sekali di awal.

**Konsistensi nama** (poin yang diminta eksplisit): nama project, folder, dan
database sudah otomatis konsisten dari `$PROJECT_NAME` yang di-generate
`symfony.bash` (`DB_NAME_SCHEMA=$PROJECT_NAME` sudah ada sebelum wiring ini,
tidak disentuh). Yang ditambahkan sesi ini: `frontend-setup.sh` set
`package.json`'s `"name"` jadi `"${PROJECT_NAME}-frontend"` (sebelumnya selalu
generic `"frontend"` dari `create-next-app`), dan `user-setup.sh` set
`api_platform.yaml`'s `title` jadi `"$PROJECT_NAME API"` (sebelumnya generic
`"API"`). Diverifikasi nyata: generate dengan nama `my-cool-app` →
`package.json` name `my-cool-app-frontend`, `api_platform.yaml` title
`my-cool-app API`, container Docker `my-cool-app-php-1`/`my-cool-app-frontend-1`,
database `my-cool-app` — semua konsisten.

**Catatan soal `compose/`** (update 2026-08-26 — lihat entri restructure di
bawah): folder ini (`compose.yaml.reference`, `compose.override.yaml.reference`,
`.env.example`, `generate-env.sh`) MASIH dormant/tidak dipakai. Layout
`backend/`+`frontend/` dari boilerplate ini SUDAH diadopsi (lihat entri
"Restructure ke backend/+frontend/" di bawah), tapi lewat mekanisme yang
sudah teruji milik `symfony.bash` sendiri — nama service tetap `php` (bukan
`backend` seperti di `compose.yaml.reference`, biar konsisten dengan tipe
1/2), dan kredensial tetap `.env.local` acak per-project (bukan satu `.env`
root + `generate-env.sh`). `compose/` baru relevan kalau nanti arsitektur
kredensial/service-naming gabungan gaya `~/Projects/PHP/boilerplate` itu
sendiri mau diadopsi juga — itu keputusan terpisah, belum terjadi.

## Restructure ke backend/+frontend/ + package.json root (2026-08-26)

User generate project tipe 3 sungguhan, mengharapkan struktur
`backend/`+`frontend/` (persis boilerplate), bukan flat seperti sebelumnya.
Flat itu sengaja (lihat catatan lama di `frontend-setup.sh`), tapi user
eksplisit minta dikembalikan — alasan konkret: butuh `package.json` root
untuk custom script lintas folder (PHP & npm sekaligus).

Perubahan: `symfony.bash` generate skeleton Symfony ke `backend/` (variabel
`BACKEND_SUBDIR`/`BACKEND_FILE_PREFIX`, no-op untuk tipe 1/2), `compose.yaml`
tetap di root dengan `build.context: ./backend`. `user-setup.sh` di-prefix
`backend/` di semua path host-side (tetap `cd` ke root project, bukan ke
`backend/`, supaya `docker compose exec` tetap jalan tanpa perlu
`--project-directory`). `frontend-setup.sh` cuma 2 perubahan: precondition
check jadi `backend/bin/console`, dan patch `sed -i.bak` untuk
`generate-api-types.mjs` DIHAPUS — `resolve(root, '../backend')` bawaan
template sekarang sudah benar apa adanya, tidak perlu di-patch lagi.

**Gotcha yang ditemukan**: `access-control-setup.sh` dipanggil DARI DALAM
container php (`docker compose exec php bash bin/access-control-setup.sh`),
jadi harus di-copy ke `backend/bin/access-control-setup.sh` (path yang
ke-mount ke `/app`), BUKAN ke `bin/` root seperti `user-setup.sh`/
`frontend-setup.sh` (yang dipanggil dari HOST). Root `bin/` dan
`backend/bin/` sekarang dua direktori berbeda dengan arti berbeda.

`package.json` root ditulis SEKALI oleh `symfony.bash` (bukan ditambah
belakangan oleh `frontend-setup.sh`), port 1:1 dari target `Makefile` yang
sudah ada (`Makefile` TETAP dipertahankan berdampingan, bukan diganti —
lihat entri di bawah soal kenapa dulu `Makefile` dipilih di atas
`package.json`; sekarang keduanya ditawarkan, user pilih sendiri). Tanpa
`devDependencies` — tidak ada `node_modules`/lockfile baru di root.

## README project hasil generate + parity command `package.json` (2026-08-24)

User eksplisit menanyakan: (1) apakah project hasil generate punya README
yang jelas soal struktur/perintah/URL, dan (2) apakah script custom di
`~/Projects/PHP/boilerplate/package.json` (`schema:update`, `console`, `cc`,
`composer`, dst) sudah masuk ke project tipe 3. Jawabannya waktu itu: BELUM.
Sekarang sudah, lewat `Makefile` (bukan root `package.json`) — filosofi
Docker-only host generator ini artinya tidak boleh menambah dependensi Node
di host, jadi `make` dipakai (hampir selalu sudah ada di host mana pun, dan
bukan language runtime). Lihat `Makefile` di folder ini — di-copy ke project
hasil generate sebagai `Makefile` root, isinya cuma pembungkus tipis
`docker compose exec`, termasuk arg-passthrough (`make console <cmd>`,
`make composer <cmd>`) via idiom `$(filter-out $@,$(MAKECMDGOALS))` + catch-all
`%:`. Section README project hasil generate ("Auth, RBAC, dan Frontend
Next.js" di `symfony.bash`) diperluas jadi comprehensive: struktur folder,
tabel URL, tabel perintah `make`, kredensial fixture.

**3 bug nyata ketemu lewat testing ulang penuh (bukan cuma baca kode)**,
semuanya di `user-setup.sh`/`frontend-setup.sh`, BUKAN di `symfony.bash`:

1. **`ArgumentCountError` saat `doctrine:fixtures:load`** — recipe
   `doctrine/doctrine-fixtures-bundle` menjalankan `cache:clear`-nya sendiri
   TERHADAP stub `AppFixtures.php` kosong (constructor tanpa argumen) SEBELUM
   `user-setup.sh` menimpa file itu dengan constructor yang butuh
   `UserPasswordHasherInterface` — container cache jadi stale. Fix: tambah
   `bin/console cache:clear` eksplisit tepat sebelum `fixtures:load`.
2. **`tests/unit/bff.test.ts` ke-copy tapi tidak pernah bisa dijalankan** —
   vitest/testing-library tidak pernah ke-install sebagai npm dep, tidak ada
   script `"test"` di `package.json`. Fix: install `vitest`,
   `@vitejs/plugin-react`, `jsdom`, `@testing-library/*` sebagai dev dep +
   tambah `pkg.scripts.test = "vitest run"`.
3. **`tests/e2e/*.spec.ts` (Playwright) sama sekali tidak bisa jalan** — dua
   lapis masalah:
   - `@playwright/test` (di-pin ke versi tertentu, `PLAYWRIGHT_VERSION` di
     `frontend-setup.sh`) TIDAK bisa `playwright install --with-deps` di
     dalam service `frontend` (image `node:24-alpine`) karena browser
     Playwright tidak kompatibel dengan musl libc. Fix: service one-off
     BARU `playwright` di `compose.override.yaml`, pakai image resmi
     `mcr.microsoft.com/playwright:v$PLAYWRIGHT_VERSION-noble` (Debian),
     profile `e2e` (tidak ikut `docker compose up`), `network_mode:
     "service:frontend"` supaya Origin header browser (`http://localhost:3000`)
     persis cocok dengan `APP_ORIGIN` service `frontend` — kalau diakses
     lewat hostname Docker `http://frontend:3000` (network biasa), BFF route
     handler menolak semua POST (login/register) dengan 403 "Invalid origin".
   - Test `navigation-role.spec.ts` (di-copy apa adanya dari boilerplate
     asal) mengasumsikan ada menu "Admin" (ROLE_ADMIN-only, link ke
     `/dashboard/admin`) — halaman frontend-nya ADA di template
     (`frontend/src/app/dashboard/admin`), tapi manifest RBAC yang di-copy
     `access-control-setup.sh` cuma manifest GENERIK bawaan bundle (cuma
     item "Dashboard", tanpa "Admin" sama sekali) — link "Admin" tidak
     pernah muncul untuk siapa pun. Fix: `user-setup.sh` menambahkan section
     "Administration" (key `admin`, `roles: [ROLE_ADMIN]`,
     `defaultRoles: [ROLE_ADMIN]`, href `/dashboard/admin`) ke
     `config/permissions/default.yaml` setelah `access-control-setup.sh`
     jalan, lalu re-run `kematjaya:access-control:sync`.

Ketiganya HANYA ketahuan karena `make test-frontend`/`make test-e2e` benar-benar
dijalankan (bukan cuma dibaca) terhadap project hasil generate ulang penuh dari
nol — sebelumnya tidak ada satu pun jalur yang benar-benar mengeksekusi test
files yang ikut ter-copy. **Diverifikasi ULANG penuh setelah semua fix**:
generate bersih → `bin/user-setup.sh` → `bin/frontend-setup.sh` →
`make test-frontend` (4/4 pass) → `make test-e2e` (3/3 pass, termasuk skenario
admin-only menu) → `make lint`/`make console`/`make migrate` (semua jalan
sesuai ekspektasi) → register+login lewat curl (201/200) → cleanup penuh
(`docker compose down -v`, chown, `rm -rf`, `docker rmi`).
