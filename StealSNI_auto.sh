#!/bin/bash

# ==================================================================================
# Скрипт для автоматической установки и настройки сайта-заглушки (SNI)
# для работы с Reality. Автоматическая версия (без интерактивных запросов).
# ==================================================================================

# Проверяем, запущен ли скрипт от имени root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Этот скрипт нужно запускать с правами root. Попробуйте: sudo $0" >&2
    exit 1
fi

# --- Прием аргументов командной строки ---
DOMAIN_NAME="$1"
LETSENCRYPT_EMAIL="$2"
CF_API_TOKEN="$3"

if [ -z "$DOMAIN_NAME" ] || [ -z "$LETSENCRYPT_EMAIL" ]; then
    echo "❌ Ошибка: Домен и email не могут быть пустыми!" >&2
    echo "Использование: $0 <DOMAIN> <EMAIL> [CF_API_TOKEN]" >&2
    exit 1
fi

# --- Определение ОС ---
echo "--- Определение операционной системы ---"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
    echo "✅ Обнаружена ОС: $PRETTY_NAME"
else
    echo "❌ Не удалось определить операционную систему."
    exit 1
fi

if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    echo "❌ Скрипт поддерживает только Ubuntu и Debian."
    exit 1
fi

echo ""
echo "✅ Скрипт будет выполнен для домена: $DOMAIN_NAME"
echo "✅ ОС: $OS $OS_VERSION"
sleep 1

# --- Установка UFW ---
echo ""
echo "--- Этап 1: Установка и настройка UFW ---"
if ! command -v ufw &> /dev/null; then
    echo "UFW не установлен. Устанавливаем..."
    apt update || { echo "❌ Ошибка при обновлении пакетов"; exit 1; }
    apt install -y ufw || { echo "❌ Ошибка при установке UFW"; exit 1; }
    echo "✅ UFW установлен."
else
    echo "✅ UFW уже установлен."
fi

echo "Настройка правил UFW..."
ufw --force enable || { echo "❌ Ошибка при включении UFW"; exit 1; }
ufw default deny incoming || { echo "❌ Ошибка при установке правил по умолчанию"; exit 1; }
ufw default allow outgoing || { echo "❌ Ошибка при установке правил по умолчанию"; exit 1; }
ufw allow 22/tcp comment 'SSH' || { echo "❌ Ошибка при открытии порта SSH"; exit 1; }
ufw allow 80/tcp comment 'HTTP' || { echo "❌ Ошибка при открытии порта HTTP"; exit 1; }
ufw allow 443/tcp comment 'HTTPS' || { echo "❌ Ошибка при открытии порта HTTPS"; exit 1; }
echo "✅ UFW настроен. Открыты порты: 22, 80, 443"

# --- Установка dependencies ---
echo ""
echo "--- Этап 2: Установка зависимостей ---"
apt update || { echo "❌ Ошибка при обновлении списка пакетов"; exit 1; }
apt install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring wget || { echo "❌ Ошибка при установке зависимостей"; exit 1; }

# --- Добавление репозитория Nginx ---
echo ""
echo "--- Этап 3: Добавление официального репозитория Nginx stable ---"
install -d -m 0700 /root/.gnupg
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg || { echo "❌ Ошибка при загрузке GPG ключа"; exit 1; }

gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg | grep -q "573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62" || { echo "❌ Ошибка: неверный GPG ключ"; exit 1; }

if [ "$OS" = "ubuntu" ]; then
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
elif [ "$OS" = "debian" ]; then
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
fi

cat > /etc/apt/preferences.d/99nginx <<EOF
Package: *
Pin: origin nginx.org
Pin: release o=nginx
Pin-Priority: 900
EOF

# --- Установка Nginx и Certbot ---
echo ""
echo "--- Этап 4: Установка Nginx и Certbot ---"
apt update || { echo "❌ Ошибка при обновлении списка пакетов"; exit 1; }
apt install -y nginx certbot python3-certbot-nginx python3-certbot-dns-cloudflare || { echo "❌ Ошибка при установке Nginx и Certbot"; exit 1; }

NGINX_VERSION=$(nginx -v 2>&1 | grep -oP '\d+\.\d+\.\d+')
echo "✅ Установлен Nginx версии: $NGINX_VERSION"

