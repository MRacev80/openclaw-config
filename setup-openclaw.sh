#!/bin/bash

################################################################################
# OpenClaw VPS Automatic Setup Script v4.0
# Автоматическая настройка безопасности VPS + установка OpenClaw
#
# Использование:
#   bash setup-openclaw.sh
#
# Требования:
#   - Ubuntu 22.04+ LTS
#   - Запускать от root
#   - SSH ключ уже установлен в /root/.ssh/authorized_keys
#
# Changelog v4:
#   - npm вместо pnpm (pnpm не подтягивает зависимости плагинов: grammy и др.)
#   - Автоматическая установка OpenClaw через npm
#   - UFW ставится автоматически
#   - SSH ключ: фикс кодировки (\r, BOM)
#   - KbdInteractiveAuthentication отключён
#   - Инструкции с полным Windows-путём к ключу
################################################################################

set -euo pipefail

# ─── Настройки ────────────────────────────────────────────────────────────────
OPENCLAW_USER="openclaw"
OPENCLAW_PORT="${OPENCLAW_PORT:-3000}"

# ─── Цвета ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─── Логирование ──────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ─── Trap для ошибок ──────────────────────────────────────────────────────────
cleanup_on_error() {
    local exit_code=$?
    local line_no=$1
    if [ $exit_code -ne 0 ]; then
        log_error "Скрипт упал на строке ${line_no} с кодом ${exit_code}"
        log_error "Проверьте вывод выше для деталей"
        if [ -n "${SSH_BACKUP:-}" ] && [ -f "$SSH_BACKUP" ]; then
            log_warning "Восстанавливаю SSH конфиг из бэкапа..."
            cp "$SSH_BACKUP" /etc/ssh/sshd_config
            systemctl restart ssh 2>/dev/null || true
            log_success "SSH конфиг восстановлен"
        fi
    fi
}
trap 'cleanup_on_error ${LINENO}' ERR

################################################################################
# ПРОВЕРКИ
################################################################################

log_info "Начинаем автоматическую настройку OpenClaw VPS v4..."

# Проверка root
if [[ $EUID -ne 0 ]]; then
    log_error "Этот скрипт должен быть запущен от root!"
    echo "Используйте: sudo bash setup-openclaw.sh"
    exit 1
fi
log_success "Скрипт запущен от root"

# Проверка OS
if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    log_warning "Обнаружена не Ubuntu. Скрипт может работать некорректно."
fi

# Проверка SSH ключа
if [ ! -f /root/.ssh/authorized_keys ] || [ ! -s /root/.ssh/authorized_keys ]; then
    log_error "SSH ключ не найден или пуст в /root/.ssh/authorized_keys"
    log_info "Сначала добавьте публичный ключ в панели хостинга"
    exit 1
fi
log_success "SSH ключ найден"

################################################################################
# 1. СМЕНА ПАРОЛЯ ROOT
################################################################################

log_info "Генерирую новый пароль root..."

ROOT_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)

chpasswd <<< "root:${ROOT_PASSWORD}"

log_success "Пароль root изменён"

SERVER_IP=$(hostname -I | awk '{print $1}')
CREDENTIALS_FILE="/root/SECURITY_CREDENTIALS.txt"

cat > "$CREDENTIALS_FILE" <<EOF
OpenClaw VPS Security Setup - $(date)
=======================================
Root password: ${ROOT_PASSWORD}
SSH: ssh ${OPENCLAW_USER}@${SERVER_IP}
User: ${OPENCLAW_USER}
Saved: $(date)
EOF
chmod 600 "$CREDENTIALS_FILE"

log_success "Креденшалы сохранены в ${CREDENTIALS_FILE}"

################################################################################
# 2. СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
################################################################################

log_info "Создаю пользователя '${OPENCLAW_USER}'..."

if id "${OPENCLAW_USER}" &>/dev/null; then
    log_warning "Пользователь '${OPENCLAW_USER}' уже существует, пропускаю"
else
    useradd -m -s /bin/bash "${OPENCLAW_USER}"
    log_success "Пользователь '${OPENCLAW_USER}' создан"
fi

################################################################################
# 3. КОПИРОВАНИЕ SSH КЛЮЧА (с фиксом кодировки)
################################################################################

log_info "Копирую SSH ключ для '${OPENCLAW_USER}'..."

mkdir -p /home/${OPENCLAW_USER}/.ssh

# Копируем ключ и чистим кодировку (\r, BOM)
sed 's/\r$//' /root/.ssh/authorized_keys | tr -d '\xEF\xBB\xBF' > /home/${OPENCLAW_USER}/.ssh/authorized_keys

