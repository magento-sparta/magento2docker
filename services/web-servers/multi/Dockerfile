ARG M2D_WEB_SERVER_PHP_VERSION='8.2'
ARG M2D_ENABLE_BLACKFIRE='no'
ARG M2D_ENABLE_MAILCATCHER='no'
ARG M2D_APACHE_ROOT_DIRECTORY='/var/www/html'

## MINICA CERTIFICATE BUILDER ##
FROM golang:1.22-bullseye AS minica_builder
RUN go install github.com/jsha/minica@latest
RUN mkdir /certs && cd /certs && minica --domains '*.127.0.0.1.nip.io,*.php81.127.0.0.1.nip.io,*.php82.127.0.0.1.nip.io,*.php83.127.0.0.1.nip.io,*.php84.127.0.0.1.nip.io,*.php85.127.0.0.1.nip.io'

## BASE IMAGE - ALL PHP VERSIONS ##
FROM debian:bullseye AS m2d_web_server_multi_base

ARG M2D_WEB_SERVER_PHP_VERSION
ARG M2D_WEB_SERVER_PHP_MEMORY_LIMIT='2G'
ARG M2D_XDEBUG_IDE_KEY='PHPSTORM'
ARG M2D_APACHE_ROOT_DIRECTORY
ENV M2D_WEB_SERVER_PHP_VERSION=${M2D_WEB_SERVER_PHP_VERSION}
ENV M2D_WEB_SERVER_PHP_MEMORY_LIMIT=${M2D_WEB_SERVER_PHP_MEMORY_LIMIT}
ENV M2D_XDEBUG_IDE_KEY=${M2D_XDEBUG_IDE_KEY}
ENV M2D_APACHE_ROOT_DIRECTORY=${M2D_APACHE_ROOT_DIRECTORY}

# SETTING UP THE SYSTEM:
RUN apt-get update && apt-get install -y \
        apache2 \
        apt-transport-https \
        apt-utils \
        autoconf \
        automake \
        bash-completion \
        ca-certificates \
        cmake \
        curl \
        dnsutils \
        g++ \
        gcc \
        git \
        gnupg \
        host \
        iputils-ping \
        iputils-tracepath \
        libatomic1 \
        libglib2.0-dev \
        libmariadb-dev \
        libmariadb-dev-compat \
        libpcre3-dev \
        libssl-dev \
        libzstd-dev \
        lsb-release \
        lsof \
        mariadb-client \
        mc \
        nano \
        openssh-server \
        parallel \
        pip \
        pv \
        rsync \
        software-properties-common \
        ssl-cert \
        strace \
        sudo \
        telnet \
        unzip \
        vim \
        wget \
        zlib1g-dev \
    && apt-get clean all

# ondrej/php PPA:
RUN curl -sSL https://packages.sury.org/php/apt.gpg \
        | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/sury-php.list \
    && apt-get update

# PHP EXTENSIONS FOR ALL VERSIONS:
ARG PHP_EXTENSIONS="fpm cli bcmath curl gd intl mbstring mysql soap sockets xml xsl zip"
ARG CACHEBUST_PHP_EXT=1
RUN echo "ext-cache:${CACHEBUST_PHP_EXT}" && for ver in 8.1 8.2 8.3 8.4 8.5; do \
        pkgs=""; \
        for ext in $PHP_EXTENSIONS; do pkgs="$pkgs php${ver}-${ext}"; done; \
        apt-get install -y $pkgs || echo "WARN: some packages for PHP ${ver} unavailable"; \
        phpenmod -v ${ver} -s cli bcmath curl gd intl mbstring xml xsl zip soap sockets 2>/dev/null || true; \
    done \
    && apt-get install -y php-pear \
    && apt-get clean all

# UOPZ PER VERSION (for extension_loaded override; not available for all versions — failures silenced):
RUN for ver in 8.1 8.2 8.3 8.4 8.5; do \
        apt-get install -y php${ver}-uopz 2>/dev/null || true; \
    done

# XDEBUG PER VERSION (enabled by default, warnings suppressed):
RUN for ver in 8.1 8.2 8.3 8.4 8.5; do \
        apt-get install -y php${ver}-xdebug 2>/dev/null || true; \
        for sapi in fpm cli; do \
            ini="/etc/php/${ver}/${sapi}/conf.d/20-xdebug.ini"; \
            [ -f "$ini" ] || continue; \
            printf "xdebug.idekey=%s\nxdebug.client_host=host.docker.internal\nxdebug.mode=debug\nxdebug.start_with_request=yes\nxdebug.max_nesting_level=10000\nxdebug.log_level=0\n;xdebug.log = ${M2D_APACHE_ROOT_DIRECTORY}/xdebug.log\nxdebug.client_port = 9003\n" \
                "${M2D_XDEBUG_IDE_KEY}" >> "$ini"; \
        done; \
    done

