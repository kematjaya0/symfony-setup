# Project: setup-script

> Bash generator for Docker-first Symfony projects. Creates Symfony 8.1 apps with FrankenPHP, Doctrine, MySQL/PostgreSQL, Adminer, PHPUnit, optional Symfony UX, optional Playwright e2e.

## Tech Stack
- **Language**: Bash; generated projects use PHP 8.4 + TypeScript for Playwright config.
- **Framework**: Symfony skeleton/webapp, FrankenPHP/Caddy.
- **Database**: Generated choice: MySQL 8.0 or PostgreSQL 16-alpine.
- **Build Tool**: Docker Compose v2 + Composer container.
- **Testing**: Generated PHPUnit; generated web apps also include Playwright via Docker profile.

## Folder Structure
```text
setup-script/
├── symfony.bash              # Main interactive Symfony project generator
├── symfony/
│   └── setup.sh              # Helper copied into generated projects as bin/setup.sh
├── .omo/                     # Existing execution plans/evidence from prior agent work
├── .opencode/
│   ├── plans/                # Task plans: YYYY-MM-DD-nama-plan.md
│   ├── skills/               # Project-specific AI skills, only if real convention emerges
│   └── knowledge/            # Decisions/learnings notes
└── .gitignore                # Ignores IDE files
```

## Quick Commands
| Task | Command |
|------|---------|
| Run generator | `bash symfony.bash` |
| Syntax check | `bash -n symfony.bash && bash -n symfony/setup.sh` |
| Generate web + MySQL smoke | `printf 'tmp-mysql-web\n2\n1\n' | bash symfony.bash` |
| Generate API + PostgreSQL smoke | `printf 'tmp-pg-api\n1\n2\n' | bash symfony.bash` |
| Generated app up | `(cd <project> && docker compose up -d)` |
| Generated app tests | `(cd <project> && docker compose exec php bin/phpunit)` |
| Generated web e2e | `(cd <project> && docker compose --profile e2e run --rm playwright)` |
| Cleanup smoke project | `(cd <project> && docker compose down -v --remove-orphans)` |

## Development Workflow

### 1. Sebelum Mulai Task
- Baca file plan di `.opencode/plans/` jika ada.
- Review requirements; **WAJIB tanya balik** untuk point ambigu.
- Pastikan acceptance criteria jelas sebelum edit.
- Untuk bug generator, reproduksi pakai input non-interaktif (`printf 'name\n2\n1\n' | bash symfony.bash`).

### 2. Implementasi
- Prefer edit minimal di `symfony.bash`; helper generated-project only di `symfony/setup.sh`.
- Jaga host prerequisite: hanya Docker + Docker Compose v2 wajib.
- Jangan tambah dependency host (PHP/Composer/Node) untuk generator.
- Commit message jelas; jangan commit generated temp projects.

### 3. Testing
- Minimal: `bash -n symfony.bash && bash -n symfony/setup.sh`.
- Untuk behavior generator: generate fresh temp project, run relevant Docker command, cleanup stack + volumes.
- Test scenarios sebanyak mungkin: happy path, DB readiness, bad input, retry/failure ceiling, idempotency.
- Semua command harus PASS sebelum task selesai.

### 4. Selesai
- Update file plan: tandai task dengan status `[x] OK`.
- Tulis catatan/learning di `.opencode/knowledge/` jika ada keputusan reusable.
- Simpan evidence di `.omo/evidence/` hanya jika task memang butuh audit trail.

## Plan File Format

File: `.opencode/plans/YYYY-MM-DD-nama-plan.md`

```markdown
# Plan: {Nama Task}

Date: YYYY-MM-DD
Status: [ ] In Progress | [x] OK

## Objective
{Apa yang ingin dicapai}

## Tasks
- [ ] Task 1
- [ ] Task 2

## Acceptance Criteria
- [ ] Criteria 1
- [ ] Criteria 2

## Notes
{Catatan tambahan, keputusan, blockers}
```

## Conventions
- Bash strict mode: `set -euo pipefail`.
- User-facing messages mostly Indonesian; keep style consistent.
- Generated credentials are random per project; never hardcode reusable secrets.
- Docker-first rule: use `composer:2` and app containers; no local PHP/Composer/Node assumption.
- Generated `DATABASE_URL` is expanded directly in heredoc; avoid placeholder replacement with `sed` because `&` in query string corrupts replacements.
- MySQL readiness must use TCP (`--protocol=TCP`, `127.0.0.1`), not socket-prone localhost.
- Retry loops must be bounded and print final captured output on failure.
- Generated web app Playwright lives under `e2e/`; PHPUnit stays under `tests/`.

## Environment Variables
- No `.env.example` in this repo.
- Generated `compose.yaml` supports: `APP_ENV`, `APP_DEBUG`, `HTTP_PORT`, `HTTPS_PORT`, `ADMINER_PORT`.
- Generated Playwright profile uses `BASE_URL` internally.

## Recommended Agents
- **Shell/Bash agent**: edits to `symfony.bash` or `symfony/setup.sh`.
- **Docker agent**: generated Compose/Dockerfile behavior, readiness, cleanup.
- **Symfony agent**: generated Symfony package/config behavior.
- **Test/QA agent**: fresh project generation smoke tests + evidence logs.
