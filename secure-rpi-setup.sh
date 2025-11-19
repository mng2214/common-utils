#!/usr/bin/env bash
set -e

### ===== НАСТРОЙКИ ПОД СЕБЯ =====
MAIN_USER="pi5"      # твой пользователь, под которым будешь логиниться по SSH
SSH_PORT=22          # можешь сменить порт SSH, если хочешь
### ==============================

if [ "$EUID" -ne 0 ]; then
  echo "Запусти скрипт так: sudo $0"
  exit 1
fi

echo ">>> Обновляю систему..."
apt-get update -y
apt-get upgrade -y

echo ">>> Проверяю пользователя $MAIN_USER..."
if ! id "$MAIN_USER" &>/dev/null; then
  echo "Пользователь $MAIN_USER не найден. Создаю..."
  adduser --disabled-password --gecos "" "$MAIN_USER"
  usermod -aG sudo "$MAIN_USER"
else
  echo "Пользователь $MAIN_USER уже существует."
fi

HOME_DIR=$(getent passwd "$MAIN_USER" | cut -d: -f6)

echo ">>> Проверяю ~/.ssh для $MAIN_USER..."
mkdir -p "$HOME_DIR/.ssh"
chmod 700 "$HOME_DIR/.ssh"
chown -R "$MAIN_USER:$MAIN_USER" "$HOME_DIR/.ssh"

if [ ! -s "$HOME_DIR/.ssh/authorized_keys" ]; then
  echo "ВНИМАНИЕ: $HOME_DIR/.ssh/authorized_keys пустой или отсутствует."
  echo "Сначала скопируй публичный ключ с ноутбука командой:"
  echo "  ssh-copy-id -i ~/.ssh/id_ed25519.pub ${MAIN_USER}@<IP_RPI>"
  echo "И запусти скрипт ещё раз."
  exit 1
fi

echo ">>> Включаю и настраиваю SSH..."
systemctl enable ssh
systemctl start ssh

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.bak.$(date +%F-%H%M%S)"
cp "$SSHD_CONFIG" "$BACKUP_FILE"

echo ">>> Хардненг SSH (только ключи, без пароля, без root)..."
# Порт
if grep -q "^Port " "$SSHD_CONFIG"; then
  sed -i "s/^Port .*/Port $SSH_PORT/" "$SSHD_CONFIG"
else
  echo "Port $SSH_PORT" >> "$SSHD_CONFIG"
fi

# Запрет root и паролей
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG" || true
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG" || true
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG" || true

grep -q "^PasswordAuthentication" "$SSHD_CONFIG" || echo "PasswordAuthentication no" >> "$SSHD_CONFIG"
grep -q "^PermitRootLogin" "$SSHD_CONFIG" || echo "PermitRootLogin no" >> "$SSHD_CONFIG"
grep -q "^PubkeyAuthentication" "$SSHD_CONFIG" || echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"

echo ">>> Перезапускаю SSH..."
systemctl restart ssh

echo ">>> Блокирую пароль root (root L)..."
passwd -l root || true

echo ">>> Ставлю UFW, Fail2ban, unattended-upgrades..."
apt-get install -y ufw fail2ban unattended-upgrades

echo ">>> Настраиваю UFW (firewall)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp"
ufw --force enable

echo ">>> Включаю Fail2ban..."
systemctl enable --now fail2ban

echo ">>> Включаю автообновления безопасности..."
cat >/etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo ">>> Отключаю ненужные сервисы (bluetooth, avahi, cups, vnc, rpcbind)..."
systemctl disable --now bluetooth.service 2>/dev/null || true
systemctl disable --now hciuart.service 2>/dev/null || true
systemctl disable --now avahi-daemon.service 2>/dev/null || true
systemctl disable --now cups 2>/dev/null || true
systemctl disable --now wayvnc 2>/dev/null || true

# rpcbind – самое важное
systemctl stop rpcbind.service 2>/dev/null || true
systemctl stop rpcbind.socket 2>/dev/null || true
systemctl disable rpcbind.service 2>/dev/null || true
systemctl disable rpcbind.socket 2>/dev/null || true
systemctl mask rpcbind.service 2>/dev/null || true
systemctl mask rpcbind.socket 2>/dev/null || true
apt-get purge -y rpcbind 2>/dev/null || true

echo ">>> Устанавливаю Docker Engine и docker compose plugin (официальный репозиторий)..."

if ! command -v docker &>/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  . /etc/os-release
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    ${VERSION_CODENAME} stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo "Docker уже установлен, пропускаю установку."
fi

echo ">>> Включаю Docker в автозапуск..."
systemctl enable --now docker

echo ">>> Добавляю $MAIN_USER в группу docker..."
usermod -aG docker "$MAIN_USER"

echo ">>> Текущие открытые порты:"
ss -tulpn | grep LISTEN || echo "Нет слушающих TCP-портов (кроме, возможно, ssh)"

echo
echo "=============================================="
echo "  БАЗОВАЯ БЕЗОПАСНОСТЬ + DOCKER НАСТРОЕНЫ ✅"
echo
echo "  Пользователь SSH:  $MAIN_USER"
echo "  Порт SSH:          $SSH_PORT"
echo
echo "  Теперь логин с твоего ноута:"
echo "    ssh -p $SSH_PORT ${MAIN_USER}@<IP_RPI>"
echo
echo "  Напоминание:"
echo "  - Docker установлен: docker, docker compose (docker compose ...)"
echo "  - Не открывай лишние порты в docker-compose (используй expose вместо ports, если можно)"
echo "=============================================="
