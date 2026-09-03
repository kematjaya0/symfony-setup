{
  "name": "@@PROJECT_NAME@@",
  "private": true,
  "scripts": {
    "dev": "docker compose up -d --build",
    "down": "docker compose down",
    "logs": "docker compose logs -f",
    "console": "docker compose exec php bin/console",
    "composer": "docker compose exec php composer",
    "cc": "docker compose exec php bin/console cache:clear",
    "migrate": "docker compose exec php bin/console doctrine:migrations:migrate --no-interaction",
    "schema:update": "docker compose exec php bin/console doctrine:schema:update --force",
    "test:backend": "docker compose exec php bin/phpunit",
    "test:frontend": "docker compose exec frontend npm test",
    "test:e2e": "docker compose --profile e2e run --rm playwright",
    "lint": "docker compose exec frontend npm run lint",
    "generate": "bash bin/generate-crud.sh"
  }
}
