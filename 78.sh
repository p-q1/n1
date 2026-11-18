#!/bin/bash
clear
cat <<'EOF'
══════════════════════════════════════════════════════════════════════════════
 ЗАДАНИЯ 7-8: OSPF (FRR) + NAT
══════════════════════════════════════════════════════════════════════════════
 [HQ-RTR, BR-RTR, BR-FW] — установка FRR
   echo 'nameserver 8.8.8.8' > /etc/resolv.conf
   apt-get update && apt-get install -y frr
   sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
   systemctl enable --now frr && systemctl restart frr

 [HQ-RTR] OSPF + MD5
   vtysh -c 'conf t' -c 'router ospf' -c 'passive-interface default' \
     -c 'network 10.10.10.0/30 area 0' -c 'network 192.168.100.0/27 area 0' \
     -c 'network 192.168.200.0/28 area 0' -c 'int gre1' \
     -c 'no ip ospf passive' -c 'ip ospf authentication message-digest' \
     -c 'ip ospf message-digest-key 1 md5 P@ssw0rd' -c 'ip ospf network point-to-point' \
     -c 'end' && vtysh -c 'write memory'

 [BR-RTR] OSPF + MD5
   vtysh -c 'conf t' -c 'router ospf' -c 'passive-interface default' \
     -c 'network 10.10.10.0/30 area 0' -c 'network 192.168.30.0/30 area 0' \
     -c 'int gre1' -c 'no ip ospf passive' \
     -c 'ip ospf authentication message-digest' \
     -c 'ip ospf message-digest-key 1 md5 P@ssw0rd' -c 'ip ospf network point-to-point' \
     -c 'int ens20' -c 'no ip ospf passive' -c 'ip ospf network point-to-point' \
     -c 'end' && vtysh -c 'write memory'

 [BR-FW] OSPF без MD5
   vtysh -c 'conf t' -c 'router ospf' -c 'passive-interface default' \
     -c 'network 192.168.30.0/30 area 0' -c 'network 192.168.0.0/28 area 0' \
     -c 'int ens19' -c 'no ip ospf passive' -c 'ip ospf network point-to-point' \
     -c 'end' && vtysh -c 'write memory'

 [HQ-RTR, BR-RTR, BR-FW] — NAT и ip_forward
   sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
   sysctl -p /etc/net/sysctl.conf
   iptables -t nat -A POSTROUTING -o ens19 -j MASQUERADE
   iptables -P FORWARD ACCEPT
   iptables-save > /etc/sysconfig/iptables
   systemctl enable --now iptables
══════════════════════════════════════════════════════════════════════════════
 Проверка: vtysh -c 'show ip ospf neighbor' (Full) · ping 8.8.8.8
══════════════════════════════════════════════════════════════════════════════
EOF
