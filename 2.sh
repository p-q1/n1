#!/bin/bash
clear
cat <<'EOF'
2: NAT НА ISP
 [ISP]
   nano /etc/net/sysctl.conf          # net.ipv4.ip_forward = 1
   sysctl -p /etc/net/sysctl.conf
   iptables -t nat -A POSTROUTING -o ens19 -j MASQUERADE
   iptables -P FORWARD ACCEPT
   iptables-save > /etc/sysconfig/iptables
   systemctl enable --now iptables
   ping 8.8.8.8

 [HQ-RTR, BR-RTR]
   nano /etc/net/sysctl.conf          # net.ipv4.ip_forward = 1
   sysctl -p /etc/net/sysctl.conf
   ping 8.8.8.8
   
EOF
