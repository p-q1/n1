#!/bin/bash
clear
cat <<'EOF'
══════════════════════════════════════════════════════════════════════════════
 ЗАДАНИЕ 3: ПОЛЬЗОВАТЕЛИ И SUDO
══════════════════════════════════════════════════════════════════════════════
 [HQ-SRV, BR-SRV]
   apt-get update && apt-get install -y sudo
   useradd -u 2027 -m -s /bin/bash sshuser
   echo 'sshuser:P@ssw0rd' | chpasswd
   usermod -aG wheel sshuser
   echo 'sshuser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/sshuser
   chmod 0440 /etc/sudoers.d/sshuser
   id sshuser && sudo -u sshuser sudo -n true && echo OK

 [HQ-RTR, BR-RTR]
   apt-get update && apt-get install -y sudo
   useradd -m -s /bin/bash net_admin
   echo 'net_admin:P@ssw0rd' | chpasswd
   usermod -aG wheel net_admin
   echo 'net_admin ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/net_admin
   chmod 0440 /etc/sudoers.d/net_admin
   id net_admin && sudo -u net_admin sudo -n true && echo OK
══════════════════════════════════════════════════════════════════════════════
EOF
