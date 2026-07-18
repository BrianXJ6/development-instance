# Docker Development Environment

Production-grade local Docker environment: **PHP 8.5 FPM on Alpine**, **Nginx**, and **Supervisor** running **Horizon** and the **scheduler** in a single container — with Xdebug, PCOV, Node.js, and an auto-provisioned MySQL testing database. A drop-in replacement for the default Laravel Sail image.

## What's inside

| Component | Details |
| --- | --- |
| Base image | `php:8.5-fpm-alpine` |
| Web server | Nginx (gzip, FastCGI buffering, 100M uploads) |
| Process manager | Supervisor — `nginx`, `php-fpm`, `queue`, `scheduler` |
| Node.js | v24 + npm (Vite dev server / builds inside the container) |
| PHP extensions | `redis`, `pcov`, `xdebug`, `imagick`, `gd` (jpeg/webp/xpm), `zip`, `pdo_mysql`, `pcntl` |
| Tooling | Composer, git, vim/nano, mysql & mariadb clients, ImageMagick, ffmpeg, sqlite |
| Container user | `sail` (uid/gid 1000, member of `www-data`) |
| Timezone | `America/Recife` by default (override via `TZ`) |

## Repository layout

```text
.
├── Dockerfile             # Image definition (single stage, dev-oriented)
├── start-container        # Entrypoint: first-run bootstrap + supervisord
├── supervisord.conf       # nginx + php-fpm + queue + scheduler
├── nginx.conf             # Dev-tuned Nginx (gzip, buffering, 100M uploads)
├── php.ini                # Dev php.ini overrides (errors on, PCOV, timezone)
├── xdebug.ini             # Xdebug: develop,debug,coverage via host.docker.internal
└── mysql/
    └── create-testing-db.sh   # Auto-creates the `testing` DB (docker-entrypoint-initdb.d)
```

## Assumptions

Built for a standard Laravel application mounted at `/var/www`, expecting:

- `artisan`, `composer.json`, `package.json`, and a `.env.example` at the project root
- **Laravel Horizon** installed (`pcntl` is compiled in — Horizon requires it). If your project uses Horizon, replace the `[program:queue]` configuration with the `[program:horizon]` block already present in `supervisord.conf`.
- The scheduler runs via `schedule:work` (long-lived process — no OS cron needed)

## Quick start (Docker Compose)

Add this repository to your project (e.g. as `docker/development-instance`, a git submodule, or a subtree) and point a service at it:

```yaml
services:
    app:
        build:
            context: ./docker/development-instance
            dockerfile: Dockerfile
        image: my-app
        ports:
            - ${APP_PORT:-80}:80
        environment:
            DB_HOST: ${DB_HOST:-mysql} # used by the entrypoint DB wait-loop
            DB_USER: ${DB_USERNAME:-admin}
            DB_PASSWORD: ${DB_PASSWORD:-secret}
        volumes:
            - .:/var/www
        depends_on:
            - mysql

    mysql:
        image: "mysql:8.4"
        environment:
            MYSQL_ROOT_PASSWORD: root
            MYSQL_DATABASE: ${DB_DATABASE:-admin}
            MYSQL_USER: ${DB_USERNAME:-admin}
            MYSQL_PASSWORD: ${DB_PASSWORD:-secret}
        volumes:
            - mysql-data:/var/lib/mysql
            # Auto-creates the `testing` database on first boot:
            - ./docker/development-instance/mysql:/docker-entrypoint-initdb.d
```

Then: `docker compose up -d` — the first boot bootstraps everything (see below).

## First-run bootstrap

The `start-container` entrypoint prepares a fresh clone automatically before handing off to Supervisor:

1. **Composer packages** — installed if `vendor/` is missing (runs `composer update` deliberately: on a fresh project without a `composer.lock`, it resolves the latest versions — dev-environment behavior by design)
2. **`.env`** — copied from `.env.example` + `artisan key:generate` if missing
3. **npm packages** — installed if `node_modules/` is missing
4. **Initial Vite build** — if `public/build/` is missing
5. **Database wait-loop** — pings MySQL (up to 30s) before continuing
6. **Migrations + seed** — only when the migration table isn't initialized yet
7. Fixes ownership (`sail:sail`) and `storage/` permissions, then starts Supervisor

Subsequent boots skip everything that already exists — startup is fast.

## Supervised processes

| Program | Command | Notes |
| --- | --- | --- |
| `nginx` | `nginx -g 'daemon off;'` | Port 80 |
| `php-fpm` | `php-fpm --nodaemonize` | FastCGI on 127.0.0.1:9000 |
| `queue` | `artisan queue:work` | `stopwaitsecs=300` for graceful queue shutdown |
| `scheduler` | `artisan schedule:work` | Replaces OS cron |

All logs land in `/var/log/supervisor/*.log`.

## PHP configuration highlights

- `display_errors=On`, `error_reporting=E_ALL` — dev-appropriate visibility
- `memory_limit=256M`, uploads up to 100M
- **PCOV** enabled for fast test coverage (`pcov.directory=.`)
- **Xdebug** in `develop,debug,coverage` mode, connecting back through `host.docker.internal` (works on Docker Desktop and WSL2; the compose example maps the host gateway)

## Testing database

`mysql/create-testing-db.sh` runs on the MySQL container's first boot (via `docker-entrypoint-initdb.d`) and creates a `testing` database, granting access to the app user **dynamically** — it reads `MYSQL_USER` and `MYSQL_ROOT_PASSWORD` from the same env vars the official MySQL image already receives, so nothing is hardcoded. Point your `phpunit.xml` at it (`DB_DATABASE=testing`) so tests never touch dev data.

## Optional: Inertia SSR

For Inertia server-side rendering, add this block to `supervisord.conf`:

```ini
[program:ssr]
autostart=false
autorestart=false
command=/usr/local/bin/php /var/www/artisan inertia:start-ssr
stderr_logfile=/var/log/supervisor/ssr.err.log
stdout_logfile=/var/log/supervisor/ssr.out.log
```

## Tips & known quirks

- **Always isolate `node_modules` in a named volume** (see compose example). Alpine's musl libc requires different native bindings than the glibc host — a shared `node_modules` makes tools with native binaries (esbuild, rolldown…) fail intermittently on one side or the other. Run `npm` through the container.
- **`bootstrap/cache` permissions** — if a web request hits "must be present and writable" after a `composer.json` change, run `chmod -R 775 bootstrap/cache` inside the container (php-fpm runs as `www-data`, which needs group write there).
- **`pcntl` is required by Horizon** — already compiled in; keep it if you keep Horizon.
- **FastCGI buffering is on** in `nginx.conf` — required for the Horizon dashboard to render correctly behind Nginx.
- **After changing `.env` or queued job/notification classes**, restart Horizon (`artisan horizon:terminate`) — it's a long-lived process and keeps old code/env in memory.

## Candidate extensions (not installed)

Evaluated but intentionally left out to keep the image lean — add per project if needed:

- `pecl`: `msgpack`, `igbinary` (high-efficiency serialization), `swoole`, `imap`
- `docker-php-ext-install`: `bcmath`, `soap`, `intl`, `ldap`
