#!/bin/bash
clear
cat <<'EOF'
══════════════════════════════════════════════════════════════════════════════
 ЗАДАНИЕ 9: DHCP ДЛЯ HQ-CLI (интерфейс vlan200)
══════════════════════════════════════════════════════════════════════════════
 [HQ-RTR]
   apt-get install -y dhcp-server
   cat > /etc/dhcp/dhcpd.conf <<EOT
ddns-update-style none;
subnet 192.168.200.0 netmask 255.255.255.240 {
  option routers 192.168.200.1;
  option subnet-mask 255.255.255.240;
  option domain-name "au-team.irpo";
  option domain-name-servers 192.168.100.2;
  range dynamic-bootp 192.168.200.2 192.168.200.10;
}
EOT
   echo 'DHCPDARGS=vlan200' > /etc/sysconfig/dhcpd
   dhcpd -t -cf /etc/dhcp/dhcpd.conf
   systemctl enable --now dhcpd
   systemctl is-active dhcpd && ss -ulnp | grep 67
══════════════════════════════════════════════════════════════════════════════
 Проверка на HQ-CLI: ip a (адрес 192.168.200.2–10), ip route (шлюз 192.168.200.1).
══════════════════════════════════════════════════════════════════════════════
EOF