# MEMORY LIMIT FOR ALL VERSIONS:
RUN for ver in 8.1 8.2 8.3 8.4 8.5; do \
        mkdir -p /etc/php/${ver}/fpm/conf.d; \
        echo "memory_limit = ${M2D_WEB_SERVER_PHP_MEMORY_LIMIT}" \
            > /etc/php/${ver}/fpm/conf.d/99-memory-limit.ini; \
    done

# PHP CONFIG FILES (prepend + custom ini):
COPY ./services/web-servers/apache/etc/php/prepend.php /usr/local/lib/php/prepend.php
COPY ./services/web-servers/apache/etc/php/custom.ini  /usr/local/lib/php/custom.ini
RUN for ver in 8.1 8.2 8.3 8.4 8.5; do \
        cp /usr/local/lib/php/custom.ini /etc/php/${ver}/fpm/conf.d/99-custom.ini; \
        cp /usr/local/lib/php/custom.ini /etc/php/${ver}/cli/conf.d/99-custom.ini; \
        echo "auto_prepend_file = /usr/local/lib/php/prepend.php" \
            > /etc/php/${ver}/cli/conf.d/99-prepend.ini; \
        echo "auto_prepend_file = /usr/local/lib/php/prepend.php" \
            > /etc/php/${ver}/fpm/conf.d/99-prepend.ini; \
    done

# FPM POOL — EACH VERSION GETS ITS OWN UNIX SOCKET:
RUN for ver in 8.1 8.2 8.3 8.4 8.5; do \
        cfg="/etc/php/${ver}/fpm/pool.d/www.conf"; \
        if [ -f "$cfg" ]; then \
            sed -i "s|listen = .*|listen = /run/php/php${ver}-fpm.sock|" "$cfg"; \
            sed -i "s|^user = .*|user = ${APACHE_RUN_USER:=magento}|"   "$cfg"; \
            sed -i "s|^group = .*|group = ${APACHE_RUN_GROUP:=magento}|" "$cfg"; \
            echo "env[M2D_APACHE_ROOT_DIRECTORY] = \${M2D_APACHE_ROOT_DIRECTORY}" >> "$cfg"; \
        fi; \
    done

# DEFAULT PHP CLI = M2D_WEB_SERVER_PHP_VERSION:
RUN update-alternatives --set php /usr/bin/php${M2D_WEB_SERVER_PHP_VERSION} 2>/dev/null || \
    ln -sf /usr/bin/php${M2D_WEB_SERVER_PHP_VERSION} /usr/local/bin/php

# DOTLESS CLI ALIASES: php81 → php8.1 etc.
RUN for ver in 8.1 8.2 8.3 8.4 8.5; do \
        ln -sf "/usr/bin/php${ver}" "/usr/local/bin/php$(echo $ver | tr -d '.')"; \
    done

# CREATE USER:
ENV _USER=magento
ENV _HOME_DIRECTORY=/home/magento
RUN useradd -m magento && echo "magento:magento" | chpasswd \
    && chsh magento -s /bin/bash \
    && adduser magento sudo

# NODEJS:
RUN curl -sL https://deb.nodesource.com/setup_20.x | bash \
    && apt-get install -y nodejs
RUN npm install --global yarn

# INSTALL COMPOSER 1 AND COMPOSER 2:
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer1 --1 \
    && mkdir -p ${_HOME_DIRECTORY}/.composer \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer2 --2 \
    && ln -s /usr/local/bin/composer2 /usr/local/bin/composer

