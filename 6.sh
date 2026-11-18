#!/bin/bash
clear
cat <<'EOF'
6: GRE-ТУННЕЛЬ ЧЕРЕЗ nmtui
 [HQ-RTR]
   nmtui → Edit a connection → Add → IP tunnel
     ├ Device:   gre1
     ├ Mode:     GRE
     ├ Local:    172.16.30.2
     ├ Remote:   172.16.40.2
     └ IPv4:     Manual · Address = 10.10.10.1/30

 [BR-RTR]
   nmtui → Edit a connection → Add → IP tunnel
     ├ Device:   gre1
     ├ Mode:     GRE
     ├ Local:    172.16.40.2
     ├ Remote:   172.16.30.2
     └ IPv4:     Manual · Address = 10.10.10.2/30

 После создания: Activate a connection → поднять gre1.
 Проверка: ping 10.10.10.2 (с HQ-RTR) / ping 10.10.10.1 (с BR-RTR).

EOF
