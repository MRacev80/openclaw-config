# Быстрый старт: Автоматическая настройка OpenClaw VPS

Скрипт `setup-openclaw.sh` автоматизирует всю безопасность-настройку.

---

## КАК ИСПОЛЬЗОВАТЬ СКРИПТ

### Способ 1: Скачать и запустить (рекомендуется)

```bash
# На вашем ПК (Windows PowerShell)
ssh -i C:\Users\gamil\.ssh\id_openclaw root@82.40.56.157

# На сервере (вы уже от root)
cd /tmp
curl -fsSL https://raw.githubusercontent.com/MRacev80/openclaw-config/main/setup-openclaw.sh -o setup-openclaw.sh
chmod +x setup-openclaw.sh
sudo bash setup-openclaw.sh
```

Если у вас нет интернета на сервере:
```bash
# На вашем ПК
scp -i C:\Users\gamil\.ssh\id_openclaw setup-openclaw.sh root@82.40.56.157:/tmp/

# Потом на сервере
ssh -i C:\Users\gamil\.ssh\id_openclaw root@82.40.56.157
cd /tmp
sudo bash setup-openclaw.sh
```

### Способ 2: Одной командой (самый быстрый)

```bash
ssh -i C:\Users\gamil\.ssh\id_openclaw root@82.40.56.157
bash <(curl -fsSL https://your-script-url/setup-openclaw.sh)
```

---

## ЧТО ДЕЛАЕТ СКРИПТ

✅ Смена пароля root на случайный сложный  
✅ Создание пользователя `openclaw`  
✅ Копирование SSH ключей  
✅ Добавление в sudoers (sudo без пароля)  
✅ Конфигурация SSH (отключаем пароли, включаем ключи)  
✅ Отключение логина root  
✅ Обновление системы  
✅ Установка Node.js 24+  
✅ Базовая настройка firewall  

**Время выполнения:** 3-5 минут

---

## ПОСЛЕ ЗАПУСКА СКРИПТА

Скрипт выведет:

```
[✓] Автоматическая настройка завершена!

SSH как openclaw:
  ssh -i ~/.ssh/id_openclaw openclaw@82.40.56.157

Root пароль: S3cur3#OpenClaw$VPS@2026!abc123
  Сохранён в: /root/SECURITY_CREDENTIALS.txt

СЛЕДУЮЩИЕ ШАГИ:
1. Проверьте подключение:
   ssh -i ~/.ssh/id_openclaw openclaw@82.40.56.157

2. Установите OpenClaw:
   sudo pnpm add -g openclaw@latest

3. Запустите onboarding:
   openclaw onboard --install-daemon
```

### Сохраните эту информацию!

Пароль root сохранён в файл на сервере:
```bash
cat /root/SECURITY_CREDENTIALS.txt
```

Скопируйте в Password Manager (Bitwarden, 1Password):
```
Server: 82.40.56.157
User: root
Password: (полученный пароль)
SSH key: ~/.ssh/id_openclaw
```

---

## ПРОВЕРКА, ЧТО ВСЁ РАБОТАЕТ

После скрипта:

```powershell
# На вашем ПК
ssh -i C:\Users\gamil\.ssh\id_openclaw openclaw@82.40.56.157

# На сервере (вы теперь от openclaw)
whoami  # должно быть "openclaw"
sudo whoami  # должно быть "root" (без пароля)
exit
```

---

## ЕСЛИ СКРИПТ УПАЛ

Скрипт делает бэкап SSH конфига перед изменениями:

```bash
# На сервере
ls -la /etc/ssh/sshd_config.backup.*

# Если что-то сломалось
sudo cp /etc/ssh/sshd_config.backup.XXXXX /etc/ssh/sshd_config
sudo systemctl restart ssh
```

---

## ДАЛЬШЕ: УСТАНОВКА OpenClaw

После успешного скрипта:

```bash
ssh -i C:\Users\gamil\.ssh\id_openclaw openclaw@82.40.56.157

# Установите OpenClaw
sudo pnpm add -g openclaw@latest

# Проверьте версию
openclaw --version

# Запустите onboarding
openclaw onboard --install-daemon
```

---

## СТРУКТУРА СКРИПТА

```
setup-openclaw.sh
├─ Проверки (root, OS, SSH ключ)
├─ 1. Смена пароля root
├─ 2. Создание пользователя openclaw
├─ 3. Копирование SSH ключей
├─ 4. Sudoers конфиг
├─ 5. SSH конфиг (отключаем пароли)
├─ 6. Обновление системы + пакеты
├─ 7. Node.js 24+
├─ 8. Firewall (если нужен)
└─ 9. Итоговый отчет + проверки
```

---

## КАСТОМИЗАЦИЯ СКРИПТА

Если хотите изменить:

### Другое имя пользователя (вместо "openclaw")

В скрипте найдите:
```bash
openclaw  # замените на "ваше-имя"
```

И замените везде на нужное.

### Отключить автоматическую смену пароля

Закомментируйте в скрипте:
```bash
# ROOT_PASSWORD=$(openssl rand -base64 20 ...)
# echo "root:${ROOT_PASSWORD}" | chpasswd
```

### Отключить firewall

Закомментируйте раздел:
```bash
# log_info "Включаю базовый firewall..."
# ufw ...
```

---

## БЕЗОПАСНОСТЬ

Скрипт:
- ✅ Не хранит пароли в логах
- ✅ Использует `set -e` (выход при ошибке)
- ✅ Делает бэкап SSH конфига
- ✅ Проверяет синтаксис конфига перед перезагрузкой
- ✅ Ограничивает права доступа (chmod 600)

---

## ЧЕКЛИСТ

- [ ] Скрипт скачан (или готов к использованию)
- [ ] Подключены по SSH к root@82.40.56.157
- [ ] Запустили `bash setup-openclaw.sh`
- [ ] Скрипт завершился успешно
- [ ] Сохранили пароль root в Password Manager
- [ ] Подключились как openclaw (не root)
- [ ] Установили OpenClaw
- [ ] Запустили `openclaw onboard`

---

**Готово! Запустите скрипт и вернитесь, когда закончится.** 🚀
