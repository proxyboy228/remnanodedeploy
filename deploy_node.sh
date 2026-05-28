#!/usr/bin/env bash
set -Eeuo pipefail

# ==================================================================================
# Мастер-скрипт автоматического развертывания ноды Remnawave + Reality + DNS
# Поддержка: Ubuntu / Debian (Автоопределение ОС)
# ==================================================================================

if [[ "${EUID}" -ne 0 ]]; then
  echo "❌ Запусти скрипт от root (sudo !!)"
  exit 1
fi

# ⚠️ НАСТРОЙ ПЕРЕД ЗАГРУЗКОЙ НА GITHUB ⚠️
GITHUB_USER="proxyboy228"
GITHUB_REPO="remnanodedeploy"

if [ "$#" -lt 7 ]; then
    echo "❌ Ошибка! Переданы не все аргументы (должно быть 7)."
    echo "Порядок: <DOMAIN> <EMAIL> <SECRET_KEY> <PORTS> <CF_TOKEN> <CF_ZONE_ID> <PANEL_IP>"
    exit 1
fi

DOMAIN_NAME="$1"
EMAIL="$2"
NODE_SECRET="$3"
ADDITIONAL_PORTS="$4" 
CF_TOKEN="$5"
CF_ZONE_ID="$6"
PANEL_IP="$7"

# --- Автоопределение операционной системы ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_TYPE=$ID # Получим 'ubuntu' или 'debian'
else
    echo "❌ Не удалось определить тип операционной системы." && exit 1
fi

if [[ "$OS_TYPE" != "ubuntu" && "$OS_TYPE" != "debian" ]]; then
    echo "❌ Скрипт поддерживает только Ubuntu и Debian. Найдено: $OS_TYPE" && exit 1
fi

echo "🚀 Старт автоматизации для ноды: $DOMAIN_NAME (ОС: $OS_TYPE)"

# --- Этап 0: Определение IPv4 и добавление записи в Cloudflare ---
PUBLIC_IP=$(curl -4 -s https://icanhazip.com || curl -4 -s https://ifconfig.me)
if [ -z "$PUBLIC_IP" ]; then
    echo "❌ Не удалось определить публичный IPv4 сервера." && exit 1
fi
echo "🌐 Публичный IPv4 сервера: $PUBLIC_IP. Добавляем в Cloudflare DNS..."

CF_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
     -H "Authorization: Bearer $CF_TOKEN" \
     -H "Content-Type: application/json" \
     --data "{\"type\":\"A\",\"name\":\"$DOMAIN_NAME\",\"content\":\"$PUBLIC_IP\",\"ttl\":auto,\"proxied\":false}")

if echo "$CF_RESPONSE" | grep -q '"success":true'; then
    echo "✅ DNS запись добавлена (Round Robin)."
else
    echo "❌ Ошибка Cloudflare API: $CF_RESPONSE" && exit 1
fi

# --- Этап 1: Оптимизация системы (apply-xray-tune.sh) ---
echo "⚙️  Запуск тюнинга сетевого стека..."
curl -sSL "https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/apply-xray-tune.sh" -o tune.sh
chmod +x tune.sh && ./tune.sh && rm -f tune.sh

# --- Этап 2: Установка Docker под ключ (Динамический репозиторий) ---
echo "🐳 Установка Docker для системы $OS_TYPE..."
apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release

mkdir -p /etc/apt/keyrings
# Качаем GPG-ключ строго под нужную ОС (ubuntu или debian)
curl -fsSL "https://download.docker.com/linux/$OS_TYPE/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes

# Добавляем репозиторий строго под нужную ОС
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_TYPE $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
echo "✅ Docker успешно установлен."

# --- Этап 3: Сайт-заглушка и SSL-сертификаты ---
echo "🔒 Настройка маскировки Nginx и генерация SSL..."
curl -sSL "https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/StealSNI_auto.sh" -o sni.sh
chmod +x sni.sh && ./sni.sh "$DOMAIN_NAME" "$EMAIL" "$CF_TOKEN" && rm -f sni.sh

# --- Этап 4: Развертывание контейнера Remnanode ---
echo "📦 Настройка Remnawave Node..."
NODE_DIR="/opt/remnanode"
mkdir -p "$NODE_DIR"

cat > "$NODE_DIR/docker-compose.yml" <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=2222
      - SECRET_KEY=${NODE_SECRET}
EOF

cd "$NODE_DIR" && docker compose up -d
echo "✅ Контейнер remnanode запущен."

# --- Этап 5: Файрвол UFW ---
echo "🛡️ Настройка файрвола UFW..."
ufw allow from "$PANEL_IP" to any port 2222 comment 'Remnawave Panel Management'

for port in $ADDITIONAL_PORTS; do
    echo "Открываем клиентский порт: $port"
    ufw allow "$port"/tcp
    ufw allow "$port"/udp
done
ufw reload

echo "========================================================================"
echo "🎉 Установка завершена! Сервер полностью готов к работе."
echo "========================================================================"
