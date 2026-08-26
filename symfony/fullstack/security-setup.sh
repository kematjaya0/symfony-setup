#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "🔧 ${GREEN}Memastikan file project bisa ditulis dari host...${NC}"
docker compose exec -T php sh -c "chown -R $(id -u):$(id -g) /app/src /app/config" 2>/dev/null || true
chmod -R u+rwX src config

echo -e "📝 ${GREEN}Membuat Homepage controller dan redirect ke /login...${NC}"
cat > src/Controller/HomepageController.php <<'PHP'
<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

class HomepageController extends AbstractController
{
    #[Route('/', name: 'homepage')]
    public function index(): Response
    {
        return $this->redirectToRoute("app_login");
    }
}
PHP

echo -e "📝 ${GREEN}Membuat backend dashboard controller...${NC}"
mkdir -p src/Controller/Backend
cat > src/Controller/Backend/DashboardController.php <<'PHP'
<?php

namespace App\Controller\Backend;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

class DashboardController extends AbstractController
{
    #[Route('/', name: 'dashboard_index')]
    public function index(): Response
    {
        return new Response('OK');
    }
}
PHP

echo -e "📝 ${GREEN}Mendaftarkan backend routes...${NC}"
if ! grep -q '^backend:' config/routes.yaml; then
    cat >> config/routes.yaml <<'YAML'

backend:
    resource: '../src/Controller/Backend/'
    type: attribute
    prefix: /backend
YAML
fi

echo -e "🔐 ${GREEN}Mengatur backend security...${NC}"
python3 - <<'PY'
from pathlib import Path

path = Path('config/packages/security.yaml')
lines = path.read_text().splitlines(keepends=True)

provider_index = next((i for i, line in enumerate(lines) if line == '    providers:\n'), None)
if provider_index is None:
    raise SystemExit('Provider "providers" tidak ditemukan di config/packages/security.yaml')

provider_end = next(
    (
        i for i in range(provider_index + 1, len(lines))
        if lines[i].strip() and len(lines[i]) - len(lines[i].lstrip(' ')) <= 4
    ),
    len(lines),
)
lines[provider_index:provider_end] = [
    '    providers:\n',
    '        app_user_provider:\n',
    '            entity:\n',
    '                class: App\\Entity\\User\n',
    '                property: email\n',
]

form_login_index = next((i for i, line in enumerate(lines) if line.strip() == 'form_login:'), None)
if form_login_index is None:
    main_index = next((i for i, line in enumerate(lines) if line == '        main:\n'), None)
    if main_index is None:
        raise SystemExit('Firewall "main" tidak ditemukan di config/packages/security.yaml')

    lines[main_index + 1:main_index + 1] = [
        '            form_login:\n',
        '                default_target_path: dashboard_index\n',
        '                always_use_default_target_path: true\n',
    ]
else:
    block_end = next(
        (
            i for i in range(form_login_index + 1, len(lines))
            if lines[i].strip() and len(lines[i]) - len(lines[i].lstrip(' ')) <= 12
        ),
        len(lines),
    )
    block = ''.join(lines[form_login_index:block_end])
    additions = []
    if 'default_target_path:' not in block:
        additions.append('                default_target_path: dashboard_index\n')
    if 'always_use_default_target_path:' not in block:
        additions.append('                always_use_default_target_path: true\n')
    lines[block_end:block_end] = additions

text = ''.join(lines)
text = text.replace('            provider: users_in_memory\n', '            provider: app_user_provider\n')

backend_rule = '        - { path: ^/backend, roles: ROLE_ADMIN }'
if backend_rule not in text:
    marker = '    access_control:\n'
    if marker in text:
        text = text.replace(marker, marker + backend_rule + '\n', 1)
    else:
        text = text.replace('\nwhen@test:\n', '\n    access_control:\n' + backend_rule + '\n\nwhen@test:\n', 1)

path.write_text(text)
PY

echo -e "🎨 ${GREEN}Menyiapkan Bootstrap untuk custom UI login...${NC}"
docker compose exec php php bin/console importmap:require bootstrap bootstrap/dist/css/bootstrap.min.css

echo ""
echo -e "${YELLOW}============================================================${NC}"
echo -e "${YELLOW}⚠️  LANGKAH MANUAL: Custom UI Login via AI Agent${NC}"
echo -e "${YELLOW}============================================================${NC}"
echo -e "${BLUE}Buka OpenCode atau AI Agent CLI kamu, lalu jalankan prompt ini:${NC}"
echo ""
cat <<'PROMPT'
Update templates/security/login.html.twig based on DESIGN.md.

Context:
- Symfony form_login page.
- Bootstrap 5 based UI.
- Preserve Symfony login contract:
  - form method="post"
  - email input name="_username"
  - password input name="_password"
  - hidden csrf input name="_csrf_token" with value "{{ csrf_token('authenticate') }}"
  - use last_username
  - show error.messageKey|trans(error.messageData, 'security')
- Keep class "alert-danger" on login error so existing functional tests keep passing.
- Use DESIGN.md visual direction:
  - dark midnight canvas #05060f
  - frosted glass auth card
  - luminous blue-white text
  - only violet #663af3 for submit CTA
  - inset frosted borders, no hard solid borders
  - generous spacing, Bootstrap 5 layout utilities
- If CSS needed, put it in assets/styles/app.css.
- If Bootstrap 5 is missing, add it with:
  docker compose exec php php bin/console importmap:require bootstrap
  then import bootstrap JS/CSS from assets/app.js.
- Do not change login route names or security config unless required.
- After change, run:
  docker compose exec php bin/phpunit tests/LoginControllerTest.php
PROMPT
echo ""
echo -e "${YELLOW}============================================================${NC}"
