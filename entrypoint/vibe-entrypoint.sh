#!/bin/bash
# vibe4dock-arcvd entrypoint: generates all runtime configuration from env
# vars, then hands over to supervisord.
#
# Generated artifacts:
#   /etc/vibe/auth/*.htpasswd          - per-service HTTP Basic Auth
#   /etc/vibe/run/*.sh                 - process wrappers (opencode, ttyd)
#   /etc/vibe/php-fpm.conf             - FPM pool (socket for Apache)
#   /etc/vibe/apache-routing.conf      - path routing (chat/veronica/shells)
#   /etc/apache2/ports.conf            - HTTP_PORT / HTTPS_PORT
#   /etc/apache2/sites-enabled/...     - HTTP + optional HTTPS vhost
#   /app/{chat-www,veronica-www}/config.js + cache-busted index.html
#   ${VERONICA_USERS_FILE}             - user JSON DB seed (if missing)
set -euo pipefail

VIBE_PREFIX="${VIBE_PREFIX:-vibe}"
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-}"
VERONICA_USERS_FILE="${VERONICA_USERS_FILE:-/data/veronica-users.json}"
VIBE_HOME="/opt/vibe"
WEB_ROOT=""                         # resolved below: project public/ or baked start page
CHAT_WWW="$VIBE_HOME/chat-www"
VERONICA_WWW="$VIBE_HOME/veronica-www"
CONFIG_DIR="/etc/vibe"
FPM_SOCKET="/run/php-fpm-vibe.sock"
VIBE_NAME="${VIBE_NAME:-Vibe4Dock}"
VIBE_NAME="${VIBE_NAME//\"/}"
VIBE_NAME="${VIBE_NAME//\\/}"
VIBE_NAME="${VIBE_NAME//|/}"

log() { echo "[vibe4dock-arcvd] $*"; }

mkdir -p "$CONFIG_DIR/auth" "$CONFIG_DIR/run" "$CONFIG_DIR/ssl" /run/apache2 /run/php

# ----------------------------------------------------------------------------
# Resolve per-service opencode settings (CHAT_OPENCODE_* / VERONICA_OPENCODE_*
# override the shared OPENCODE_* values)
# ----------------------------------------------------------------------------
resolve_chat_key()      { echo "${CHAT_OPENCODE_API_KEY:-${OPENCODE_API_KEY:-}}"; }
resolve_chat_provider() { echo "${CHAT_OPENCODE_PROVIDER:-${OPENCODE_PROVIDER:-}}"; }
resolve_chat_model()    { echo "${CHAT_OPENCODE_MODEL:-${OPENCODE_MODEL:-}}"; }
resolve_chat_agent()    { echo "${CHAT_OPENCODE_AGENT:-${OPENCODE_AGENT:-}}"; }
resolve_vero_key()      { echo "${VERONICA_OPENCODE_API_KEY:-${OPENCODE_API_KEY:-}}"; }
resolve_vero_provider() { echo "${VERONICA_OPENCODE_PROVIDER:-${OPENCODE_PROVIDER:-}}"; }
resolve_vero_model()    { echo "${VERONICA_OPENCODE_MODEL:-${OPENCODE_MODEL:-}}"; }
resolve_vero_agent()    { echo "${VERONICA_OPENCODE_AGENT:-${OPENCODE_AGENT:-}}"; }

# ----------------------------------------------------------------------------
# Basic auth htpasswd files (active only when username AND password are set)
# ----------------------------------------------------------------------------
write_htpasswd() {
    local file="$1" user="$2" pass="$3" hash
    if [ -n "$user" ] && [ -n "$pass" ]; then
        hash="$(openssl passwd -apr1 "$pass")"
        printf '%s:%s\n' "$user" "$hash" > "$file"
        chown root:www-data "$file"
        chmod 640 "$file"
        return 0
    fi
    rm -f "$file"
    return 1
}

# models.json lives under /home/... (directory deny default). Without its
# own Require line in the Location the Deny applies -> 403. Therefore:
# protect with service auth, without service auth explicitly grant.
CHAT_MODELS_AUTH="${CHAT_AUTH_BLOCK:-Require all granted}"
VERONICA_MODELS_AUTH="${VERONICA_AUTH_BLOCK:-Require all granted}"

auth_block() {
    local htpasswd="$1" realm="$2"
    cat <<AUTH
    AuthType Basic
    AuthName "$realm"
    AuthUserFile $htpasswd
    Require valid-user
AUTH
}

if write_htpasswd "$CONFIG_DIR/auth/chat.htpasswd" "${CHAT_USERNAME:-}" "${CHAT_PASSWORD:-}"; then
    CHAT_AUTH_BLOCK="$(auth_block "$CONFIG_DIR/auth/chat.htpasswd" "Chat")"
    log "Chat: basic auth enabled (${CHAT_USERNAME})"
else
    CHAT_AUTH_BLOCK=""
    log "Chat: no auth (CHAT_USERNAME/CHAT_PASSWORD not set)"
fi

if write_htpasswd "$CONFIG_DIR/auth/veronica.htpasswd" "${VERONICA_USERNAME:-}" "${VERONICA_PASSWORD:-}"; then
    VERONICA_AUTH_BLOCK="$(auth_block "$CONFIG_DIR/auth/veronica.htpasswd" "Veronica")"
    log "Veronica: basic auth enabled (${VERONICA_USERNAME})"
