#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage: bash bin/user-setup.sh

Dev-only bootstrap from host (tipe project: REST API):
- starts Docker Compose
- installs doctrine fixtures bundle
- writes User entity, UserFixtures, UserFixturesTest
- writes contoh endpoint publik GET /api/ping
- loads fixtures with --no-interaction (purges dev DB)
- prints manual command untuk lanjut setup JWT auth (bin/jwt-setup.sh)
HELP
    exit 0
fi

echo "== Dev setup from host =="
docker compose up -d

echo -e "📝 ${GREEN}Menginstal doctrine fixtures bundle...${NC}"
docker compose exec php composer require doctrine/doctrine-fixtures-bundle --dev

echo "== Ensure project files are writable from host =="
docker compose exec -T php sh -c "chown -R $(id -u):$(id -g) /app/src /app/tests /app/config" 2>/dev/null || true
mkdir -p src/Entity src/DataFixtures tests src/Controller/Api src/Repository
chmod -R u+rwX src tests config

echo -e "📝 ${GREEN}Membuat User entity...${NC}"
cat > src/Entity/User.php <<'PHP'
<?php

namespace App\Entity;

use App\Repository\UserRepository;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Security\Core\User\PasswordAuthenticatedUserInterface;
use Symfony\Component\Security\Core\User\UserInterface;

#[ORM\Entity(repositoryClass: UserRepository::class)]
#[ORM\Table(name: '`user`')]
#[ORM\UniqueConstraint(name: 'UNIQ_IDENTIFIER_EMAIL', fields: ['email'])]
class User implements UserInterface, PasswordAuthenticatedUserInterface
{
    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\Column(length: 180)]
    private ?string $email = null;

    /**
     * @var list<string> The user roles
     */
    #[ORM\Column]
    private array $roles = [];

    /**
     * @var string The hashed password
     */
    #[ORM\Column]
    private ?string $password = null;

    public function getId(): ?int
    {
        return $this->id;
    }

    public function getEmail(): ?string
    {
        return $this->email;
    }

    public function setEmail(string $email): static
    {
        $this->email = $email;

        return $this;
    }

    public function getUserIdentifier(): string
    {
        return (string) $this->email;
    }

    /**
     * @return list<string>
     */
    public function getRoles(): array
    {
        $roles = $this->roles;
        $roles[] = 'ROLE_USER';

        return array_values(array_unique($roles));
    }

    /**
     * @param list<string> $roles
     */
    public function setRoles(array $roles): static
    {
        $this->roles = $roles;

        return $this;
    }

    public function getPassword(): ?string
    {
        return $this->password;
    }

    public function setPassword(string $password): static
    {
        $this->password = $password;

        return $this;
    }

    public function __serialize(): array
    {
        $data = (array) $this;
        $data["\0".self::class."\0password"] = hash('crc32c', $this->password);

        return $data;
    }
}
PHP

cat > src/Repository/UserRepository.php <<'PHP'
<?php

namespace App\Repository;

use App\Entity\User;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/**
 * @extends ServiceEntityRepository<User>
 */
class UserRepository extends ServiceEntityRepository
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, User::class);
    }
}
PHP

echo "== update schema =="
docker compose exec php php bin/console doctrine:schema:update --force

echo -e "📝 ${GREEN}Membuat UserFixtures...${NC}"
if [ ! -d src/DataFixtures ]; then
    mkdir -p src/DataFixtures
fi
cat > src/DataFixtures/UserFixtures.php <<'PHP'
<?php

namespace App\DataFixtures;

use App\Entity\User;
use Doctrine\Bundle\FixturesBundle\Fixture;
use Doctrine\Persistence\ObjectManager;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;

class UserFixtures extends Fixture
{
    public function __construct(private readonly UserPasswordHasherInterface $passwordHasher)
    {
    }

    public function load(ObjectManager $manager): void
    {
        $user = (new User())
            ->setEmail('admin@example.com')
            ->setRoles(['ROLE_ADMIN']);

        $user->setPassword($this->passwordHasher->hashPassword($user, 'admin123'));

        $manager->persist($user);
        $manager->flush();
    }
}
PHP

echo -e "📝 ${GREEN}Membuat UserFixturesTest...${NC}"
mkdir -p tests
cat > tests/UserFixturesTest.php <<'PHP'
<?php

namespace App\Tests;

use App\DataFixtures\UserFixtures;
use App\Entity\User;
use Doctrine\Persistence\ObjectManager;
use PHPUnit\Framework\TestCase;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;

class UserFixturesTest extends TestCase
{
    public function testLoadPersistsAdminWithHashedPassword(): void
    {
        $persistedUser = null;
        $passwordHasher = $this->createMock(UserPasswordHasherInterface::class);
        $manager = $this->createMock(ObjectManager::class);

        $passwordHasher->expects($this->once())
            ->method('hashPassword')
            ->with($this->isInstanceOf(User::class), 'admin123')
            ->willReturn('hashed-admin-password');

        $manager->expects($this->once())
            ->method('persist')
            ->with($this->callback(function (User $user) use (&$persistedUser): bool {
                $persistedUser = $user;

                return true;
            }));

        $manager->expects($this->once())->method('flush');

        (new UserFixtures($passwordHasher))->load($manager);

        self::assertInstanceOf(User::class, $persistedUser);
        self::assertSame('admin@example.com', $persistedUser->getEmail());
        self::assertSame('hashed-admin-password', $persistedUser->getPassword());
        self::assertContains('ROLE_ADMIN', $persistedUser->getRoles());
        self::assertContains('ROLE_USER', $persistedUser->getRoles());
    }
}
PHP

echo -e "📝 ${GREEN}Membuat contoh endpoint publik GET /api/ping...${NC}"
cat > src/Controller/Api/PingController.php <<'PHP'
<?php

namespace App\Controller\Api;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

class PingController extends AbstractController
{
    #[Route('/api/ping', name: 'api_ping', methods: ['GET'])]
    public function __invoke(): JsonResponse
    {
        return $this->json(['status' => 'ok']);
    }
}
PHP

echo -e "🔧 ${GREEN}menjalankan fixture load...${NC}"
docker compose exec php php bin/console doctrine:fixtures:load --no-interaction

echo "== Verify fixture unit test =="
docker compose exec php php bin/phpunit tests/UserFixturesTest.php
echo ""
echo -e "${YELLOW}============================================================${NC}"
echo -e "${YELLOW}⚠️  LANGKAH SELANJUTNYA: Setup autentikasi JWT untuk /api${NC}"
echo -e "${YELLOW}============================================================${NC}"
echo -e "${BLUE}Jalankan dari host Docker:${NC}"
echo ""
echo -e "${GREEN}bash bin/jwt-setup.sh${NC}"
echo ""
echo -e "${YELLOW}============================================================${NC}"
