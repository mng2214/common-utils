#!/usr/bin/env bash
set -e

### ===== НАСТРОЙКИ ПОД СЕБЯ =====
WG_IF="wg0"
WG_PORT=51820

# Виртуальная подсеть WireGuard
WG_NETWORK="10.8.0.0/24"
WG_SERVER_IP="10.8.0.1/24"
WG_CLIENT_IP="10.8.0.2/24"

# Файл клиента, который ты заберёшь на ПК
CLIENT_CONF="/etc/wireguard/client.conf"

# Placeholder для Endpoint — потом поменяешь на public IP или DDNS
ENDPOINT_PLACEHOLDER="<YOUR_PUBLIC_IP_OR_DDNS>"
### ==============================

if [ "$EUID" -ne 0 ]; then
  echo "Запусти скрипт так: sudo $0"
  exit 1
fi

echo ">>> Устанавливаю WireGuard..."
apt-get update -y
apt-get install -y wireguard

echo ">>> Создаю /etc/wireguard, если нет..."
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

cd /etc/wireguard

### ===== КЛЮЧИ СЕРВЕРА =====
if [ ! -f server_private.key ] || [ ! -f server_public.key ]; then
  echo ">>> Генерирую ключи сервера..."
  umask 077
  wg genkey | tee server_private.key | wg pubkey > server_public.key
else
  echo ">>> Ключи сервера уже существуют, не трогаю."
fi

SERVER_PRIVATE_KEY=$(cat server_private.key)
SERVER_PUBLIC_KEY=$(cat server_public.key)

### ===== КЛЮЧИ КЛИЕНТА =====
if [ ! -f client_private.key ] || [ ! -f client_public.key ]; then
  echo ">>> Генерирую ключи клиента..."
  umask 077
  wg genkey | tee client_private.key | wg pubkey > client_public.key
else
  echo ">>> Ключи клиента уже существуют, не трогаю."
fi

CLIENT_PRIVATE_KEY=$(cat client_private.key)
CLIENT_PUBLIC_KEY=$(cat client_public.key)

### ===== РЕЗЕРВ wg0.conf, ЕСЛИ ЕСТЬ =====
WG_CONF="/etc/wireguard/${WG_IF}.conf"
if [ -f "$WG_CONF" ]; then
  echo ">>> Найден старый ${WG_CONF}, делаю бэкап..."
  cp "$WG_CONF" "${WG_CONF}.bak.$(date +%F-%H%M%S)"
fi

echo ">>> Пишу новый ${WG_CONF}..."

cat > "$WG_CONF" <<EOF
[Interface]
Address = ${WG_SERVER_IP}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
SaveConfig = false

[Peer]
# Клиент (ПК)
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${WG_CLIENT_IP}
EOF

chmod 600 "$WG_CONF"

### ===== ОТКРЫВАЕМ ПОРТ ДЛЯ WIREGUARD =====
echo ">>> Настраиваю UFW для WireGuard (51820/udp)..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow ${WG_PORT}/udp || true
else
  echo "UFW не установлен, пропускаю. (ты ставил его в первом скрипте)"
fi

### ===== ВКЛЮЧАЕМ ИНТЕРФЕЙС WG0 =====
echo ">>> Включаю wg-quick@${WG_IF}..."
systemctl enable --now wg-quick@${WG_IF}

echo ">>> Текущий статус WireGuard:"
wg show || true

### ===== СОЗДАЁМ client.conf ДЛЯ ПК =====
echo ">>> Создаю ${CLIENT_CONF} (конфиг для твоего ПК)..."

cat > "$CLIENT_CONF" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${WG_CLIENT_IP}
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${ENDPOINT_PLACEHOLDER}:${WG_PORT}
AllowedIPs = ${WG_NETWORK}
PersistentKeepalive = 25
EOF

chmod 600 "$CLIENT_CONF"

echo
echo "=============================================="
echo "  WireGuard сервер настроен ✅"
echo
echo "  Интерфейс:    ${WG_IF}"
echo "  Сервер IP:    ${WG_SERVER_IP}"
echo "  Клиент IP:    ${WG_CLIENT_IP}"
echo "  Порт:         ${WG_PORT}/udp"
echo
echo "  Конфиг клиента (забрать на ПК):"
echo "    ${CLIENT_CONF}"
echo
echo "  Дальше:"
echo "  1) Отредактируй Endpoint в client.conf:"
echo "       Endpoint = ${ENDPOINT_PLACEHOLDER}:${WG_PORT}"
echo "     → поставь туда свой public IP (например, 67.x.x.x) или DDNS,"
echo "       или локальный IP типа 10.0.0.205 для домашней сети."
echo
echo "  2) Скопируй client.conf на ПК:"
echo "       scp pi5@<IP_RPI>:${CLIENT_CONF} ."
echo
echo "  3) Импортируй client.conf в WireGuard на ПК и нажми Activate."
echo
echo "  4) Подключайся по SSH через VPN:"
echo "       ssh pi5@10.8.0.1"
echo "=============================================="