else
    VERONICA_AUTH_BLOCK=""
    log "Veronica: no auth (VERONICA_USERNAME/VERONICA_PASSWORD not set)"
fi

if write_htpasswd "$CONFIG_DIR/auth/shell-root.htpasswd" "${ROOT_SHELL_USERNAME:-}" "${ROOT_SHELL_PASSWORD:-}"; then
    ROOT_AUTH_BLOCK="$(auth_block "$CONFIG_DIR/auth/shell-root.htpasswd" "Root Shell")"
    log "Root shell: basic auth enabled (${ROOT_SHELL_USERNAME})"
else
    ROOT_AUTH_BLOCK=""
    log "Root shell: no auth (ROOT_SHELL_USERNAME/ROOT_SHELL_PASSWORD not set)"
fi

if write_htpasswd "$CONFIG_DIR/auth/shell-app.htpasswd" "${APP_SHELL_USERNAME:-}" "${APP_SHELL_PASSWORD:-}"; then
    APP_AUTH_BLOCK="$(auth_block "$CONFIG_DIR/auth/shell-app.htpasswd" "Application Shell")"
    log "App shell: basic auth enabled (${APP_SHELL_USERNAME})"
else
    APP_AUTH_BLOCK=""
    log "App shell: no auth (APP_SHELL_USERNAME/APP_SHELL_PASSWORD not set)"
fi

# Start page (DocumentRoot): protected only when both values are set.
# Applied via the <Directory> block so the service routes stay untouched.
if write_htpasswd "$CONFIG_DIR/auth/site.htpasswd" "${SITE_USERNAME:-}" "${SITE_PASSWORD:-}"; then
    SITE_DIR_AUTH="$(auth_block "$CONFIG_DIR/auth/site.htpasswd" "Vibe4Dock")"
    log "Site: basic auth enabled (${SITE_USERNAME})"
else
    SITE_DIR_AUTH="Require all granted"
    log "Site: no auth (SITE_USERNAME/SITE_PASSWORD not set)"
fi

# Vibe-Diff (git working tree UI), same rule as all services
if write_htpasswd "$CONFIG_DIR/auth/diff.htpasswd" "${DIFF_USERNAME:-}" "${DIFF_PASSWORD:-}"; then
    DIFF_AUTH_BLOCK="$(auth_block "$CONFIG_DIR/auth/diff.htpasswd" "Vibe-Diff")"
    log "Vibe-Diff: basic auth enabled (${DIFF_USERNAME})"
else
    DIFF_AUTH_BLOCK=""
    log "Vibe-Diff: no auth (DIFF_USERNAME/DIFF_PASSWORD not set)"
fi
# ----------------------------------------------------------------------------
# Project dir + web root: the project repo may be mounted at /app (compose
# pattern `./:/app`, like any PHP project with a public/ web root). When it
# has a public/ directory that becomes the web root ("/"); otherwise the
# baked Vibe4Dock start page is served (and stays reachable at /${P}-start).
# ----------------------------------------------------------------------------
PROJECT_DIR="${VIBE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
    if mountpoint -q /app 2>/dev/null || grep -qs " /app " /proc/mounts; then
        # /app ist ein Bind-Mount - es ist das Projekt (auch wenn noch leer)
        PROJECT_DIR="/app"
    elif [ -e /app/composer.json ] || [ -e /app/.git ] || [ -e /app/package.json ] || [ -d /app/public ]; then
        PROJECT_DIR="/app"
    elif [ -d /app/project ]; then
        PROJECT_DIR="/app/project"
    fi
fi
PROJECT_DIR="${PROJECT_DIR%/}"
if [ -z "$WEB_ROOT" ]; then
    if [ -n "$PROJECT_DIR" ]; then
        # public/ immer anlegen (auch bei leerem Projekt) und mit der
        # Vibe4Dock-Startseite vorbelegen - / zeigt damit die gewohnte
        # Uebersicht, bis der Agent eine eigene index.php/index.html baut
        # (DirectoryIndex bevorzugt index.php; beides ueberschreibt den
        # Platzhalter ohne Neustart). /vibe-start bleibt zusaetzlich da.
        mkdir -p "$PROJECT_DIR/public"
        if [ ! -e "$PROJECT_DIR/public/index.php" ] && [ ! -e "$PROJECT_DIR/public/index.html" ]; then
            cp "$VIBE_HOME/www/index.php" "$VIBE_HOME/www/favicon.png" \
               "$VIBE_HOME/www/favicon.ico" "$VIBE_HOME/www/logo.svg" \
               "$VIBE_HOME/www/robots.txt" "$PROJECT_DIR/public/" 2>/dev/null || true
        fi
        chown -R application:application "$PROJECT_DIR/public" 2>/dev/null || true
        chown application:application "$PROJECT_DIR" 2>/dev/null || true
        WEB_ROOT="$PROJECT_DIR/public"
    else
        WEB_ROOT="$VIBE_HOME/www"
    fi
