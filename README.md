# remnanodedeploy
# Автоматический деплой нод Remnawave

Скрипт для быстрой неинтерактивной настройки серверов-нод. Автоматически выполняет тюнинг сетевого стека, ставит Docker, привязывает IP к Cloudflare DNS (Round Robin), настраивает Nginx-маскировку по `proxy_protocol` через Let's Encrypt и закрывает порты через UFW.

## Быстрый запуск (One-liner)

Подключитесь к чистой VPS по SSH (от root) и запустите команду, подставив свои значения:

```bash
curl -sSL [https://raw.githubusercontent.com/proxyboy228/remnanodedeploy/main/deploy_node.sh](https://raw.githubusercontent.com/ТВОЙ_GITHUB_ЮЗЕРНЕЙМ/ИМЯ_ТВОЕГО_РЕПОЗИТОРИЯ/main/deploy_node.sh) -o deploy.sh && chmod +x deploy.sh && ./deploy.sh \
"us.domain.com" \
"admin@domain.com" \
"СЕКРЕТНЫЙ_КЛЮЧ_НОДЫ" \
"443 8443 2083" \
"ТВОЙ_CLOUDFLARE_API_TOKEN" \
"ТВОЙ_CLOUDFLARE_ZONE_ID" \
"ip ноды"
```

Порядковый номер,Аргумент,Описание,Пример
1,DOMAIN,"Поддомен, который вы выделяете под локацию (добавляется в DNS автоматически)","""us.domain.com"""
2,EMAIL,Ваш email для регистрации SSL-сертификата Let's Encrypt,"""admin@domain.com"""
3,SECRET_KEY,Секретный ключ ноды для связи с управляющей панелью Remnawave,"""MyMegaSecret123"""
4,PORTS,Список входящих портов для клиентов. Писать через пробел строго в кавычках,"""443 8443 2083"""
5,CF_TOKEN,API Токен Cloudflare с правами Zone.DNS:Edit и Zone.Zone:Read,"""a1b2c3d4..."""
6,CF_ZONE_ID,Идентификатор зоны вашего домена в Cloudflare (находится на вкладке Overview),"""9f8e7d6c..."""
7,PANEL_IP,Публичный IP-адрес вашей панели. Порт 2222 откроется только для него,"""127.0.0.1"""

Что скрипт делает автоматически:
Запрашивает внешний IP текущей VPS и добавляет А-запись в Cloudflare (без проксирования).

Выполняет системный тюнинг (sysctl, limits, включает BBR и оптимизирует nf_conntrack).

Разворачивает последнюю стабильную версию Docker.

Выпускает SSL-сертификат от Let's Encrypt через DNS-01 challenge.

Настраивает Nginx на работу по proxy_protocol для безопасного SelfSteal (Reality).

Поднимает контейнер remnanode в режиме host.

Защищает сервер через UFW (порт управления 2222 доступен только для PANEL_IP).
