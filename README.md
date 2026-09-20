# jbsnewmedia/vibe4dock-arcvd

**A**pplication · **R**oot · **C**hat · **V**eronica · **D**iff - all-in-one Docker image: **one** container instance, **one** HTTP(S) port, all services behind path routing.

| Route | Content |
|---|---|
| `/` | Vibe4Dock start page (PHP) |
| `/{VIBE_PREFIX}-chat/` | Chat UI + opencode API |
| `/{VIBE_PREFIX}-veronica/` | Veronica UI + opencode API + server-side user JSON DB |
| `/{VIBE_PREFIX}-diff/` | Vibe-Diff: git working tree UI (branches, commits, diffs, line/block revert) |
| `/{VIBE_PREFIX}-shell-root/` | Root shell (ttyd + tmux) |
| `/{VIBE_PREFIX}-shell-app/` | Application shell (ttyd + tmux) |

Base image: `webdevops/php-apache:8.5` (Apache + php-fpm); the opencode backends and ttyd shells run as background processes (supervisord).

## Quick start

```bash
cp .env.example .env
# fill in .env (at least OPENCODE_API_KEY)
docker compose up -d
xdg-open http://localhost/
```

Routes (with `VIBE_PREFIX=vibe`):

- http://localhost/
- http://localhost/vibe-chat/
- http://localhost/vibe-veronica/
- http://localhost/vibe-diff/
- http://localhost/vibe-shell-root/
- http://localhost/vibe-shell-app/

## Configuration (docker compose env)

See `.env.example` for all values.

### Ports

- `HTTP_PORT` - Apache listen port inside the container (default `80`)
- `HTTPS_PORT` - empty = HTTPS disabled; when set (e.g. `443`) an HTTPS vhost with the same routing is enabled. A self-signed certificate is generated on first start unless certificates are provided
- `SSL_CERT_PATH` / `SSL_KEY_PATH` - own certificates (e.g. mounted under `./data/certs/`); a self-signed certificate is generated when unset
- `HOST_HTTP_PORT` / `HOST_HTTPS_PORT` - host side of the port mapping in `docker-compose.yml`; the HTTPS mapping must be uncommented when `HTTPS_PORT` is set

### Routing

- `VIBE_PREFIX` - prefix for all service routes (default `vibe`), allowed characters: `a-z`, `0-9`, `-`
- `VIBE_NAME` - PWA app name (chat + veronica manifests) and start page title (default `Vibe4Dock`); page titles follow the pattern `$VIBE_NAME - Vibe4Dock` (services: `$APP - $VIBE_NAME - Vibe4Dock`)
- `SHELL_HINT` - branding line shown as the persistent tmux status bar inside the root/app shells (has a default with copyright + repo link)

### Basic Auth (via env)

- Start page: `SITE_USERNAME`/`SITE_PASSWORD` (protects the DocumentRoot `/` itself; the service routes are unaffected)
- Chat: `CHAT_USERNAME`/`CHAT_PASSWORD`
- Veronica: `VERONICA_USERNAME`/`VERONICA_PASSWORD`
- Root shell: `ROOT_SHELL_USERNAME`/`ROOT_SHELL_PASSWORD`
- Application shell: `APP_SHELL_USERNAME`/`APP_SHELL_PASSWORD`

General rule: **auth is only active when BOTH username and password are set.**

### opencode

Shared: `OPENCODE_API_KEY`, `OPENCODE_PROVIDER`, `OPENCODE_MODEL`, `OPENCODE_AGENT`.
Per-service overrides: `CHAT_OPENCODE_*` or `VERONICA_OPENCODE_*` (API_KEY, PROVIDER, MODEL, AGENT).

### File uploads (Chat + Veronica)

The 📎 button uploads to the project's `incoming/` directory; files are referenced in the prompt via `@filename`. Optional: `VIBE_INCOMING_DIR` overrides the target directory (default `/app/project/incoming`; set it if the project bind mount is read-only). Upload limit: 100 MB per file.

### Vibe-Diff (git working tree UI)

Browser UI for the git repo behind the code: current branch, branch list (with checkout), last 50 commits, changed files, and a unified diff view with **line-level and block-level revert** (like an IDE) plus whole-file revert. Language follows the `vibe4dock.lang` cookie (set by the chat/veronica UIs or the DE/EN switch in the header).

- `VIBE_DIFF_REPO` - repo path inside the container; **default: parent of the webroot (`/app`)**, i.e. `git ../` relative to the webroot. Mount your project repo (rw - reverts write to the worktree) and point this env to it
- `DIFF_USERNAME`/`DIFF_PASSWORD` - optional basic auth, same both-values rule as everywhere

```yaml
    environment:
      VIBE_DIFF_REPO: /app/project
      DIFF_USERNAME: diff
      DIFF_PASSWORD: change-me
    volumes:
      - ./project:/app/project
```

### Veronica