fi
export VIBE_PROJECT_DIR="$PROJECT_DIR" VIBE_WEB_ROOT="$WEB_ROOT"
log "Project dir: ${PROJECT_DIR:-none} | Web root: $WEB_ROOT"

export VIBE_DIFF_REPO="${VIBE_DIFF_REPO:-${PROJECT_DIR:-/app/project}}"

# ----------------------------------------------------------------------------
# Frontend config.js + cache busting (same mechanism as the addon start.sh)
# ----------------------------------------------------------------------------
ASSET_V="$(date +%s)"

# Stuck-dialog threshold in minutes without any stream progress (default 10).
STUCK_MINUTES="${STUCK_MINUTES:-10}"
case "${STUCK_MINUTES}" in
    ''|*[!0-9]*) STUCK_MINUTES="10" ;;
esac

cat > "$CHAT_WWW/config.js" <<CFG
window.CHAT_CONFIG = {
    vibeName: "${VIBE_NAME}",
    provider: "$(resolve_chat_provider)",
    model: "$(resolve_chat_model)",
    agent: "$(resolve_chat_agent)",
    stuckMinutes: "${STUCK_MINUTES}"
};
CFG
sed -i "s/app.js/app.js?v=${ASSET_V}/; s/style.css/style.css?v=${ASSET_V}/; s/config.js/config.js?v=${ASSET_V}/; s/i18n.js/i18n.js?v=${ASSET_V}/; s/md.js/md.js?v=${ASSET_V}/" "$CHAT_WWW/index.html"

ALLOW_REGISTRATION="1"
case "${VERONICA_ALLOW_REGISTRATION:-1}" in
    0|false|no|off) ALLOW_REGISTRATION="0" ;;
esac

cat > "$VERONICA_WWW/config.js" <<CFG
window.CHAT_CONFIG = {
    vibeName: "${VIBE_NAME}",
    provider: "$(resolve_vero_provider)",
    model: "$(resolve_vero_model)",
    agent: "$(resolve_vero_agent)",
    allowRegistration: "${ALLOW_REGISTRATION}",
    stuckMinutes: "${STUCK_MINUTES}"
};
CFG
sed -i "s/app.js/app.js?v=${ASSET_V}/; s/style.css/style.css?v=${ASSET_V}/; s/config.js/config.js?v=${ASSET_V}/; s/i18n.js/i18n.js?v=${ASSET_V}/; s/md.js/md.js?v=${ASSET_V}/" "$VERONICA_WWW/index.html"

# ----------------------------------------------------------------------------
# PWA name: VIBE_NAME (default: Vibe4Dock) drives the manifest app names and
# the start page title. Manifests are regenerated so id/scope always follow
# the configured VIBE_PREFIX.
# ----------------------------------------------------------------------------

gen_manifest() {
    local file="$1" app="$2" desc="$3" theme="$4" bg="$5"
    cat > "$file" <<MAN
{
    "id": "/${VIBE_PREFIX}-${app}/",
    "name": "${VIBE_NAME}",
    "short_name": "${VIBE_NAME}",
    "description": "${VIBE_NAME} - ${desc}",
    "start_url": "./",
    "scope": "./",
    "display": "standalone",
    "orientation": "portrait",
    "background_color": "${bg}",
    "theme_color": "${theme}",
    "icons": [
        { "src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
        { "src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
        { "src": "icons/maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
    ]
}
MAN
}

gen_manifest "$CHAT_WWW/manifest.json" chat "chat" "#16181d" "#16181d"
gen_manifest "$VERONICA_WWW/manifest.json" veronica "veronica" "#54656f" "#f0f2f5"

if [ -f "$WEB_ROOT/index.php" ]; then
    sed -i "s|<title>Vibe4Dock</title>|<title>${VIBE_NAME} - Vibe4Dock</title>|" "$WEB_ROOT/index.php"
    sed -i "s|<h1>Vibe4Dock is running</h1>|<h1>${VIBE_NAME} is running</h1>|" "$WEB_ROOT/index.php"
    sed -i "s|<meta property=\"og:title\" content=\"[^\"]*\">|<meta property=\"og:title\" content=\"${VIBE_NAME}\">|" "$WEB_ROOT/index.php"
fi

chown -R application:application "$CHAT_WWW" "$VERONICA_WWW"

# ----------------------------------------------------------------------------
# Veronica user JSON DB: seed the file once if it does not exist yet.
#   VERONICA_BOOTSTRAP_ADMIN            - admin alias
#   VERONICA_BOOTSTRAP_ADMIN_PIN_HASH   - "sha256:..." (raw PIN also accepted)
#   VERONICA_BOOTSTRAP_USERS            - "alias:sha256:...,alias:sha256:..."
# Afterwards the DB is owned by the UI/API.
# ----------------------------------------------------------------------------
VDB_DIR="$(dirname "$VERONICA_USERS_FILE")"
mkdir -p "$VDB_DIR"
chown application:application "$VDB_DIR" 2>/dev/null || true

# The Veronica UI hashes PINs as "sha256:<sha256('veronica:<alias>:<pin>')>"
# (see app.js hashPin()). Raw PINs from the env seeds get the same salted
# scheme here so seeded accounts can actually log in.
normalize_pin_hash() {
    local v="$1" alias="$2"
    case "$v" in
        sha256:*) echo "$v" ;;
        '') echo '' ;;
        *) echo "sha256:$(printf 'veronica:%s:%s' "$alias" "$v" | sha256sum | cut -d' ' -f1)" ;;
    esac
}

