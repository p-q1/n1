#!/bin/bash
clear
cat <<'EOF'
══════════════════════════════════════════════════════════════════════════════
 ЗАДАНИЕ 4: VLAN ЧЕРЕЗ nmtui
══════════════════════════════════════════════════════════════════════════════
 [HQ-RTR]  ens20 — trunk (без IP), поверх него 3 VLAN
   nmtui → Edit a connection → Add → VLAN
     ├ vlan100:  Parent = ens20 · VLAN ID = 100 · IPv4 = Manual · 192.168.100.1/27
     ├ vlan200:  Parent = ens20 · VLAN ID = 200 · IPv4 = Manual · 192.168.200.1/28
     └ vlan999:  Parent = ens20 · VLAN ID = 999 · IPv4 = Manual · 192.168.99.1/29
   (ens20 оставить без IP — только Parent)

 [HQ-SRV]  ens19 — trunk, VLAN 100
   nmtui → Edit a connection → Add → VLAN
     └ vlan100:  Parent = ens19 · VLAN ID = 100 · IPv4 = Manual · 192.168.100.2/27
                 Gateway = 192.168.100.1

 [HQ-CLI]  ens19 — trunk, VLAN 200, адрес по DHCP
   nmtui → Edit a connection → Add → VLAN
     └ vlan200:  Parent = ens19 · VLAN ID = 200 · IPv4 = Automatic (DHCP)
══════════════════════════════════════════════════════════════════════════════
 После создания: Activate a connection → поднять каждый VLAN.
 Проверка: ip -br a  (на HQ-RTR видны vlan100/200/999, на SRV/CLI — свои).
══════════════════════════════════════════════════════════════════════════════
EOF