# --- Настройка сайтов-заглушек ---
echo ""
echo "--- Этап 5: Настройка Nginx и загрузка сайта ---"
rm -f /etc/nginx/conf.d/default.conf

SITE_DIR="/var/www/html/site"
mkdir -p "$SITE_DIR/assets"

echo "Загружаем файлы для сайта-заглушки..."
wget -q https://raw.githubusercontent.com/proxyboy228/SNI-Templates/refs/heads/main/converter/apple-touch-icon.png -P "$SITE_DIR"
wget -q https://raw.githubusercontent.com/proxyboy228/SNI-Templates/refs/heads/main/converter/favicon-96x96.png -P "$SITE_DIR"
wget -q https://raw.githubusercontent.com/proxyboy228/SNI-Templates/refs/heads/main/converter/favicon.ico -P "$SITE_DIR"
wget -q https://raw.githubusercontent.com/proxyboy228/SNI-Templates/refs/heads/main/converter/favicon.svg -P "$SITE_DIR"
wget -q https://raw.githubusercontent.com/proxyboy228/SNI-Templates/refs/heads/main/converter/index.html -P "$SITE_DIR"
wget -q https://raw.githubusercontent.com/proxyboy228/SNI-Templates/refs/heads/main/converter/site.webmanifest -P "$SITE_DIR"
wget -q https://raw.githubusercontent.com/proxyboy228/SNI-Templates/refs/heads/main/converter/web-app-manifest-192x192.png -P "$SITE_DIR"
wget -q https://raw.githubusercontent.com/proxyboy228/SNI-Templates/refs/heads/main/converter/web-app-manifest-512x512.png -P "$SITE_DIR"
wget -q https://raw.githubusercontent.com/proxyboy228/SNI-Templates/refs/heads/main/converter/assets/script.js -P "$SITE_DIR/assets"
wget -q https://raw.githubusercontent.com/proxyboy228/SNI-Templates/refs/heads/main/converter/assets/style.css -P "$SITE_DIR/assets"

# --- Временный конфиг для Certbot ---
echo ""
echo "--- Этап 6: Создание временной конфигурации Nginx ---"
cat > /etc/nginx/conf.d/sni.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    if (\$host = ${DOMAIN_NAME}) {
        return 301 https://\$host\$request_uri;
    }
    return 404;
}
EOF

nginx -t || { echo "❌ Ошибка в конфигурации Nginx"; exit 1; }
systemctl restart nginx || { echo "❌ Ошибка при перезапуске Nginx"; exit 1; }

# --- Получение SSL ---
echo ""
echo "--- Этап 7: Получение SSL-сертификата Let's Encrypt ---"
if [ -n "$CF_API_TOKEN" ]; then
    echo "🔑 Автоматический режим: Используем Cloudflare API Token..."
    mkdir -p /root/.secrets/certbot
    CF_CREDS_FILE="/root/.secrets/certbot/cloudflare.ini"
    printf "dns_cloudflare_api_token = %s\n" "$CF_API_TOKEN" > "$CF_CREDS_FILE"
    chmod 600 "$CF_CREDS_FILE"
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$CF_CREDS_FILE" \
        --dns-cloudflare-propagation-seconds 30 \
        -d "$DOMAIN_NAME" \
        --non-interactive --agree-tos --email "$LETSENCRYPT_EMAIL" || { echo "❌ Ошибка при получении SSL"; exit 1; }
    rm -f "$CF_CREDS_FILE"
else
    echo "⚠️ Ручной режим: Токен CF не передан. Требуется ручной ввод!"
    certbot certonly --manual --preferred-challenges dns -d "$DOMAIN_NAME" --agree-tos --email "$LETSENCRYPT_EMAIL" || exit 1
fi

# --- Финальный конфиг с Proxy Protocol ---
echo ""
echo "--- Этап 8: Создание финальной конфигурации Nginx ---"
cat > /etc/nginx/conf.d/sni.conf <<EOF
server {
    listen 127.0.0.1:8443 ssl proxy_protocol;
    http2 on;
    server_name ${DOMAIN_NAME};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
    
    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;
    set_real_ip_from ::1;

    root ${SITE_DIR};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

nginx -t && systemctl restart nginx
echo "✅ [StealSNI] Успешно завершено!"