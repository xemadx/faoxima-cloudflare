#!/usr/bin/env bash
set -euo pipefail

export FAOXIMA_CLOUDFLARE=1
export DB_PORT=${DB_PORT:-3306}
export DB_TLS=${DB_TLS:-1}
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export LC_ALL=C

fail() { printf '%s\n' "$1" >&2; exit 1; }

[[ ${PUBLIC_URL:-} =~ ^https://([a-zA-Z0-9.-]+)/([a-zA-Z0-9_-]+)$ ]] || fail 'Invalid PUBLIC_URL'
export FAOXIMA_DOMAIN=${BASH_REMATCH[1]} FAOXIMA_URL_PATH=${BASH_REMATCH[2]}
[[ ${DB_HOST:-} =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ && $DB_PORT =~ ^[1-9][0-9]{0,4}$ && $DB_PORT -le 65535 ]] || fail 'Invalid database address'
[[ ${DB_USER:-} =~ ^[a-zA-Z0-9_-]+$ && ${DB_NAME:-} =~ ^[a-zA-Z0-9_-]+$ && ${FILES_DB_NAME:-} =~ ^[a-zA-Z0-9_-]+$ ]] || fail 'Invalid database or user name'
[[ $DB_NAME != "$FILES_DB_NAME" && -n ${DB_PASS:-} ]] || fail 'Configure separate application and filesystem schemas'
[[ ${TELEGRAM_BOT_TOKEN:-} =~ ^[0-9]+:[a-zA-Z0-9_-]{20,}$ && ${TELEGRAM_ADMIN_ID:-} =~ ^[0-9]+$ && ${TELEGRAM_BOT_USERNAME:-} =~ ^[a-zA-Z0-9_]+$ ]] || fail 'Invalid Telegram settings'

tls_query=''
case "$DB_TLS" in
    1) tls_query='?tls=true' ;;
    0) ;;
    *) fail 'DB_TLS must be 1 or 0' ;;
esac
if [[ -n ${DB_CA_PEM:-} ]]; then
    SSL_CERT_FILE=/etc/ssl/faoxima-ca.pem
    cat /etc/ssl/certs/ca-certificates.crt > "$SSL_CERT_FILE"
    printf '\n%s\n' "$DB_CA_PEM" >> "$SSL_CERT_FILE"
    chmod 644 "$SSL_CERT_FILE"
    unset DB_CA_PEM
fi

volume=/mnt/faoxima
app="$volume/app"
meta_url="mysql://${DB_USER}:@(${DB_HOST}:${DB_PORT})/${FILES_DB_NAME}${tls_query}"

if ! META_PASSWORD="$DB_PASS" juicefs status "$meta_url" >/dev/null 2>&1; then
    META_PASSWORD="$DB_PASS" ACCESS_KEY="$DB_USER" SECRET_KEY="$DB_PASS" \
        juicefs format --storage mysql --bucket "(${DB_HOST}:${DB_PORT})/${FILES_DB_NAME}${tls_query}" "$meta_url" faoxima-files
fi

META_PASSWORD="$DB_PASS" juicefs mount --no-syslog --backup-meta 0 --cache-size 256 \
    "$meta_url" "$volume" &
mount_pid=$!
fpm_pid=''
nginx_pid=''
cleanup() {
    trap - EXIT TERM INT
    [[ -z $nginx_pid ]] || kill -QUIT "$nginx_pid" 2>/dev/null || true
    [[ -z $fpm_pid ]] || kill -QUIT "$fpm_pid" 2>/dev/null || true
    [[ -z $nginx_pid ]] || wait "$nginx_pid" || true
    [[ -z $fpm_pid ]] || wait "$fpm_pid" || true
    fusermount3 -u "$volume" 2>/dev/null || true
    kill "$mount_pid" 2>/dev/null || true
    wait "$mount_pid" || true
}
trap cleanup EXIT
trap 'exit 0' TERM INT

for ((attempt=0; attempt<45; attempt++)); do
    mountpoint -q "$volume" && break
    kill -0 "$mount_pid" 2>/dev/null || fail 'Persistent filesystem mount failed'
    sleep 1
done
mountpoint -q "$volume" || fail 'Timed out mounting the persistent filesystem'

(
    flock -x 9
    release=$(sha256sum /opt/cloudflare/release.sha256 | cut -d ' ' -f 1)
    migration=$(printf '%s\n' "$release" "$DB_HOST" "$DB_PORT" "$DB_NAME" "$TELEGRAM_ADMIN_ID" | sha256sum | cut -d ' ' -f 1)
    install -d -o www-data -g www-data -m 775 "$app" "$app/storage" "$app/logs" "$app/cronbot/.runtime"
    install -d -o www-data -g www-data -m 700 "$app/storage/private" "$volume/sessions"
    if [[ $(cat "$volume/.release" 2>/dev/null || true) != "$release" ]]; then
        for file in text.json default_help.json optimization_config.php; do
            if [[ ! -e $app/$file ]]; then
                install -o www-data -g www-data -m 664 "/opt/faoxima/$file" "$app/$file"
            fi
        done
        rsync -rt --ignore-times --chown=www-data:www-data --chmod=D775,F664 \
            --exclude=/text.json --exclude=/default_help.json --exclude=/optimization_config.php \
            /opt/faoxima/ "$app/"
        if [[ -f $volume/.release.files ]]; then
            comm -23 "$volume/.release.files" /opt/cloudflare/release.files | while IFS= read -r removed; do
                rm -f -- "$app/$removed"
            done
        fi
        cp /opt/cloudflare/release.files "$volume/.release.files.new"
        mv -f "$volume/.release.files.new" "$volume/.release.files"
        printf '%s\n' "$release" > "$volume/.release.new"
        mv -f "$volume/.release.new" "$volume/.release"
    fi
    if [[ $(cat "$volume/.migration" 2>/dev/null || true) != "$migration" ]]; then
        runuser -u www-data -- php /opt/cloudflare/setup.php
        printf '%s\n' "$migration" > "$volume/.migration.new"
        mv -f "$volume/.migration.new" "$volume/.migration"
    fi
) 9>"$volume/.bootstrap.lock"

ln -sfn "$app" /var/www/faoxima
ln -sfn "$app" "/var/www/site/$FAOXIMA_URL_PATH"
printf 'session.save_path = "%s"\n' "$volume/sessions" > /etc/php/8.3/fpm/conf.d/99-faoxima-state.ini
envsubst '${FAOXIMA_DOMAIN} ${FAOXIMA_URL_PATH}' < /opt/cloudflare/nginx.conf.template > /etc/nginx/nginx.conf
cat > /etc/nginx/faoxima-php.conf <<EOF
include fastcgi_params;
fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
fastcgi_param HTTPS on;
fastcgi_param HTTP_HOST $FAOXIMA_DOMAIN;
fastcgi_param HTTP_X_FORWARDED_HOST $FAOXIMA_DOMAIN;
fastcgi_param HTTP_X_FORWARDED_PROTO https;
fastcgi_pass 127.0.0.1:9000;
fastcgi_read_timeout 300s;
EOF

php-fpm8.3 -F &
fpm_pid=$!
nginx -g 'daemon off;' &
nginx_pid=$!
wait -n "$mount_pid" "$fpm_pid" "$nginx_pid"
