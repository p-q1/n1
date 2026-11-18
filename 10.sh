#!/bin/bash
clear
cat <<'EOF'
══════════════════════════════════════════════════════════════════════════════
 ЗАДАНИЕ 10: DNS НА HQ-SRV (Alt Linux, BIND в chroot)
══════════════════════════════════════════════════════════════════════════════
 [HQ-SRV]
   echo 'nameserver 8.8.8.8' > /etc/resolv.conf
   apt-get update && apt-get install -y bind bind-utils

   # 1. rndc (обязательно для управления без перезагрузки)
   rndc-confgen > /etc/bind/rndc.key
   sed -i '6,$d' /etc/bind/rndc.key

   # 2. Основные опции (путь chroot: /var/lib/bind/etc/options.conf)
   sed -i \
     -e 's/^\/\/ *listen-on.*/listen-on { any; };/' \
     -e 's/^\/\/ *forwarders.*/forwarders { 77.88.8.8; };/' \
     -e 's/^\/\/ *allow-query.*/allow-query { any; };/' \
     -e 's/^ *dnssec-validation.*/dnssec-validation no;/' \
     /var/lib/bind/etc/options.conf
   grep -q 'dnssec-validation' /var/lib/bind/etc/options.conf || \
     echo 'dnssec-validation no;' >> /var/lib/bind/etc/options.conf

   # 3. Подключение зон (rfc1912.conf)
   cat >> /var/lib/bind/etc/rfc1912.conf <<EOT
zone "au-team.irpo" { type master; file "/zone/au-team.irpo"; };
zone "100.168.192.in-addr.arpa" { type master; file "/zone/100.168.192.rev"; };
zone "0.168.192.in-addr.arpa" { type master; file "/zone/0.168.192.rev"; };
EOT

   # 4. Зоны — копируем шаблоны и правим
   cd /var/lib/bind/etc/zone/
   cp localhost au-team.irpo
   cat > au-team.irpo <<EOT
$TTL 1D
@ IN SOA au-team.irpo. root.au-team.irpo. (
  2024102200 12H 1H 1W 1H )
  IN NS au-team.irpo.
  IN A 192.168.100.2
hq-rtr  IN A 192.168.100.1
br-rtr  IN A 192.168.30.1
br-fw   IN A 192.168.30.2
hq-srv  IN A 192.168.100.2
hq-cli  IN A 192.168.200.2
br-srv  IN A 192.168.0.2
docker  IN A 172.16.30.1
web     IN A 172.16.40.1
EOT

   cp 127.in-addr.arpa 100.168.192.rev
   cat > 100.168.192.rev <<EOT
$TTL 1D
@ IN SOA au-team.irpo. root.au-team.irpo. (
  2024102200 12H 1H 1W 1H )
  IN NS au-team.irpo.
2 IN PTR hq-srv.au-team.irpo.
EOT

   cp 100.168.192.rev 0.168.192.rev
   sed -i 's/^2 IN PTR hq-srv/2 IN PTR br-srv/' 0.168.192.rev

   # 5. Права и запуск
   chown named:named au-team.irpo 100.168.192.rev 0.168.192.rev
   chmod 600 au-team.irpo 100.168.192.rev 0.168.192.rev
   named-checkconf && named-checkzone au-team.irpo au-team.irpo
   systemctl enable --now bind
   systemctl status bind --no-pager
══════════════════════════════════════════════════════════════════════════════
 Проверка: nslookup hq-rtr.au-team.irpo 127.0.0.1
           nslookup 192.168.100.2 127.0.0.1
══════════════════════════════════════════════════════════════════════════════
EOF