# TOOLS:
COPY ./services/web-servers/apache/tools/* /usr/local/bin/
COPY ./services/web-servers/multi/tools/* /usr/local/bin/

# CUSTOM CONFIGURATIONS:
COPY ./services/web-servers/apache/etc/fixtures /etc/fixtures

# SSH:
COPY ./services/web-servers/apache/etc/ssh ${_HOME_DIRECTORY}/.ssh
ADD  ./services/web-servers/apache/etc/ssh/magento2docker.pub ${_HOME_DIRECTORY}/.ssh/authorized_keys
RUN chmod -R 700 ${_HOME_DIRECTORY}/.ssh \
    && echo "    ServerAliveInterval 30" >> /etc/ssh/ssh_config \
    && echo "    TCPKeepAlive yes" >> /etc/ssh/ssh_config
COPY ./services/web-servers/apache/etc/ssh /root/.ssh
ADD  ./services/web-servers/apache/etc/ssh/magento2docker.pub /root/.ssh/authorized_keys
RUN chmod -R 700 /root/.ssh \
    && echo "Ciphers aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com,chacha20-poly1305@openssh.com,aes128-cbc,3des-cbc,aes192-cbc,aes256-cbc" >> /etc/ssh/sshd_config \
    && touch /root/.ssh/known_hosts \
    && ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null || true

# MINICA CERTIFICATES:
RUN mkdir -p /etc/apache2/ssl
COPY --from=minica_builder /certs/_.127.0.0.1.nip.io/cert.pem /etc/apache2/ssl/cert.pem
COPY --from=minica_builder /certs/_.127.0.0.1.nip.io/key.pem  /etc/apache2/ssl/key.pem
COPY --from=minica_builder /certs/minica.pem                   /etc/apache2/ssl/minica.pem

# APACHE:
COPY ./services/web-servers/multi/etc/apache2/sites-enabled/000-default.conf \
     /etc/apache2/sites-enabled/000-default.conf
RUN a2enmod ssl headers vhost_alias proxy proxy_fcgi proxy_http proxy_wstunnel rewrite setenvif expires deflate \
    && a2ensite default-ssl.conf \
    && chown -R "${_USER}:${_USER}" "${M2D_APACHE_ROOT_DIRECTORY}" \
    && mkdir -p /usr/local/etc /var/log/pwa /var/run/pwa \
    && touch /usr/local/etc/pwa-ports.map \
    && chown magento:magento /usr/local/etc/pwa-ports.map /var/log/pwa /var/run/pwa \
    && chmod 664 /usr/local/etc/pwa-ports.map
RUN chown -R "${_USER}:${_USER}" ${_HOME_DIRECTORY}

# TUNE ENVIRONMENT:
RUN echo "Defaults    timestamp_timeout=-1" >> /etc/sudoers

# FLAG TO NOT CACHE ANYTHING FROM THIS POINT
ARG CACHEBUST=1

# MAGENTO TOOLS:
RUN curl -o /usr/local/bin/n98-magerun2 https://files.magerun.net/n98-magerun2.phar; \
    curl -o /etc/bash_completion.d/n98-magerun2.phar.bash https://raw.githubusercontent.com/netz98/n98-magerun2/master/res/autocompletion/bash/n98-magerun2.phar.bash; \
    curl -o /usr/local/bin/m2-convert-for-composer https://raw.githubusercontent.com/isitnikov/m2-convert-patch-for-composer-install/master/convert-for-composer.php; \
    curl -o /etc/bash_completion.d/magento2-bash-completion https://raw.githubusercontent.com/yvoronoy/magento2-bash-completion/master/magento2-bash-completion-enterprise

# ADOBE TOOLS (as root):
RUN curl -o /usr/local/bin/_m2install.sh https://raw.githubusercontent.com/magento-sparta/m2install/master/m2install.sh; \
    curl -o /etc/bash_completion.d/m2install-bash-completion https://raw.githubusercontent.com/magento-sparta/m2install/master/m2install-bash-completion;

# MYDUMPER:
RUN apt-get install -y lsb-release libatomic1
RUN apt-get -y install libglib2.0-dev zlib1g-dev libpcre3-dev libssl-dev libzstd-dev
RUN apt-get -y install libmariadb-dev-compat libmariadb-dev
RUN pip install -U sphinx
RUN wget -O mydumper.tar.gz https://github.com/mydumper/mydumper/archive/refs/tags/v0.16.1-3.tar.gz && \
    tar xzf mydumper.tar.gz
COPY ./services/db-engines/mydumper/CMakeLists.txt mydumper-0.16.1-3/
RUN cd mydumper-0.16.1-3 && cmake . && make && make install

RUN git ls-remote git@git.corp.adobe.com:magento-support/cloud-tools.git 2>&1 | if grep -q HEAD; then \
    git clone git@git.corp.adobe.com:magento-support/cloud-tools.git /usr/local/src/cloud-tools; else echo; fi \
    && if [ -d /usr/local/src/cloud-tools ]; then \
        ln -s /usr/local/src/cloud-tools/cloud-dump /usr/local/bin/cloud-dump \
        && ln -s /usr/local/src/cloud-tools/cloud-git-url /usr/local/bin/cloud-git-url \
        && ln -s /usr/local/src/cloud-tools/cloud-patchcheck /usr/local/bin/cloud-patchcheck; \
    else echo; fi

RUN git ls-remote git@github.com:magento-sparta/m-it.git 2>&1 | if grep -q HEAD; then \
    git clone git@github.com:magento-sparta/m-it.git /usr/local/src/m-it; else echo; fi \
    && if [ -d /usr/local/src/m-it ]; then /usr/local/src/m-it/mit-installer.sh; else echo; fi

# USER CONTEXT CONFIGURATION:
USER magento

RUN mkdir -p ${_HOME_DIRECTORY}/.ssh \
    && touch ${_HOME_DIRECTORY}/.ssh/known_hosts \
    && ssh-keyscan github.com >> ${_HOME_DIRECTORY}/.ssh/known_hosts 2>/dev/null || true

COPY ./services/web-servers/apache/etc/git/gitconfig       ${_HOME_DIRECTORY}/.gitconfig
COPY ./services/web-servers/apache/etc/composer/auth.json* ${_HOME_DIRECTORY}/.composer/
COPY ./services/web-servers/apache/etc/m2install/.m2install.conf* ${_HOME_DIRECTORY}/

# BASH COMPLETION:
RUN echo "source /etc/bash_completion" >> ${_HOME_DIRECTORY}/.bashrc \
    && echo 'switch-php() { source /usr/local/bin/switch-php "$@"; }' >> ${_HOME_DIRECTORY}/.bashrc \
    && echo 'export PHP_IDE_CONFIG="serverName=host.docker.internal"' >> ${_HOME_DIRECTORY}/.bashrc

# MAGENTO CLI:
#RUN cd ${_HOME_DIRECTORY} && curl -sS https://accounts.magento.cloud/cli/installer | php

# ADOBE TOOLS (as magento):
RUN if [ -d /usr/local/src/m-it ]; then /usr/local/src/m-it/mit-installer.sh; else echo; fi
RUN sed -i.back '/^export BASH_IT_THEME=/ s/^/# /' ${_HOME_DIRECTORY}/.bashrc

USER root
RUN chown -R "${_USER}:${_USER}" ${_HOME_DIRECTORY}/.gitconfig ${_HOME_DIRECTORY}/.composer ${_HOME_DIRECTORY}/.m2install.conf*; \
    chmod +x /usr/local/bin/*

# CRONTAB:
RUN apt-get update && apt-get install -y cron

## END OF BASE IMAGE ##

## BASE IMAGE WITHOUT MAILCATCHER ##
FROM m2d_web_server_multi_base AS m2d_web_server_multi_base_mailcatcher_no

## BASE IMAGE WITH MAILCATCHER ##
FROM m2d_web_server_multi_base AS m2d_web_server_multi_base_mailcatcher_yes
RUN apt-get update && apt-get install -y msmtp
COPY ./services/web-servers/apache/etc/msmtprc /etc/msmtprc
RUN for ver in 8.1 8.2 8.3 8.4 8.5; do \
        cp /services/web-servers/apache/etc/php/mailcatcher.ini \
           /etc/php/${ver}/fpm/conf.d/99-mailcatcher.ini 2>/dev/null || true; \
    done

FROM m2d_web_server_multi_base_mailcatcher_${M2D_ENABLE_MAILCATCHER} AS m2d_web_server_multi_mailcatcher

## BASE IMAGE WITHOUT BLACKFIRE ##
FROM m2d_web_server_multi_mailcatcher AS m2d_web_server_multi_blackfire_no

## BASE IMAGE WITH BLACKFIRE ##
FROM m2d_web_server_multi_mailcatcher AS m2d_web_server_multi_blackfire_yes
RUN version=$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;") \
    && curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s https://blackfire.io/api/v1/releases/probe/php/linux/amd64/$version \
    && mkdir -p /tmp/blackfire \
    && tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
    && mv /tmp/blackfire/blackfire-*.so $(php -r "echo ini_get('extension_dir');")/blackfire.so \
    && printf "extension=blackfire.so\nblackfire.agent_socket=tcp://blackfire:8707\n" \
        > /etc/php/${M2D_WEB_SERVER_PHP_VERSION}/fpm/conf.d/blackfire.ini \
    && rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz \
    && curl -A "Docker" -L https://blackfire.io/api/v1/releases/client/linux_static/amd64 | tar zxp -C /tmp/blackfire \
    && mv /tmp/blackfire/blackfire /usr/bin/blackfire \
    && rm -Rf /tmp/blackfire

## TARGET IMAGE ##
FROM m2d_web_server_multi_blackfire_${M2D_ENABLE_BLACKFIRE} AS web_server

# CODESNIFFER:
#RUN mkdir -p /usr/local/magento-ecg-code-sniffer \
#    && cd /usr/local/magento-ecg-code-sniffer \
#    && composer require --ignore-platform-reqs squizlabs/php_codesniffer magento-ecg/coding-standard \
#    && ln -sf /usr/local/magento-ecg-code-sniffer/vendor/bin/phpcs /usr/local/bin/phpcs \
#    && phpcs --config-set installed_paths /usr/local/magento-ecg-code-sniffer/vendor/magento-ecg/coding-standard

COPY ./services/web-servers/multi/bin/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

## RUN AS _USER ##
USER ${_USER}
WORKDIR ${_HOME_DIRECTORY}

USER root
CMD ["/usr/local/bin/start.sh"]
