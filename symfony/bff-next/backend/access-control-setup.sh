#!/usr/bin/env bash
#
# Post-install setup for kematjaya/access-control-bundle.
#
# Unlike kematjaya/auth-bundle, this package ships NO setup.sh of its own —
# it only has a Flex-shaped .recipe/ that never auto-applies in practice
# (Composer's "allow-contrib": false blocks Flex from fetching non-official
# recipes, and this bundle isn't in the public contrib index). This script
# mirrors auth-bundle/setup.sh's copy_if_missing pattern for the two files
# that recipe would have copied.
#
# Run from your Symfony project root, after:
#   composer require kematjaya/access-control-bundle
#
# Usage:
#   bff-next/backend/access-control-setup.sh [--force]

set -euo pipefail

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
    FORCE=1
fi

PROJECT_ROOT="$(pwd)"
RECIPE_DIR="vendor/kematjaya/access-control-bundle/.recipe"

blue() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
yellow() { printf '\033[1;33m--\033[0m %s\n' "$1"; }
red() { printf '\033[1;31m!!\033[0m %s\n' "$1" >&2; }

if [[ ! -f "$PROJECT_ROOT/bin/console" ]]; then
    red "bin/console not found. Run this script from your Symfony project root."
    exit 1
fi

if [[ ! -d "$RECIPE_DIR" ]]; then
    red "$RECIPE_DIR not found — is kematjaya/access-control-bundle installed?"
    exit 1
fi

copy_if_missing() {
    local src="$1" dest="$2"
    if [[ -f "$dest" && "$FORCE" -eq 0 ]]; then
        yellow "skipped $dest (already exists, use --force to overwrite)"
        return
    fi
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    blue "wrote $dest"
}

# 1. Register the bundle in config/bundles.php
blue "Registering the bundle"
if [[ -f config/bundles.php ]] && grep -q 'KematjayaAccessControlBundle::class' config/bundles.php; then
    yellow "skipped config/bundles.php (entry already present)"
else
    php -r '
        $file = "config/bundles.php";
        $contents = file_get_contents($file);
        $entry = "    Kematjaya\\AccessControlBundle\\KematjayaAccessControlBundle::class => [\x27all\x27 => true],\n";
        $updated = preg_replace("/return \[\n/", "return [\n" . $entry, $contents, 1, $count);
        if ($count !== 1) {
            fwrite(STDERR, "Could not automatically edit config/bundles.php - add this line yourself:\n" . $entry);
            exit(1);
        }
        file_put_contents($file, $updated);
    ' || red "Add manually: Kematjaya\\AccessControlBundle\\KematjayaAccessControlBundle::class => ['all' => true],"
fi

# 2. Config: superuser_role/manifest_profile (safe to auto-load, own namespace)
blue "Writing config/packages/kematjaya_access_control.yaml"
if [[ -f config/packages/kematjaya_access_control.yaml && "$FORCE" -eq 0 ]]; then
    yellow "skipped config/packages/kematjaya_access_control.yaml (already exists, use --force to overwrite)"
else
    cat > config/packages/kematjaya_access_control.yaml <<'YAML'
kematjaya_access_control:
    superuser_role: ROLE_ADMIN
    manifest_profile: '%env(PERMISSIONS_PROFILE)%'
YAML
    blue "wrote config/packages/kematjaya_access_control.yaml"
fi

# 3. Route import + starter permission manifest — straight from the bundle's
# own recipe dir, so this always tracks whatever version is installed.
blue "Copying config fragments from the bundle's own recipe"
copy_if_missing "$RECIPE_DIR/config/routes/kematjaya_access_control.yaml" "config/routes/kematjaya_access_control.yaml"
copy_if_missing "$RECIPE_DIR/config/permissions/default.yaml" "config/permissions/default.yaml"

# 4. .env var the manifest_profile above reads
blue ".env variables"
if [[ -f .env ]] && grep -q '^PERMISSIONS_PROFILE=' .env; then
    yellow "skipped .env (PERMISSIONS_PROFILE already present)"
else
    {
        echo ''
        echo '###> kematjaya/access-control-bundle ###'
        echo 'PERMISSIONS_PROFILE=default'
        echo '###< kematjaya/access-control-bundle ###'
    } >> .env
    blue "added PERMISSIONS_PROFILE to .env"
fi

# 5. Schema + sync
blue "Updating the database schema"
php bin/console doctrine:schema:update --force

blue "Syncing the manifest into the database"
php bin/console kematjaya:access-control:sync

cat <<'EOF'

Done. Two things are NOT automated - do them yourself:

  1. If you use Symfony's role_hierarchy, configure it in your own
     config/packages/security.yaml (superuser_role above must match its
     top role, e.g. ROLE_ADMIN: ROLE_USER).
  2. Protect specific controller/API Platform actions with
     is_granted('<permission key>') as you add real menu items to
     config/permissions/default.yaml.
EOF