sanitize_alias() {
    # allowlist for JSON safety
    printf '%s' "$1" | tr -cd 'a-zA-Z0-9._-'
}

if [ ! -f "$VERONICA_USERS_FILE" ]; then
    ADMIN_ALIAS="$(sanitize_alias "${VERONICA_BOOTSTRAP_ADMIN:-}")"
    ADMIN_PIN="$(normalize_pin_hash "${VERONICA_BOOTSTRAP_ADMIN_PIN_HASH:-}" "$ADMIN_ALIAS")"
    if [ -n "$ADMIN_ALIAS" ] && [ -n "$ADMIN_PIN" ]; then
        {
            printf '{\n  "%s": {"pin": "%s", "createdAt": %s, "admin": true}' \
                "$ADMIN_ALIAS" "$ADMIN_PIN" "$(date +%s000)"
            OLDIFS="$IFS"; IFS=','
            for entry in ${VERONICA_BOOTSTRAP_USERS:-}; do
                [ -z "$entry" ] && continue
                ALIAS="$(sanitize_alias "${entry%%:*}")"
                PIN="$(normalize_pin_hash "${entry#*:}" "$ALIAS")"
                [ -z "$ALIAS" ] || [ -z "$PIN" ] && continue
                [ "$ALIAS" = "$ADMIN_ALIAS" ] && continue
                printf ',\n  "%s": {"pin": "%s", "createdAt": %s}' "$ALIAS" "$PIN" "$(date +%s000)"
            done
            IFS="$OLDIFS"
            printf '\n}\n'
        } > "$VERONICA_USERS_FILE"
        log "Veronica user DB created: $VERONICA_USERS_FILE (admin: $ADMIN_ALIAS)"
    else
        printf '{}\n' > "$VERONICA_USERS_FILE"
        log "Veronica user DB initialized (empty): $VERONICA_USERS_FILE"
    fi
fi
touch "$VERONICA_USERS_FILE.lock"
chown application:application "$VERONICA_USERS_FILE" "$VERONICA_USERS_FILE.lock" 2>/dev/null \
    || log "WARNING: $VERONICA_USERS_FILE is not writable by PHP (owner: $(stat -c %U "$VERONICA_USERS_FILE" 2>/dev/null || echo '?')) - user DB is read-only"

# ----------------------------------------------------------------------------
# php-fpm pool config (clear_env=no so the API can read VERONICA_USERS_FILE)
# ----------------------------------------------------------------------------
cat > "$CONFIG_DIR/php-fpm.conf" <<FPM
[global]
error_log = /proc/self/fd/2
daemonize = no

[www]
user = application
group = application
listen = ${FPM_SOCKET}
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
catch_workers_output = yes
clear_env = no
security.limit_extensions = .php
php_admin_value[upload_max_filesize] = 100M
php_admin_value[post_max_size] = 120M
php_admin_value[max_execution_time] = 300
php_admin_value[memory_limit] = 256M
FPM

# ----------------------------------------------------------------------------
# Process wrappers
# ----------------------------------------------------------------------------
cat > "$CONFIG_DIR/run/apache.sh" <<'WRAP'
#!/bin/sh
# Remove stale PID files (docker restart: the PID is recycled, otherwise
# apache2ctl believes an httpd is already running)
rm -f /run/apache2/apache2.pid
exec /usr/sbin/apache2ctl -DFOREGROUND
WRAP

cat > "$CONFIG_DIR/run/opencode-chat.sh" <<'WRAP'
#!/bin/sh
set -e
export HOME=/home/application
export PATH="/home/application/.opencode/bin:$PATH"
export ANTHROPIC_API_KEY="${CHAT_OPENCODE_API_KEY:-${OPENCODE_API_KEY:-}}"
if [ -n "$ANTHROPIC_API_KEY" ]; then
    export OPENAI_API_KEY="${CHAT_OPENCODE_API_KEY:-${OPENCODE_API_KEY:-}}"
fi
export OPENCODE_PROVIDER="${CHAT_OPENCODE_PROVIDER:-${OPENCODE_PROVIDER:-}}"
export OPENCODE_MODEL="${CHAT_OPENCODE_MODEL:-${OPENCODE_MODEL:-}}"
export OPENCODE_AGENT="${CHAT_OPENCODE_AGENT:-${OPENCODE_AGENT:-}}"
cd "${VIBE_PROJECT_DIR:-/app/project}"
exec opencode serve --hostname 127.0.0.1 --port 4577 --print-logs --log-level INFO
WRAP

cat > "$CONFIG_DIR/run/opencode-veronica.sh" <<'WRAP'
#!/bin/sh
set -e
export HOME=/home/application
export PATH="/home/application/.opencode/bin:$PATH"
export ANTHROPIC_API_KEY="${VERONICA_OPENCODE_API_KEY:-${OPENCODE_API_KEY:-}}"
if [ -n "$ANTHROPIC_API_KEY" ]; then
    export OPENAI_API_KEY="${VERONICA_OPENCODE_API_KEY:-${OPENCODE_API_KEY:-}}"
fi
export OPENCODE_PROVIDER="${VERONICA_OPENCODE_PROVIDER:-${OPENCODE_PROVIDER:-}}"
export OPENCODE_MODEL="${VERONICA_OPENCODE_MODEL:-${OPENCODE_MODEL:-}}"
export OPENCODE_AGENT="${VERONICA_OPENCODE_AGENT:-${OPENCODE_AGENT:-}}"
cd "${VIBE_PROJECT_DIR:-/app/project}"
# Stagger the start: both opencode instances share the SQLite DB in
# ~/.local/share/opencode - starting them at the same instant can crash
# the second one with "database is locked" (supervisor then restarts it).
sleep 3
exec opencode serve --hostname 127.0.0.1 --port 4578 --print-logs --log-level INFO
WRAP

# Tab title injection for the ttyd pages (nginx parity: sub_filter).
# ttyd 1.7.x has no --title-format, hence mod_substitute. The Substitute
# directives live directly in the routing heredoc so the \" escapes reach
# Apache instead of being consumed by the shell.

# ----------------------------------------------------------------------------
# Shell branding: persistent tmux status line at the top (cyan) with the
# hint text, window titles, and a bashrc that keeps the title in sync.
# SHELL_HINT env overrides the branding line.
# ----------------------------------------------------------------------------
SHELL_HINT="${SHELL_HINT:-Part of Vibe4Dock · © 2026+ JBS New Media GmbH · Juergen Schwind · github.com/jbsnewmedia/vibe4dock · MIT License}"
HINT_SH="'$(printf '%s' "$SHELL_HINT" | sed "s/'/'\\\\''/g")'"

cat > "$CONFIG_DIR/shell.bashrc" <<'BRC'
# shellcheck shell=bash
if [ -f /etc/bash.bashrc ]; then
    . /etc/bash.bashrc
fi

if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

PROMPT_COMMAND='printf "\033]0;%s\007" "$VIBE4DOCK_SHELL_HINT"'
BRC

gen_tmux_script() {
    local file="$1" title="$2" session="$3"
    sed -e "s/__TITLE__/$title/g" -e "s/__SESSION__/$session/g" > "$file" <<'TMUX'
#!/bin/sh
printf '\033]0;%s\007' '__TITLE__'
exec tmux start-server \
    \; set-option -g status on \
    \; set-option -g status-position top \
    \; set-option -g status-style 'bg=cyan,fg=black' \
    \; set-option -g status-left-style 'bg=cyan,fg=black' \
    \; set-option -g status-right-style 'bg=cyan,fg=black' \
    \; set-option -g status-left-length 240 \
    \; set-option -g status-right '' \
    \; set-option -g status-left " $VIBE4DOCK_SHELL_HINT " \
    \; set-option -g window-status-format '' \
    \; set-option -g window-status-current-format '' \
    \; set-option -g default-command "env VIBE4DOCK_SHELL_HINT=\"$VIBE4DOCK_SHELL_HINT\" bash --noprofile --rcfile /etc/vibe/shell.bashrc" \
    \; set-option -g set-titles on \
    \; set-option -g set-titles-string '__TITLE__' \
    \; new-session -A -s __SESSION__
TMUX
}

gen_tmux_script "$CONFIG_DIR/run/tmux-root.sh" 'Root Shell - Vibe4Dock' 'root'
gen_tmux_script "$CONFIG_DIR/run/tmux-app.sh" 'Application Shell - Vibe4Dock' 'main'

cat > "$CONFIG_DIR/run/shell-root.sh" <<WRAP
#!/bin/sh
export VIBE4DOCK_SHELL_HINT=$HINT_SH
exec /usr/bin/ttyd \\
    --writable \\
    --port 7681 \\
    --interface 127.0.0.1 \\
    --base-path /${VIBE_PREFIX}-shell-root \\
    /bin/sh /etc/vibe/run/tmux-root.sh
WRAP

cat > "$CONFIG_DIR/run/shell-app.sh" <<WRAP
#!/bin/sh
exec /usr/bin/ttyd \\
    --writable \\
    --port 7682 \\
    --interface 127.0.0.1 \\
    --base-path /${VIBE_PREFIX}-shell-app \\
    sudo -u application env VIBE4DOCK_SHELL_HINT=$HINT_SH /bin/sh /etc/vibe/run/tmux-app.sh
WRAP

chmod +x "$CONFIG_DIR/run/"*.sh

# ----------------------------------------------------------------------------
# Apache ports + globals
# ----------------------------------------------------------------------------
{
    echo "Listen ${HTTP_PORT}"
    if [ -n "$HTTPS_PORT" ]; then
        echo "Listen ${HTTPS_PORT}"
    fi
} > /etc/apache2/ports.conf

echo "ServerName localhost" > /etc/apache2/conf-enabled/vibe-globals.conf

# Security hardening: hide server version, send baseline security headers
cat > /etc/apache2/conf-enabled/vibe-security.conf <<'SEC'
ServerTokens Prod
ServerSignature Off

<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Permissions-Policy "geolocation=(), camera=(), microphone=(), payment=(), usb=()"
    Header always set Content-Security-Policy "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self' *; font-src 'self' data:; base-uri 'self'; frame-ancestors 'self'"
</IfModule>
SEC

# ----------------------------------------------------------------------------
# Apache routing (shared between HTTP and HTTPS vhost)
# ----------------------------------------------------------------------------
P="$VIBE_PREFIX"

cat > "$CONFIG_DIR/apache-routing.conf" <<ROUTING
# Generated by vibe-entrypoint.sh - prefix: /${P}

<Location /${P}-chat>
${CHAT_AUTH_BLOCK}
</Location>
# Upload endpoints -> PHP via FPM (writes into the project's incoming/ dir)
ProxyPass /${P}-chat/api/upload !
Alias /${P}-chat/api/upload/file ${VIBE_HOME}/php/upload-api.php
Alias /${P}-chat/api/upload/list ${VIBE_HOME}/php/upload-api.php
Alias /${P}-chat/api/upload ${VIBE_HOME}/php/upload-api.php
ProxyPass /${P}-chat/api/ http://127.0.0.1:4577/ retry=0
Alias /${P}-chat/models.json /home/application/.local/state/opencode/model.json
<Location /${P}-chat/models.json>
${CHAT_MODELS_AUTH}
    ForceType application/json
    Header set Cache-Control "no-cache"
</Location>
Alias /${P}-chat/ ${VIBE_HOME}/chat-www/
RedirectMatch 301 ^/${P}-chat\$ /${P}-chat/

<Location /${P}-veronica>
${VERONICA_AUTH_BLOCK}
</Location>
ProxyPass /${P}-veronica/api/users !
Alias /${P}-veronica/api/users ${VIBE_HOME}/php/veronica-users-api.php
# Upload endpoints -> PHP via FPM (writes into the project's incoming/ dir)
ProxyPass /${P}-veronica/api/upload !
Alias /${P}-veronica/api/upload/file ${VIBE_HOME}/php/upload-api.php
Alias /${P}-veronica/api/upload/list ${VIBE_HOME}/php/upload-api.php
Alias /${P}-veronica/api/upload ${VIBE_HOME}/php/upload-api.php
ProxyPass /${P}-veronica/api/ http://127.0.0.1:4578/ retry=0
Alias /${P}-veronica/models.json /home/application/.local/state/opencode/model.json
<Location /${P}-veronica/models.json>
${VERONICA_MODELS_AUTH}
    ForceType application/json
    Header set Cache-Control "no-cache"
</Location>
Alias /${P}-veronica/ ${VIBE_HOME}/veronica-www/
RedirectMatch 301 ^/${P}-veronica\$ /${P}-veronica/

<Location /${P}-diff>
${DIFF_AUTH_BLOCK}
</Location>
Alias /${P}-diff/ ${VIBE_HOME}/diff-www/
RedirectMatch 301 ^/${P}-diff\$ /${P}-diff/

# Vibe4Dock start page (reachable even when a project public/ owns the web root)
Alias /${P}-start/ ${VIBE_HOME}/www/
Alias /${P}-start ${VIBE_HOME}/www
RedirectMatch 301 ^/${P}-start\$ /${P}-start/

<Location /${P}-shell-root>
${ROOT_AUTH_BLOCK}
    AddOutputFilterByType SUBSTITUTE text/html
    Substitute "s|</head>|<style>*{scrollbar-width:thin;scrollbar-color:#2b3340 transparent}::-webkit-scrollbar{width:10px;height:10px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:#2b3340;border-radius:5px}::-webkit-scrollbar-thumb:hover{background:#3d4757}</style><script>var t=\"Root Shell - Vibe4Dock\";(function(){var d=Object.getOwnPropertyDescriptor(Document.prototype,\"title\");if(d&&d.set)d.set.call(document,t)})();Object.defineProperty(document,\"title\",{get:function(){return t},set:function(){}})</script></head>|"
    ProxyPass http://127.0.0.1:7681/${P}-shell-root retry=0 upgrade=websocket
</Location>
RedirectMatch 301 ^/${P}-shell-root\$ /${P}-shell-root/

<Location /${P}-shell-app>
${APP_AUTH_BLOCK}
    AddOutputFilterByType SUBSTITUTE text/html
    Substitute "s|</head>|<style>*{scrollbar-width:thin;scrollbar-color:#2b3340 transparent}::-webkit-scrollbar{width:10px;height:10px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:#2b3340;border-radius:5px}::-webkit-scrollbar-thumb:hover{background:#3d4757}</style><script>var t=\"Application Shell - Vibe4Dock\";(function(){var d=Object.getOwnPropertyDescriptor(Document.prototype,\"title\");if(d&&d.set)d.set.call(document,t)})();Object.defineProperty(document,\"title\",{get:function(){return t},set:function(){}})</script></head>|"
    ProxyPass http://127.0.0.1:7682/${P}-shell-app retry=0 upgrade=websocket
</Location>
RedirectMatch 301 ^/${P}-shell-app\$ /${P}-shell-app/
ROUTING

# ----------------------------------------------------------------------------
# Vhosts (HTTP always, HTTPS optional)
# ----------------------------------------------------------------------------
write_vhost_body() {
    cat <<VHOST
    ServerName localhost
    UseCanonicalName Off
    ProxyPreserveHost On
    ProxyTimeout 3600

    DocumentRoot ${WEB_ROOT}
    <Directory ${WEB_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        DirectoryIndex index.php index.html
${SITE_DIR_AUTH}
    </Directory>
    <Directory ${VIBE_HOME}>
        Options -Indexes
        Require all granted
    </Directory>
    <Directory ${VIBE_HOME}/www>
        Options -Indexes
        Require all granted
    </Directory>
    <Directory ${VIBE_HOME}/php>
        Options -Indexes
        Require all granted
    </Directory>
    <Directory ${VIBE_HOME}/diff-www>
        Options -Indexes
        Require all granted
    </Directory>
    <FilesMatch \.php\$>
        SetHandler "proxy:unix:${FPM_SOCKET}|fcgi://localhost"
    </FilesMatch>

    Include ${CONFIG_DIR}/apache-routing.conf

    ErrorLog /dev/stderr
    CustomLog /dev/stdout combined
VHOST
}

{
    echo "# Generated by vibe-entrypoint.sh"
    echo "<VirtualHost *:${HTTP_PORT}>"
    write_vhost_body
    echo "</VirtualHost>"
} > /etc/apache2/sites-enabled/vibe4dock-arcvd.conf

if [ -n "$HTTPS_PORT" ]; then
    CERT_FILE="${SSL_CERT_PATH:-$CONFIG_DIR/ssl/selfsigned.crt}"
    KEY_FILE="${SSL_KEY_PATH:-$CONFIG_DIR/ssl/selfsigned.key}"
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        log "HTTPS: generating self-signed certificate (${CERT_FILE})"
        openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -subj "/CN=localhost" \
            -keyout "$KEY_FILE" -out "$CERT_FILE" >/dev/null 2>&1
    fi
    {
        echo "# Generated by vibe-entrypoint.sh (HTTPS)"
        echo "<VirtualHost *:${HTTPS_PORT}>"
        write_vhost_body
        cat <<SSL
    SSLEngine on
    SSLCertificateFile ${CERT_FILE}
    SSLCertificateKeyFile ${KEY_FILE}
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
SSL
        echo "</VirtualHost>"
    } >> /etc/apache2/sites-enabled/vibe4dock-arcvd.conf
    log "HTTPS enabled on port ${HTTPS_PORT}"
fi

log "Routes: / (project public/ or start page) | /${P}-start | /${P}-chat | /${P}-veronica | /${P}-diff | /${P}-shell-root | /${P}-shell-app"

# ----------------------------------------------------------------------------
# opencode data dirs: prepare for optional bind mounts (config, sessions,
# state). Docker creates host dirs as root - hand them to the application
# user so opencode can write settings, sessions and models.json.
# ----------------------------------------------------------------------------
mkdir -p /home/application/.config/opencode \
         /home/application/.local/share/opencode \
         /home/application/.local/state/opencode
chown -R application:application \
    /home/application/.config/opencode \
    /home/application/.local/share/opencode \
    /home/application/.local/state/opencode 2>/dev/null \
    || log "WARNING: opencode data dirs not writable by application user - settings/sessions may not persist"

# ----------------------------------------------------------------------------
# Veronica persona: assembled from MULTI-FILE rule folders so the persona can
# be extended flexibly (bind-mount or edit on the host, then restart):
#   <opencode-config>/persona/veronica/*.md        - shared persona rules
#   <opencode-config>/persona/veronica-plan/*.md   - identity + plan restrictions
# The generated agent files (<opencode-config>/agent/*.md) are rebuilt from
# these on every container start - do not edit them directly.
# ----------------------------------------------------------------------------
VIBE_OCODE_AGENT_DIR="/home/application/.config/opencode/agent"
VIBE_PERSONA_DIR="/home/application/.config/opencode/persona"
mkdir -p "$VIBE_OCODE_AGENT_DIR" "$VIBE_PERSONA_DIR/veronica" "$VIBE_PERSONA_DIR/veronica-plan"

if [ ! -e "$VIBE_PERSONA_DIR/veronica/10-identity.md" ]; then
cat > "$VIBE_PERSONA_DIR/veronica/10-identity.md" <<'PERSONA'
You are Veronica, the assistant of Vibe4Dock by JBS New Media GmbH, based in Worms, Germany.

- If someone asks in German who you are, answer exactly: "Ich bin Veronica von Vibe4Dock, dem Assistenten-System von der JBS New Media GmbH in Worms."
- If someone asks in English who you are, answer exactly: "I am Veronica from Vibe4Dock, the assistant system by JBS New Media GmbH in Worms."
- For any other language, use the English variant.
PERSONA
fi
if [ ! -e "$VIBE_PERSONA_DIR/veronica/20-style.md" ]; then
cat > "$VIBE_PERSONA_DIR/veronica/20-style.md" <<'PERSONA'
- You are friendly, precise and solution-oriented, and you always reply in the language of the question (German or English).
- You work directly in the users' project directory.
PERSONA
fi
if [ ! -e "$VIBE_PERSONA_DIR/veronica-plan/10-identity.md" ]; then
cat > "$VIBE_PERSONA_DIR/veronica-plan/10-identity.md" <<'PERSONA'
You are Veronica, the assistant of Vibe4Dock by JBS New Media GmbH, based in Worms, Germany.

- If someone asks in German who you are, answer exactly: "Ich bin Veronica von Vibe4Dock, dem Assistenten-System von der JBS New Media GmbH in Worms."
- If someone asks in English who you are, answer exactly: "I am Veronica from Vibe4Dock, the assistant system by JBS New Media GmbH in Worms."
- For any other language, use the English variant.
PERSONA
fi
if [ ! -e "$VIBE_PERSONA_DIR/veronica-plan/20-plan-mode.md" ]; then
cat > "$VIBE_PERSONA_DIR/veronica-plan/20-plan-mode.md" <<'PERSONA'
- You are currently in PLAN MODE. In this mode you must NOT create, modify or delete any files - even if asked to.
- This also applies to shell commands: never use redirections (>, >>), tee, cp, mv, rm, touch, mkdir, sed -i or any other command that writes - shell use in plan mode is strictly read-only.
- In plan mode you only read and analyze: gather information, answer questions, and provide a concrete implementation plan in your reply.
- Never end a plan by asking for a confirmation or a reply: no "sag Bescheid", no "weiter"/"los", no "say the word", no closing question. The implementation starts when the user switches off the Plan toggle at the top of the chat - the UI then sends the GO automatically. If you mention how to start, say exactly that.
- Once plan mode is ended (you will notice that you are addressed without the plan-mode context), you work as usual again - then creating and modifying files is allowed again.
PERSONA
fi

assemble_persona() {
    local agent="$1" desc="$2" extra_yaml="$3"
    local dir="$VIBE_PERSONA_DIR/$agent"
    {
        echo "---"
        echo "# GENERATED by vibe-entrypoint.sh at container start - do not edit."
        echo "# Extend the persona with files in persona/$agent/*.md instead, then restart."
        echo "description: $desc"
        echo "mode: primary"
        echo "hidden: true"
        if [ -n "$extra_yaml" ]; then
            printf '%s\n' "$extra_yaml"
        fi
        echo "---"
        echo
        cat "$VIBE_PERSONA_DIR/$agent"/*.md 2>/dev/null
    } > "$VIBE_OCODE_AGENT_DIR/$agent.md"
}

if [ ! -e "$VIBE_PERSONA_DIR/veronica/30-project.md" ]; then
cat > "$VIBE_PERSONA_DIR/veronica/30-project.md" <<'PERSONA'
- The project scaffold is already fully prepared: the folder structure, configuration and infrastructure exist and are wired up and working. There is nothing to set up or rebuild - do not recreate the existing structure.
- Your main focus is the CONTENT: the web root `public/` in the project directory is what gets served.
- The whole project directory is your working area: fetch packages with composer, extend src/, adjust config - whatever the task requires. Work in the existing structure instead of replacing it, and do not touch the docker setup unless the user explicitly asks for it.
- Content must be self-contained: bundle fonts, styles and assets locally inside `public/` (no external CDN dependencies such as Google Fonts).
PERSONA
fi
if [ ! -e "$VIBE_PERSONA_DIR/veronica-plan/30-project.md" ]; then
cat > "$VIBE_PERSONA_DIR/veronica-plan/30-project.md" <<'PERSONA'
- The project scaffold is already fully prepared: the folder structure, configuration and infrastructure exist and are wired up and working. Plans must respect that - there is nothing to scaffold, do not plan rebuilding the existing structure.
- The main focus is the content: changes to the web root `public/` in the project directory.
- The whole project directory is in scope for plans: fetching composer packages, extending src/, adjusting config - whatever the task requires. Do not plan changes to the docker setup unless the user explicitly asks for them.
- Content must be self-contained: plan locally bundled fonts, styles and assets inside `public/` (no external CDN dependencies such as Google Fonts).
PERSONA
fi

assemble_persona "veronica" "Veronica - Vibe4Dock assistant persona (internal)" ""
assemble_persona "veronica-plan" "Veronica - Vibe4Dock assistant persona in plan mode, read-only (internal)" "tools:
  write: false
  edit: false
  patch: false
permission:
  edit: deny
  bash: deny"

chown -R application:application "$VIBE_OCODE_AGENT_DIR" "$VIBE_PERSONA_DIR" 2>/dev/null \
    || log "WARNING: Veronica persona not writable by application user"

# ----------------------------------------------------------------------------
# Chat/Veronica uploads land in the project's incoming/ dir so the agent can
# reference them via @name. The project dir may be a bind mount owned by root -
# hand the incoming dir to the application user (php-fpm) for uploads.
# ----------------------------------------------------------------------------
VIBE_INCOMING_DIR="${VIBE_INCOMING_DIR:-${VIBE_PROJECT_DIR:-/app/project}/incoming}"
export VIBE_INCOMING_DIR
mkdir -p "$VIBE_INCOMING_DIR"
chown application:application "$VIBE_INCOMING_DIR" 2>/dev/null \
    || log "WARNING: $VIBE_INCOMING_DIR not chown-able - file uploads may fail"

# ----------------------------------------------------------------------------
# Hand over to supervisord
# ----------------------------------------------------------------------------
exec /usr/bin/supervisord -c /etc/vibe/supervisord.conf
