#!/bin/bash
clear
cat <<'EOF'
══════════════════════════════════════════════════════════════════════════════
 ЗАДАНИЕ 5: SSH — порт 2027, только sshuser, 2 попытки, баннер
══════════════════════════════════════════════════════════════════════════════
 [HQ-SRV, BR-SRV] — одинаково на обеих машинах
   echo 'Authorized access only' > /etc/openssh/banner
   sed -i '/^#*Port /d; /^#*MaxAuthTries /d; /^#*Banner /d; /^AllowUsers/d' \
     /etc/openssh/sshd_config
   cat >> /etc/openssh/sshd_config <<EOT
Port 2027
MaxAuthTries 2
Banner /etc/openssh/banner
AllowUsers sshuser
EOT
   systemctl restart sshd
   systemctl is-active sshd && ss -tln | grep 2027
══════════════════════════════════════════════════════════════════════════════
EOF
