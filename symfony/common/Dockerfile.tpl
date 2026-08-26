# syntax=docker/dockerfile:1

# --- STAGE 1: Base image (dipakai dev & prod) ---
FROM dunglas/frankenphp:1-php8.4-bookworm AS frankenphp_base

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        unzip \
        libicu-dev \
        libzip-dev \
        libpq-dev \
        default-libmysqlclient-dev \
    && docker-php-ext-configure intl \
    && docker-php-ext-install -j"$(nproc)" \
        intl \
        zip \
        opcache \
        @@PHP_DB_EXTS@@ \
    && pecl install apcu \
    && docker-php-ext-enable apcu \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY .docker/frankenphp/conf.d/app.ini $PHP_INI_DIR/conf.d/zz-app.ini
COPY .docker/frankenphp/Caddyfile /etc/frankenphp/Caddyfile

WORKDIR /app

# --- STAGE 2: Development ---
FROM frankenphp_base AS frankenphp_dev

ENV APP_ENV=dev
# CATATAN: worker mode SENGAJA TIDAK diaktifkan di dev. Worker mode
# menyimpan aplikasi di memory antar-request; kalau diaktifkan tanpa
# --watch, perubahan kode PHP Anda tidak akan muncul sampai container
# di-restart manual. Mode klasik (request per boot) jauh lebih predictable
# untuk development sehari-hari.
# Source code di-mount lewat compose.yaml agar hot-reload berjalan.

# --- STAGE 3: Production ---
FROM frankenphp_base AS frankenphp_prod

ENV APP_ENV=prod
ENV APP_DEBUG=0
ENV FRANKENPHP_CONFIG="worker ./public/index.php"

COPY .docker/frankenphp/conf.d/zzz-opcache-prod.ini $PHP_INI_DIR/conf.d/zzz-opcache-prod.ini
COPY . /app/

RUN composer install --no-dev --optimize-autoloader --classmap-authoritative --no-interaction \
    && composer dump-env prod \
    && php bin/console cache:clear --env=prod --no-debug

@@PROD_EXTRA_STEP@@

RUN chown -R www-data:www-data /app/var
USER www-data
