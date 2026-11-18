#!/bin/bash
ISP_ENS20="172.16.30.1/28";  ISP_ENS21="172.16.40.1/28"
HQ_RTR_ENS19="172.16.30.2/28"; HQ_RTR_ENS20="192.168.100.1/27"
HQ_RTR_ENS21="192.168.200.1/28"; HQ_RTR_GRE="10.10.10.1/30"
BR_RTR_ENS19="172.16.40.2/28"; BR_RTR_ENS20="192.168.30.1/30"
BR_RTR_GRE="10.10.10.2/30"
BR_FW_ENS19="192.168.30.2/30"; BR_FW_ENS20="192.168.0.1/28"
HQ_SRV="192.168.100.2/27"; BR_SRV="192.168.0.2/28"
HQ_CLI_NET="192.168.200.0/28"
ask() { local p="$1" d="$2" v; read -r -p "$p [$d]: " v; echo "${v:-$d}"; }
echo "=== Ввод IP (Enter — оставить по умолчанию) ==="
ISP_ENS20=$(ask "ISP ens20 (→HQ)" "$ISP_ENS20")
ISP_ENS21=$(ask "ISP ens21 (→BR)" "$ISP_ENS21")
HQ_RTR_ENS19=$(ask "HQ-RTR ens19 (→ISP)" "$HQ_RTR_ENS19")
HQ_RTR_ENS20=$(ask "HQ-RTR ens20 (VLAN100)" "$HQ_RTR_ENS20")
HQ_RTR_ENS21=$(ask "HQ-RTR ens21 (VLAN200)" "$HQ_RTR_ENS21")
HQ_RTR_GRE=$(ask "HQ-RTR gre1" "$HQ_RTR_GRE")
BR_RTR_ENS19=$(ask "BR-RTR ens19 (→ISP)" "$BR_RTR_ENS19")
BR_RTR_ENS20=$(ask "BR-RTR ens20 (→BR-FW)" "$BR_RTR_ENS20")
BR_RTR_GRE=$(ask "BR-RTR gre1" "$BR_RTR_GRE")
BR_FW_ENS19=$(ask "BR-FW ens19 (→BR-RTR)" "$BR_FW_ENS19")
BR_FW_ENS20=$(ask "BR-FW ens20 (→BR-SRV)" "$BR_FW_ENS20")
HQ_SRV=$(ask "HQ-SRV" "$HQ_SRV")
BR_SRV=$(ask "BR-SRV" "$BR_SRV")
HQ_CLI_NET=$(ask "HQ-CLI сеть (DHCP)" "$HQ_CLI_NET")
clear
cat <<EOF
=== СХЕМА СЕТИ ===

Интернет
 └─ ISP (ens19: DHCP)
    ├ ens20: $ISP_ENS20 ── HQ-RTR
    └ ens21: $ISP_ENS21 ── BR-RTR

 HQ-RTR
    ├ ens19: $HQ_RTR_ENS19   (gw 172.16.30.1)
    ├ ens20: $HQ_RTR_ENS20 (VLAN 100)
    ├ ens21: $HQ_RTR_ENS21 (VLAN 200)
    ├ gre1:  $HQ_RTR_GRE
    ├ HQ-SRV: $HQ_SRV
    └ HQ-CLI: DHCP $HQ_CLI_NET (gw $HQ_RTR_ENS21)

 BR-RTR
    ├ ens19: $BR_RTR_ENS19   (gw 172.16.40.1)
    ├ ens20: $BR_RTR_ENS20
    ├ gre1:  $BR_RTR_GRE
    └ BR-FW
        ├ ens19: $BR_FW_ENS19 (gw $BR_RTR_ENS20)
        ├ ens20: $BR_FW_ENS20
        └ BR-SRV: $BR_SRV (gw $BR_FW_ENS20)

 GRE: $HQ_RTR_GRE ── $BR_RTR_GRE

 1. apt-get update && apt-get install -y NetworkManager-tui
    systemctl enable --now NetworkManager

 2. Переводим интерфейсы на NM:
    sed -i 's/^NM_CONTROLLED=.*/NM_CONTROLLED=yes/' /etc/net/ifaces/*/options
    sed -i 's/^DISABLED=.*/DISABLED=yes/'         /etc/net/ifaces/*/options
    (строки нет — вписать в options вручную)
    systemctl restart network NetworkManager
 3. nmtui → Edit a connection → интерфейс → Edit:
    IPv4 CONFIGURATION = Manual · Show · Addresses = IP/маска
    при необходимости — Gateway.  OK → Activate a connection.

 4. Проверка: ping <шлюз> && ping <удалённый_адрес>
EOF