chown -R ${OPENCLAW_USER}:${OPENCLAW_USER} /home/${OPENCLAW_USER}/.ssh
chmod 700 /home/${OPENCLAW_USER}/.ssh
chmod 600 /home/${OPENCLAW_USER}/.ssh/authorized_keys

if [ ! -s /home/${OPENCLAW_USER}/.ssh/authorized_keys ]; then
    log_error "authorized_keys для ${OPENCLAW_USER} пуст! Прерываю."
    exit 1
fi

log_success "SSH ключ скопирован и очищен от артефактов кодировки"

################################################################################
# 4. SUDOERS (безопасно через /etc/sudoers.d/)
################################################################################

log_info "Настраиваю sudoers для '${OPENCLAW_USER}'..."

SUDOERS_FILE="/etc/sudoers.d/${OPENCLAW_USER}"

echo "${OPENCLAW_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"

if ! visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
    log_error "Ошибка в sudoers файле! Удаляю..."
    rm -f "$SUDOERS_FILE"
    exit 1
fi

log_success "Sudoers настроен (${SUDOERS_FILE})"

################################################################################
# 5. КОНФИГУРАЦИЯ SSH
################################################################################

log_info "Конфигурирую SSH..."

SSH_BACKUP="/etc/ssh/sshd_config.backup.$(date +%s)"
cp /etc/ssh/sshd_config "$SSH_BACKUP"
log_success "Бэкап SSH конфига: ${SSH_BACKUP}"

set_sshd_param() {
    local param="$1"
    local value="$2"
    local config="/etc/ssh/sshd_config"
    sed -i "/^#\?${param}\s/d" "$config"
    echo "${param} ${value}" >> "$config"
}

set_sshd_param "PermitRootLogin" "no"
set_sshd_param "PasswordAuthentication" "no"
set_sshd_param "PubkeyAuthentication" "yes"
set_sshd_param "ChallengeResponseAuthentication" "no"
set_sshd_param "KbdInteractiveAuthentication" "no"

if ! sshd -t 2>/dev/null; then
    log_error "SSH конфиг имеет ошибки! Восстанавливаю..."
    cp "$SSH_BACKUP" /etc/ssh/sshd_config
    exit 1
fi
log_success "SSH конфиг валиден"

systemctl restart ssh

sleep 1
if ! systemctl is-active --quiet ssh; then
    log_error "SSH не запустился после рестарта! Восстанавливаю..."
    cp "$SSH_BACKUP" /etc/ssh/sshd_config
    systemctl restart ssh
    exit 1
fi

log_success "SSH daemon перезагружен и работает"

################################################################################
# 6. ОБНОВЛЕНИЕ СИСТЕМЫ
################################################################################

log_info "Обновляю систему..."

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get install -y -qq \
    curl \
    git \
    wget \
    vim \
    htop \
    net-tools \
    zip \
    unzip \
    ca-certificates

log_success "Система обновлена"

################################################################################
# 7. NODE.JS
################################################################################

log_info "Проверяю Node.js..."

if ! command -v node &>/dev/null; then
    log_info "Node.js не найден, устанавливаю v24..."
    curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/nodesource_setup.sh
    if [ ! -s /tmp/nodesource_setup.sh ]; then
        log_error "Не удалось скачать установщик Node.js"
        exit 1
    fi
    bash /tmp/nodesource_setup.sh
    apt-get install -y -qq nodejs
    rm -f /tmp/nodesource_setup.sh
    log_success "Node.js $(node --version) установлен"
else
    log_success "Node.js $(node --version) уже установлен"
fi

################################################################################
# 8. OPENCLAW (через npm — pnpm не подтягивает зависимости плагинов)
################################################################################

log_info "Устанавливаю OpenClaw через npm для '${OPENCLAW_USER}'..."

# npm global в homedir пользователя (без sudo, без конфликтов)
su - "${OPENCLAW_USER}" -c '
    # Создаём директорию для глобальных npm-пакетов
    mkdir -p ~/.npm-global

    # Настраиваем npm prefix
    npm config set prefix "~/.npm-global"

    # Добавляем в PATH если ещё не добавлено
    if ! grep -q "npm-global/bin" ~/.bashrc 2>/dev/null; then
        echo "" >> ~/.bashrc
        echo "# npm global packages" >> ~/.bashrc
        echo "export PATH=\$HOME/.npm-global/bin:\$PATH" >> ~/.bashrc
    fi

    # Устанавливаем OpenClaw
    export PATH=$HOME/.npm-global/bin:$PATH
    npm install -g openclaw@latest
'

# Проверяем установку
OPENCLAW_VERSION=$(su - "${OPENCLAW_USER}" -c 'source ~/.bashrc 2>/dev/null; openclaw --version 2>/dev/null' || echo "не определена")
log_success "OpenClaw ${OPENCLAW_VERSION} установлен для ${OPENCLAW_USER}"

