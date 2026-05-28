# remnanodedeploy
# Автоматический деплой нод Remnawave

Скрипт для быстрой неинтерактивной настройки серверов-нод. Автоматически выполняет тюнинг сетевого стека, ставит Docker, привязывает IP к Cloudflare DNS (Round Robin), настраивает Nginx-маскировку по `proxy_protocol` через Let's Encrypt и закрывает порты через UFW.

## Быстрый запуск (One-liner)

Подключитесь к чистой VPS по SSH (от root) и запустите команду, подставив свои значения:

```bash
curl -sSL [https://raw.githubusercontent.com/ТВОЙ_GITHUB_ЮЗЕРНЕЙМ/ИМЯ_ТВОЕГО_РЕПОЗИТОРИЯ/main/deploy_node.sh](https://raw.githubusercontent.com/ТВОЙ_GITHUB_ЮЗЕРНЕЙМ/ИМЯ_ТВОЕГО_РЕПОЗИТОРИЯ/main/deploy_node.sh) -o deploy.sh && chmod +x deploy.sh && ./deploy.sh \
"us.domain.com" \
"admin@domain.com" \
"СЕКРЕТНЫЙ_КЛЮЧ_НОДЫ" \
"443 8443 2083" \
"ТВОЙ_CLOUDFLARE_API_TOKEN" \
"ТВОЙ_CLOUDFLARE_ZONE_ID" \
"ip ноды"
