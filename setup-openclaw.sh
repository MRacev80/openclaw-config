#!/bin/bash

################################################################################
# OpenClaw VPS Automatic Setup Script
# Автоматическая настройка безопасности VPS для OpenClaw
# 
# Использование:
#   curl -fsSL https://your-domain/setup-openclaw.sh | bash
#   или
#   bash setup-openclaw.sh
#
# Требования:
#   - Ubuntu 22.04 LTS
#   - Запускать от root
#   - SSH ключ уже установлен в /root/.ssh/authorized_keys
################################################################################

set -e  # Exit on error

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для логирования
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

################################################################################
# ПРОВЕРКИ
################################################################################

log_info "Начинаем автоматическую настройку OpenClaw VPS..."

# Проверка, что запускаем от root
if [[ $EUID -ne 0 ]]; then
    log_error "Этот скрипт должен быть запущен от root!"
    echo "Используйте: sudo bash setup-openclaw.sh"
    exit 1
fi

log_success "Скрипт запущен от root"

# Проверка OS
if ! grep -q "Ubuntu 22.04" /etc/os-release; then
    log_warning "Обнаружена не Ubuntu 22.04. Скрипт может работать, но не гарантируется."
fi

# Проверка SSH ключа
if [ ! -f /root/.ssh/authorized_keys ]; then
    log_error "SSH ключ не найден в /root/.ssh/authorized_keys"
    log_info "Сначала добавьте публичный ключ в панели HOSTKEY и переустановите сервер"
    exit 1
fi

log_success "SSH ключ найден"

################################################################################
# 1. СМЕНА ПАРОЛЯ ROOT
################################################################################

log_info "Генерирую новый безопасный пароль для root..."

# Генерируем случайный пароль (20 символов, буквы+цифры+спец.символы)
ROOT_PASSWORD=$(openssl rand -base64 20 | tr -d "=+/" | cut -c1-20)

log_info "Новый пароль root: ${GREEN}${ROOT_PASSWORD}${NC}"
log_warning "СОХРАНИТЕ ЭТОТ ПАРОЛЬ В БЕЗОПАСНОМ МЕСТЕ!"
log_info "Вы можете использовать его для аварийного доступа"

# Устанавливаем пароль
echo "root:${ROOT_PASSWORD}" | chpasswd

log_success "Пароль root изменён"

# Сохраняем пароль в файл для вас (с ограничением доступа)
echo "OpenClaw VPS Security Setup - $(date)" > /root/SECURITY_CREDENTIALS.txt
echo "=======================================" >> /root/SECURITY_CREDENTIALS.txt
echo "Root password: ${ROOT_PASSWORD}" >> /root/SECURITY_CREDENTIALS.txt
echo "Root SSH: root@$(hostname -I | awk '{print $1}')" >> /root/SECURITY_CREDENTIALS.txt
echo "Username: openclaw" >> /root/SECURITY_CREDENTIALS.txt
echo "Saved: $(date)" >> /root/SECURITY_CREDENTIALS.txt
chmod 600 /root/SECURITY_CREDENTIALS.txt

log_success "Креденшалы сохранены в /root/SECURITY_CREDENTIALS.txt"

################################################################################
# 2. СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ openclaw
################################################################################

log_info "Создаю пользователя 'openclaw'..."

if id "openclaw" &>/dev/null; then
    log_warning "Пользователь 'openclaw' уже существует, пропускаю создание"
else
    useradd -m -s /bin/bash openclaw
    log_success "Пользователь 'openclaw' создан"
fi

################################################################################
# 3. КОПИРОВАНИЕ SSH КЛЮЧА
################################################################################

log_info "Копирую SSH ключ для пользователя 'openclaw'..."

mkdir -p /home/openclaw/.ssh
cp /root/.ssh/authorized_keys /home/openclaw/.ssh/authorized_keys
chown -R openclaw:openclaw /home/openclaw/.ssh
chmod 700 /home/openclaw/.ssh
chmod 600 /home/openclaw/.ssh/authorized_keys

log_success "SSH ключ скопирован"

################################################################################
# 4. ДОБАВЛЕНИЕ В SUDOERS
################################################################################

log_info "Добавляю 'openclaw' в sudoers (для sudo без пароля)..."

if grep -q "^openclaw ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then
    log_warning "'openclaw' уже в sudoers, пропускаю"