- **Plan mode toggle** - the header toggle sends a kickoff prompt with opencode's `plan` agent (`agent: 'plan'`) directly into the session; while on, every message from the send button runs in plan mode. State persists across reloads
- `VERONICA_ALLOW_REGISTRATION` - registration in the UI (`1`/`0`)
- `VERONICA_BOOTSTRAP_ADMIN` + `VERONICA_BOOTSTRAP_ADMIN_PIN_HASH` - admin seed, **only on first start** (when the JSON DB does not exist yet)
- `VERONICA_BOOTSTRAP_USERS` - optional extra users `"alias:sha256:...,alias:sha256:..."`
- The Veronica UI hashes PINs salted: `sha256` of `veronica:<alias>:<pin>`. **Raw PINs in the env seeds are accepted and salted automatically** (recommended). To pre-compute: `printf 'veronica:adm:1234' | sha256sum` -> `sha256:...` (replace alias/pin accordingly)

### Veronica user database (JSON, not public)

The users live server-side in `${VERONICA_USERS_FILE}` (default `/data/veronica-users.json`, mounted via compose volume `./data:/data`). The directory is **outside all web roots** and is never served.

- Schema (UI-native): `{"alias": {"pin": "sha256:...", "createdAt": 123, "admin": true}, ...}`
- API (behind Veronica basic auth): `GET /{VIBE_PREFIX}-veronica/api/users` reads, `PUT` replaces atomically (flock + tmp/rename)
- The UI syncs on load (server -> browser) and writes changes (registration, admin actions) back via `PUT`; `localStorage` is only an offline cache
- The env seeds are only used when the file does not exist yet - afterwards the JSON file is the single source of truth

## Differences from the multi-container stack

- No tools dashboard (`/vibe-dashboard`) and no addon management
- The upload endpoints of the chat/veronica UIs (`/api/upload*`) are served by a local PHP script (`/app/php/upload-api.php`) and write into the project's `incoming/` directory (instead of the tools container)
- Shells use HTTP basic auth instead of the form login (`vibe-auth` is not included)
- The opencode backends themselves have no auth - they are protected by the basic auth in front of them

## Build locally

Two variants exist (built from the same Dockerfile via `BASE_IMAGE` build-arg):

| Variant | Docker Hub image | Base | Purpose |
|---|---|---|---|
| production | `jbsnewmedia/vibe4dock-arcvd:<tag>` | `webdevops/php-apache:8.5` | normal operation |
| dev | `jbsnewmedia/vibe4dock-arcvd:<tag>-dev` | `webdevops/php-apache-dev:8.5` | xdebug, composer, dev tooling for shell work |

```bash
# production
docker build -t jbsnewmedia/vibe4dock-arcvd:1.0.3 .
docker run --rm -p 8080:80 -e OPENCODE_API_KEY=... jbsnewmedia/vibe4dock-arcvd:1.0.3

# dev variant
docker build --build-arg BASE_IMAGE=webdevops/php-apache-dev:8.5 --build-arg VARIANT=dev \
    -t jbsnewmedia/vibe4dock-arcvd:1.0.3-dev .
```

## Release (Docker Hub)

The GitHub Actions workflow `.github/workflows/docker.yml` builds and pushes on every push to `main` (`latest`) and on tags:

| Git tag | Docker Hub tags (production) | Docker Hub tags (dev) |
|---|---|---|
| push to `main` | `latest` | `latest-dev` |
| `1.0.0` or `v1.0.0` | `1.0.0`, `1.0`, `latest` | `1.0.0-dev`, `1.0-dev`, `latest-dev` |
| `1.0.1` or `v1.0.1` | `1.0.1`, `1.0`, `latest` | `1.0.1-dev`, `1.0-dev`, `latest-dev` |
| `1.0.2` or `v1.0.2` | `1.0.2`, `1.0`, `latest` | `1.0.2-dev`, `1.0-dev`, `latest-dev` |
| `1.0.3` or `v1.0.3` (current patch release) | `1.0.3`, `1.0`, `latest` | `1.0.3-dev`, `1.0-dev`, `latest-dev` |

Release notes per version live in `doc/rls/` (see `1.0.0.md`, `1.0.1.md`, `1.0.2.md`, `1.0.3.md`).

One-time setup in repo settings -> *Secrets and variables* -> *Actions* -> *New repository secret*:

- `DOCKERHUB_USERNAME` - Docker Hub login (`jbsnewmedia`)
- `DOCKERHUB_TOKEN` - Docker Hub -> Account Settings -> *Personal access tokens* -> *Generate new token* (permissions: Read & Write)

First release (bare and v-prefixed tags both trigger the workflow):

```bash
git tag 1.0.0 && git push origin 1.0.0
```

Patch releases afterwards: `git tag 1.0.1 && git push origin 1.0.1`.

### Re-publishing the same tag (force-move)

The `1.0` tag can be overwritten without bumping the version. Move the git tag and force-push it; the workflow then overwrites `1.0` on Docker Hub:

```bash
# commit the patch first, then:
git tag -f v1.0 && git push -f origin v1.0
```

Caveat: anyone who already pulled `1.0` keeps the old image until the next pull (the digest changes). Patch releases (`v1.0.1`) are the cleaner option because published tags stay immutable.
