#!/bin/bash
clear
cat <<'EOF'
══════════════════════════════════════════════════════════════════════════════
 ЗАДАНИЕ 11: ЧАСОВОЙ ПОЯС (Europe/Moscow)
══════════════════════════════════════════════════════════════════════════════
 [ВСЕ УСТРОЙСТВА, кроме виртуального коммутатора]
   timedatectl set-timezone Europe/Moscow
   timedatectl | grep -E 'Time zone|Local time'

   # Если timedatectl ругается (нет systemd-timesyncd в минимальной сборке):
   ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
   echo 'Europe/Moscow' > /etc/timezone
   timedatectl | grep 'Time zone'
══════════════════════════════════════════════════════════════════════════════
 Проверка: date  → должен показать MSK (+03)
══════════════════════════════════════════════════════════════════════════════
EOF
