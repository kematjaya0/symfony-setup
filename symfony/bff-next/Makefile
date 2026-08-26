# Shortcut perintah sehari-hari. Semua target ini cuma pembungkus tipis
# untuk `docker compose ...` — tidak butuh PHP/Node/Composer di host,
# cukup Docker + Docker Compose v2 (lihat README.md).
#
# Arg passthrough: `make console <apapun>` dan `make composer <apapun>`
# meneruskan sisa argumen apa adanya ke `bin/console`/`composer` di dalam
# container php, contoh:
#   make console doctrine:migrations:diff
#   make composer require symfony/mailer

.PHONY: dev down logs console composer cc migrate schema-update \
        test-backend test-frontend test-e2e lint

dev:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f

console:
	docker compose exec php bin/console $(filter-out $@,$(MAKECMDGOALS))

composer:
	docker compose exec php composer $(filter-out $@,$(MAKECMDGOALS))

cc:
	docker compose exec php bin/console cache:clear

migrate:
	docker compose exec php bin/console doctrine:migrations:migrate --no-interaction

schema-update:
	docker compose exec php bin/console doctrine:schema:update --force

test-backend:
	docker compose exec php bin/phpunit

test-frontend:
	docker compose exec frontend npm test

test-e2e:
	docker compose --profile e2e run --rm playwright

lint:
	docker compose exec frontend npm run lint

# Catatan: tidak ada target `lint` untuk backend (php-cs-fixer/phpstan)
# karena keduanya BUKAN bagian dari paket minimal yang di-install
# symfony.bash untuk tipe project ini — menambahkannya di sini akan
# jadi perintah yang gagal begitu dijalankan. Tambahkan manual lewat
# `make composer require --dev friendsofphp/php-cs-fixer` dulu kalau perlu.

# Tangkap argumen tambahan (mis. "doctrine:migrations:diff" di
# `make console doctrine:migrations:diff`) supaya Make tidak
# menganggapnya sebagai target terpisah yang tidak dikenal.
%:
	@:
