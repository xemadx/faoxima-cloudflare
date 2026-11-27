ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG TARGETARCH
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl fuse3 gettext-base mariadb-client nginx rsync tini \
        php8.3-bcmath php8.3-cli php8.3-curl php8.3-fpm php8.3-gd php8.3-intl \
        php8.3-mbstring php8.3-mysql php8.3-redis php8.3-soap php8.3-xml php8.3-zip \
    && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) checksum=79648a0a67145bf42ca4e8336578c13a5bbc9a0bd34df340b3b93dac1e975247 ;; \
      arm64) checksum=19f72a30d3642a2f7971c8c4a31d2647de62f19520716e85c3a777de5f4c9036 ;; \
      *) exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 "https://github.com/juicedata/juicefs/releases/download/v1.4.2/juicefs-1.4.2-linux-${TARGETARCH}.tar.gz" -o /tmp/juicefs.tar.gz; \
    echo "$checksum  /tmp/juicefs.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/juicefs.tar.gz -C /usr/local/bin juicefs; \
    rm /tmp/juicefs.tar.gz

COPY --chmod=755 cloudflare/entrypoint.sh /usr/local/bin/faoxima-start
COPY cloudflare/nginx.conf.template cloudflare/setup.php /opt/cloudflare/
COPY docker/php/conf.d/faoxima.ini /etc/php/8.3/mods-available/faoxima.ini
COPY . /opt/faoxima/

RUN set -eu; \
    cd /opt/faoxima; \
    mv installer/includes /opt/cloudflare/installer; \
    rm -rf installer cloudflare docker; \
    test -f vendor/autoload.php; \
    find . -type f -exec sha256sum '{}' + | LC_ALL=C sort -k2 > /opt/cloudflare/release.sha256; \
    cut -c67- /opt/cloudflare/release.sha256 | LC_ALL=C sort > /opt/cloudflare/release.files; \
    mkdir -p /mnt/faoxima /var/www/site /run/php; \
    phpenmod -v 8.3 faoxima; \
    printf '[global]\nerror_log = /proc/self/fd/2\n[www]\nlisten = 127.0.0.1:9000\nclear_env = no\ncatch_workers_output = yes\npm.max_children = 12\nping.path = /health\n' > /etc/php/8.3/fpm/pool.d/zz-faoxima.conf

WORKDIR /var/www
EXPOSE 8080 8081
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/faoxima-start"]