################################################################################
# 9. FIREWALL
################################################################################

log_info "Настраиваю firewall..."

if ! command -v ufw &>/dev/null; then
    log_info "UFW не найден, устанавливаю..."
    apt-get install -y -qq ufw
fi

if command -v ufw &>/dev/null; then
    ufw default deny incoming 2>/dev/null || true
    ufw default allow outgoing 2>/dev/null || true
    ufw allow 22/tcp comment 'SSH' 2>/dev/null || true
    ufw allow 80/tcp comment 'HTTP' 2>/dev/null || true
    ufw allow 443/tcp comment 'HTTPS' 2>/dev/null || true
    ufw allow "${OPENCLAW_PORT}/tcp" comment 'OpenClaw' 2>/dev/null || true
    ufw --force enable 2>/dev/null || true
    log_success "Firewall настроен (SSH, HTTP, HTTPS, OpenClaw:${OPENCLAW_PORT})"
else
    log_warning "Не удалось установить UFW"
fi

################################################################################
# 10. ИТОГОВЫЙ ОТЧЁТ
################################################################################

echo ""
log_success "=========================================="
log_success "  Автоматическая настройка завершена!"
log_success "=========================================="
echo ""
echo -e "${BLUE}ДОСТУП К СЕРВЕРУ (PowerShell на ПК):${NC}"
echo -e "  ssh -i C:\\Users\\<USERNAME>\\.ssh\\id_openclaw ${OPENCLAW_USER}@${SERVER_IP}"
echo ""
echo -e "${BLUE}Root пароль:${NC} ${ROOT_PASSWORD}"
echo -e "  Сохранён в: ${CREDENTIALS_FILE}"
echo ""
echo -e "${RED}⚠ СОХРАНИТЕ ПАРОЛЬ В PASSWORD MANAGER И ЗАКРОЙТЕ ТЕРМИНАЛ${NC}"
echo ""
echo -e "${BLUE}СЛЕДУЮЩИЕ ШАГИ (от пользователя ${OPENCLAW_USER}):${NC}"
echo "  1. В НОВОМ терминале проверьте подключение:"
echo "     ssh -i C:\\Users\\<USERNAME>\\.ssh\\id_openclaw ${OPENCLAW_USER}@${SERVER_IP}"
echo ""
echo "  2. Запустите onboarding:"
echo "     openclaw onboard --install-daemon"
echo ""
echo "  3. SSH туннель для веб-интерфейса (с ПК):"
echo "     ssh -i C:\\Users\\<USERNAME>\\.ssh\\id_openclaw -N -L 18789:127.0.0.1:18789 ${OPENCLAW_USER}@${SERVER_IP}"
echo "     Затем откройте: http://localhost:18789"
echo ""

################################################################################
# 11. ФИНАЛЬНЫЕ ПРОВЕРКИ
################################################################################

log_info "Финальные проверки..."

CHECKS_PASSED=0
CHECKS_TOTAL=6

grep -q "^PermitRootLogin no" /etc/ssh/sshd_config && { log_success "Root SSH login отключён"; ((CHECKS_PASSED++)); } || log_error "Root SSH login НЕ отключён"
grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config && { log_success "Password auth отключена"; ((CHECKS_PASSED++)); } || log_error "Password auth НЕ отключена"
id "${OPENCLAW_USER}" &>/dev/null && { log_success "Пользователь '${OPENCLAW_USER}' существует"; ((CHECKS_PASSED++)); } || log_error "Пользователь НЕ создан"
[ -f "$SUDOERS_FILE" ] && { log_success "Sudoers настроен"; ((CHECKS_PASSED++)); } || log_error "Sudoers НЕ настроен"
command -v node &>/dev/null && { log_success "Node.js $(node --version)"; ((CHECKS_PASSED++)); } || log_error "Node.js НЕ установлен"
su - "${OPENCLAW_USER}" -c 'source ~/.bashrc 2>/dev/null; command -v openclaw' &>/dev/null && { log_success "OpenClaw установлен для ${OPENCLAW_USER}"; ((CHECKS_PASSED++)); } || log_error "OpenClaw НЕ установлен"

echo ""
if [ "$CHECKS_PASSED" -eq "$CHECKS_TOTAL" ]; then
    log_success "Все проверки пройдены (${CHECKS_PASSED}/${CHECKS_TOTAL})"
else
    log_warning "Проверки: ${CHECKS_PASSED}/${CHECKS_TOTAL}"
fi

echo ""
log_info "Сервер: $(hostname) | IP: ${SERVER_IP} | OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2) | Node: $(node --version 2>/dev/null || echo 'N/A')"
echo ""

exit 0