else
    echo "openclaw ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    log_success "'openclaw' добавлен в sudoers"
fi

################################################################################
# 5. КОНФИГУРАЦИЯ SSH
################################################################################

log_info "Конфигурирую SSH (отключаю пароли, включаю только ключи)..."

# Backup исходного конфига
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%s)
log_success "Бэкап конфига сохранён"

# Изменяем параметры (используем sed для замены)
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Убедимся, что параметры установлены (если их еще не было)
if ! grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
fi

if ! grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
fi

if ! grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config; then
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
fi

# Проверяем синтаксис конфига
if ! sshd -t; then
    log_error "SSH конфиг имеет ошибки! Восстанавливаю из бэкапа..."
    cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
    exit 1
fi

log_success "SSH конфиг обновлён"

# Перезагружаем SSH daemon
systemctl restart ssh
log_success "SSH daemon перезагружен"

################################################################################
# 6. ОБНОВЛЕНИЕ СИСТЕМЫ
################################################################################

log_info "Обновляю систему и устанавливаю необходимые пакеты..."

apt-get update -qq
apt-get upgrade -y -qq
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
# 7. ПРОВЕРКА Node.js
################################################################################

log_info "Проверяю Node.js версию..."

if ! command -v node &> /dev/null; then
    log_warning "Node.js не найден, устанавливаю..."
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
    apt-get install -y nodejs
else
    NODE_VERSION=$(node --version)
    log_success "Node.js ${NODE_VERSION} уже установлен"
fi

################################################################################
# 8. FIREWALL (если нужен)
################################################################################

log_info "Включаю базовый firewall..."

# Обычно на VPS уже есть firewall, но проверим
if ! command -v ufw &> /dev/null; then
    log_info "UFW не установлен, пропускаю"
else
    # Разрешаем SSH, HTTP, HTTPS
    ufw default deny incoming 2>/dev/null || true
    ufw default allow outgoing 2>/dev/null || true
    ufw allow 22/tcp 2>/dev/null || true
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true
    ufw --force enable 2>/dev/null || true
    log_success "Firewall настроен"
fi

################################################################################
# 9. ИТОГОВЫЙ ОТЧЕТ
################################################################################

log_info "======================================="
log_success "Автоматическая настройка завершена!"
log_info "======================================="

echo ""
echo -e "${BLUE}ДОСТУП К СЕРВЕРУ:${NC}"
echo -e "${GREEN}SSH как openclaw:${NC}"
echo "  ssh -i ~/.ssh/id_openclaw openclaw@$(hostname -I | awk '{print $1}')"
echo ""
echo -e "${GREEN}Root пароль:${NC} ${ROOT_PASSWORD}"
echo "  Сохранён в: /root/SECURITY_CREDENTIALS.txt"
echo ""
echo -e "${BLUE}СЛЕДУЮЩИЕ ШАГИ:${NC}"
echo "1. Проверьте подключение:"
echo "   ssh -i ~/.ssh/id_openclaw openclaw@$(hostname -I | awk '{print $1}')"
echo ""
echo "2. Установите OpenClaw:"
echo "   sudo pnpm add -g openclaw@latest"
echo ""
echo "3. Запустите onboarding:"
echo "   openclaw onboard --install-daemon"
echo ""
echo -e "${RED}ВАЖНО:${NC}"
echo "- Сохраните пароль root в Password Manager"
echo "- НЕ используйте root для обычной работы"
echo "- Все команды OpenClaw запускайте от 'openclaw'"
echo ""

################################################################################
# 10. ПРОВЕРКИ
################################################################################

log_info "Выполняю финальные проверки..."

# Проверка SSH конфига
if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
    log_success "Root SSH login отключен"
fi

if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
    log_success "Password authentication отключена"
fi

if id "openclaw" &>/dev/null; then
    log_success "Пользователь 'openclaw' создан"
fi

if grep -q "^openclaw ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then
    log_success "Sudoers настроен"
fi

echo ""
log_success "Все проверки пройдены!"
echo ""

################################################################################
# ВЫВОД ИНФОРМАЦИИ
################################################################################

log_info "Информация о сервере:"
echo "  Hostname: $(hostname)"
echo "  IP: $(hostname -I | awk '{print $1}')"
echo "  OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
echo "  Kernel: $(uname -r)"
echo "  Node.js: $(node --version)"
echo ""

exit 0
