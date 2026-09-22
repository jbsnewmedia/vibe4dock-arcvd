# jbsnewmedia/vibe4dock-arcvd - all-in-one image
#
# One container, one HTTP(S) port:
#   /                       -> project web root if the repo mounted at /app has
#                              a public/ directory, otherwise the start page
#   /{VIBE_PREFIX}-chat     -> Chat UI + opencode API
#   /{VIBE_PREFIX}-veronica -> Veronica UI + opencode API + server-side user JSON DB
#   /{VIBE_PREFIX}-shell-root / -shell-app -> ttyd shells
#
# The project repo lives at /app (compose pattern `./:/app`, like neun.app);
# the agent works there and /app/public is the web root. The image payload
# itself lives in /opt/vibe so a project mount cannot shadow it.
#
# Variants (build-arg):
#   BASE_IMAGE=webdevops/php-apache:8.5       -> production image
#   BASE_IMAGE=webdevops/php-apache-dev:8.5   -> dev image (xdebug, composer, dev tools)
ARG BASE_IMAGE=webdevops/php-apache:8.5
FROM ${BASE_IMAGE}

# VARIANT=dev toggles dev-only extras in the entrypoint/labels
ARG VARIANT=prod
ENV VIBE4DOCK_VARIANT=${VARIANT}

ENV DEBIAN_FRONTEND=noninteractive \
    TERM=xterm-256color

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        nano \
        openssl \
        sudo \
        supervisor \
        tmux \
    && rm -rf /var/lib/apt/lists/*

# Apache modules: API/WS proxying + output rewrite;
# drop the webdevops template vhost (its <PHP_SOCKET> placeholders are only
# filled by the webdevops entrypoint, which this image replaces)
RUN a2enmod proxy_http proxy_wstunnel substitute \
    && rm -f /etc/apache2/sites-enabled/10-docker.conf

# ttyd (web terminal)
RUN curl -fsSL https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
        -o /usr/bin/ttyd \
    && chmod +x /usr/bin/ttyd

# opencode CLI for the application user
RUN sudo -u application env HOME=/home/application bash -lc \
        'curl -fsSL https://opencode.ai/install | bash -s --'

# Application payload (lives outside /app so a project repo can be mounted there)
COPY build/www /opt/vibe/www
COPY build/chat/www /opt/vibe/chat-www
COPY build/veronica/www /opt/vibe/veronica-www
COPY build/diff/www /opt/vibe/diff-www
COPY build/php /opt/vibe/php

# Process manager + entrypoint (generates all Apache/php-fpm/wrapper config at start)
COPY supervisord/vibe-supervisord.conf /etc/vibe/supervisord.conf
COPY entrypoint/vibe-entrypoint.sh /usr/local/bin/vibe-entrypoint.sh
RUN chmod +x /usr/local/bin/vibe-entrypoint.sh \
    && mkdir -p /data /app \
    && chown application:application /data /app

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/vibe-entrypoint.sh"]
