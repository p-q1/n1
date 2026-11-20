#!/bin/bash

main() {
    set -u

    if [ "$EUID" -ne 0 ]; then
        echo "ОШИБКА: скрипт должен запускаться от имени root (sudo -i)."
        return 1
    fi

    local ISP_ENS20="172.16.30.1/28"
    local ISP_ENS21="172.16.40.1/28"
    local HQ_RTR_ENS19="172.16.30.2/28"
    local HQ_RTR_VLAN100="192.168.100.1/27"
    local HQ_RTR_VLAN200="192.168.200.1/28"
    local HQ_RTR_VLAN999="192.168.99.1/29"
    local HQ_RTR_GRE="10.10.10.1 peer 10.10.10.2"
    local BR_RTR_ENS19="172.16.40.2/28"
    local BR_RTR_ENS20="192.168.30.1/30"
    local BR_RTR_GRE="10.10.10.2 peer 10.10.10.1"
    local BR_FW_ENS19="192.168.30.2/30"
    local BR_FW_ENS20="192.168.0.1/28"
    local HQ_SRV_ADDR="192.168.100.2/27"
    local BR_SRV_ADDR="192.168.0.2/28"
    local HQ_CLI_NET="192.168.200.0/28"
    local SSH_PORT="2027"
    local OSPF_PASS="P@ssw0rd"
    local TZ="Europe/Moscow"

    hist() { 
        history -s "$1" 2>/dev/null || true
        echo "$1" >> "$HOME/.bash_history"
    }
    run() { eval "$1"; hist "$1"; }
    ask() { local p="$1" d="$2" v; read -r -p "$p [$d]: " v; echo "${v:-$d}"; }

    clear
    echo "=== Выбор машины ==="
    local MACHINE
    select MACHINE in ISP HQ-RTR BR-RTR BR-FW HQ-SRV BR-SRV HQ-CLI; do
        [ -n "$MACHINE" ] && break
    done
    echo "Выбрано: $MACHINE"

    case "$MACHINE" in
        ISP)
            ISP_ENS20=$(ask "ISP ens20 (->HQ)" "$ISP_ENS20")
            ISP_ENS21=$(ask "ISP ens21 (->BR)" "$ISP_ENS21")
            ;;
        HQ-RTR)
            HQ_RTR_ENS19=$(ask "HQ-RTR ens19 (->ISP)" "$HQ_RTR_ENS19")
            HQ_RTR_VLAN100=$(ask "HQ-RTR vlan100" "$HQ_RTR_VLAN100")
            HQ_RTR_VLAN200=$(ask "HQ-RTR vlan200" "$HQ_RTR_VLAN200")
            HQ_RTR_VLAN999=$(ask "HQ-RTR vlan999" "$HQ_RTR_VLAN999")
            HQ_RTR_GRE=$(ask "HQ-RTR gre1 ipv4address" "$HQ_RTR_GRE")
            SSH_PORT=$(ask "Порт SSH" "$SSH_PORT")
            ;;
        BR-RTR)
            BR_RTR_ENS19=$(ask "BR-RTR ens19 (->ISP)" "$BR_RTR_ENS19")
            BR_RTR_ENS20=$(ask "BR-RTR ens20 (->BR-FW)" "$BR_RTR_ENS20")
            BR_RTR_GRE=$(ask "BR-RTR gre1 ipv4address" "$BR_RTR_GRE")
            SSH_PORT=$(ask "Порт SSH" "$SSH_PORT")
            ;;
        BR-FW)
            BR_FW_ENS19=$(ask "BR-FW ens19 (->BR-RTR)" "$BR_FW_ENS19")
            BR_FW_ENS20=$(ask "BR-FW ens20 (->BR-SRV)" "$BR_FW_ENS20")
            ;;
        HQ-SRV)
            HQ_SRV_ADDR=$(ask "HQ-SRV vlan100" "$HQ_SRV_ADDR")
            SSH_PORT=$(ask "Порт SSH" "$SSH_PORT")
            ;;
        BR-SRV)
            BR_SRV_ADDR=$(ask "BR-SRV ens19" "$BR_SRV_ADDR")
            SSH_PORT=$(ask "Порт SSH" "$SSH_PORT")
            ;;
        HQ-CLI)
            HQ_CLI_NET=$(ask "HQ-CLI сеть (DHCP)" "$HQ_CLI_NET")
            ;;
    esac
    TZ=$(ask "Часовой пояс" "$TZ")

    _opts_static() {
        cat > "$1/options" <<EOF
TYPE=eth
BOOTPROTO=static
CONFIG_IPV4=yes
ONBOOT=yes
DISABLED=no
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=no
EOF
    }
    _opts_dhcp() {
        cat > "$1/options" <<EOF
TYPE=eth
BOOTPROTO=dhcp
CONFIG_IPV4=yes
ONBOOT=yes
DISABLED=no
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=no
EOF
    }
    _opts_noip() {
        cat > "$1/options" <<EOF
TYPE=eth
BOOTPROTO=static
CONFIG_IPV4=no
ONBOOT=yes
DISABLED=no
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=no
EOF
    }

    setup_iface_static() {
        local iface="$1" addr="$2" gw="${3:-}"
        local d="/etc/net/ifaces/$iface"
        mkdir -p "$d"
        _opts_static "$d"
        echo "$addr" > "$d/ipv4address"
        if [ -n "$gw" ]; then
            echo "default via $gw" > "$d/ipv4route"
        else
            rm -f "$d/ipv4route"
        fi
        hist "nano /etc/net/ifaces/$iface/ipv4address"
    }

    setup_iface_trunk() {
        local iface="$1"
        local d="/etc/net/ifaces/$iface"
        mkdir -p "$d"
        _opts_noip "$d"
    }

    setup_iface_vlan() {
        local iface="$1" parent="$2" vid="$3" addr="${4:-}" gw="${5:-}" proto="${6:-static}"
        local d="/etc/net/ifaces/$iface"
        mkdir -p "$d"
        cat > "$d/options" <<EOF
TYPE=vlan
HOST=$parent
VID=$vid
BOOTPROTO=$proto
CONFIG_IPV4=yes
ONBOOT=yes
DISABLED=no
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=no
EOF
        if [ "$proto" = "static" ] && [ -n "$addr" ]; then
            echo "$addr" > "$d/ipv4address"
            if [ -n "$gw" ]; then
                echo "default via $gw" > "$d/ipv4route"
            fi
        fi
        hist "nano /etc/net/ifaces/$iface/options"
        hist "nano /etc/net/ifaces/$iface/ipv4address"
    }

    setup_iface_gre() {
        local iface="$1" local_ip="$2" remote_ip="$3" addr="$4"
        local d="/etc/net/ifaces/$iface"
        mkdir -p "$d"
        cat > "$d/options" <<EOF
TUNLOCAL=$local_ip
TUNREMOTE=$remote_ip
TUNTYPE=gre
TYPE=iptun
TUNTTL=64
TUNMTU=1476
TUNOPTIONS='ttl 64'
DISABLE=no
EOF
        echo "$addr" > "$d/ipv4address"
        hist "nano /etc/net/ifaces/$iface/options"
        hist "nano /etc/net/ifaces/$iface/ipv4address"
    }

    restart_network() {
        echo ">>> systemctl restart network"
        systemctl restart network 2>&1 || true
        sleep 2
        echo ">>> ip -br a"
        ip -br a
    }

    enable_ip_forward() {
        for f in /etc/net/sysctl.conf /etc/sysctl.conf; do
            if [ -f "$f" ] && grep -q '^[[:space:]]*net.ipv4.ip_forward' "$f"; then
                sed -i -E 's/^[[:space:]]*net\.ipv4\.ip_forward.*/net.ipv4.ip_forward = 1/' "$f"
            else
                echo 'net.ipv4.ip_forward = 1' >> "$f"
            fi
        done
        sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
        sysctl -p /etc/net/sysctl.conf >/dev/null 2>&1 || true
        hist "nano /etc/net/sysctl.conf"
        hist "sysctl -p"
    }

    setup_nat() {
        local out_iface="$1"
        enable_ip_forward
        iptables -I INPUT -p 47 -j ACCEPT 2>/dev/null || true
        iptables -I FORWARD -p 47 -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p 89 -j ACCEPT 2>/dev/null || true
        iptables -I FORWARD -p 89 -j ACCEPT 2>/dev/null || true
        run "iptables -t nat -A POSTROUTING -o $out_iface -j MASQUERADE"
        run "iptables -P FORWARD ACCEPT"
        run "iptables-save > /etc/sysconfig/iptables"
        run "systemctl enable --now iptables"
    }

    setup_sudo_user() {
        local user="$1" uid="$2" group="$3"
        if [ -n "$uid" ]; then
            useradd -u "$uid" -m -s /bin/bash "$user" 2>/dev/null || true
        else
            useradd -m -s /bin/bash "$user" 2>/dev/null || true
        fi
        echo "$user:P@ssw0rd" | chpasswd
        usermod -aG "$group" "$user"
        echo "$user ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$user"
        chmod 0440 "/etc/sudoers.d/$user"
        hist "useradd -u $uid -m -s /bin/bash $user"
        hist "passwd $user"
        hist "usermod -aG $group $user"
        hist "echo '$user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$user"
    }

    setup_ssh() {
        local port="$1" user="$2"
        echo 'Authorized access only' > /etc/openssh/banner
        sed -i -E '/^[[:space:]]*#?[[:space:]]*(Port|MaxAuthTries|Banner|AllowUsers)([[:space:]]|$)/d' /etc/openssh/sshd_config
        cat >> /etc/openssh/sshd_config <<EOF
Port $port
MaxAuthTries 2
Banner /etc/openssh/banner
AllowUsers $user
EOF
        if sshd -t 2>/tmp/sshd_err; then
            run "systemctl restart sshd"
        else
            echo "Ошибка в sshd_config:"
            cat /tmp/sshd_err
        fi
        hist "nano /etc/openssh/sshd_config"
    }

    setup_ospf() {
        local role="$1"
        sed -i 's/^zebra=no/zebra=yes/' /etc/frr/daemons
        sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons

        if [ "$role" = "hq-rtr" ]; then
            cat > /etc/frr/frr.conf <<EOF
frr version 8.0
frr defaults traditional
hostname hq-rtr
no ipv6 forwarding
service integrated-vtysh-config
!
interface gre1
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
 ip ospf network point-to-point
 ip ospf mtu-ignore
 no ip ospf passive
!
router ospf
 ospf router-id 10.10.10.1
 passive-interface default
 network 10.10.10.0/30 area 0
 network 192.168.100.0/27 area 0
 network 192.168.200.0/28 area 0
!
line vty
!
EOF
        elif [ "$role" = "br-rtr" ]; then
            cat > /etc/frr/frr.conf <<EOF
frr version 8.0
frr defaults traditional
hostname br-rtr
no ipv6 forwarding
service integrated-vtysh-config
!
interface gre1
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
 ip ospf network point-to-point
 ip ospf mtu-ignore
 no ip ospf passive
!
interface ens20
 ip ospf network point-to-point
 no ip ospf passive
!
router ospf
 ospf router-id 10.10.10.2
 passive-interface default
 network 10.10.10.0/30 area 0
 network 192.168.30.0/30 area 0
!
line vty
!
EOF
        elif [ "$role" = "br-fw" ]; then
            cat > /etc/frr/frr.conf <<EOF
frr version 8.0
frr defaults traditional
hostname br-fw
no ipv6 forwarding
service integrated-vtysh-config
!
interface ens19
 ip ospf network point-to-point
 no ip ospf passive
!
router ospf
 ospf router-id 192.168.30.2
 passive-interface default
 network 192.168.30.0/30 area 0
 network 192.168.0.0/28 area 0
!
line vty
!
EOF
        fi
        chown frr:frr /etc/frr/frr.conf
        chmod 640 /etc/frr/frr.conf
        run "systemctl enable --now frr"
        run "systemctl restart frr"
        sleep 3
        hist "nano /etc/frr/frr.conf"
    }

    setup_ovs_bridge() {
        run "systemctl enable --now openvswitch"
        sleep 2
        ovs-vsctl --may-exist add-br hq-sw
        ovs-vsctl --may-exist add-port hq-sw ens20
        ovs-vsctl --may-exist add-port hq-sw ens21
        ovs-vsctl --may-exist add-port hq-sw vlan100 -- set Interface vlan100 type=internal
        ovs-vsctl --may-exist add-port hq-sw vlan200 -- set Interface vlan200 type=internal
        ovs-vsctl --may-exist add-port hq-sw vlan999 -- set Interface vlan999 type=internal
        ovs-vsctl set Port ens20 vlan_mode=trunk trunks=100
        ovs-vsctl set Port ens21 vlan_mode=trunk trunks=200
        ovs-vsctl set Port vlan100 vlan_mode=access tag=100
        ovs-vsctl set Port vlan200 vlan_mode=access tag=200
        ovs-vsctl set Port vlan999 vlan_mode=access tag=999
        hist "ovs-vsctl show"
    }

    setup_dhcp() {
        mkdir -p /etc/dhcp /var/lib/dhcpd /var/lib/dhcp
        touch /var/lib/dhcpd/dhcpd.leases /var/lib/dhcp/dhcpd.leases
        chown -R dhcpd:dhcpd /var/lib/dhcpd /var/lib/dhcp 2>/dev/null || true

        cat > /etc/dhcp/dhcpd.conf <<EOF
ddns-update-style none;
authoritative;
subnet 192.168.200.0 netmask 255.255.255.240 {
    option routers 192.168.200.1;
    option subnet-mask 255.255.255.240;
    option domain-name "au-team.irpo";
    option domain-name-servers 192.168.100.2;
    range dynamic-bootp 192.168.200.2 192.168.200.10;
}
EOF
        echo 'DHCPDARGS=vlan200' > /etc/sysconfig/dhcpd
        
        for i in {1..15}; do
            ip link show vlan200 &>/dev/null && break
            sleep 1
        done
        ip link set vlan200 up 2>/dev/null || true
        ip addr add 192.168.200.1/28 dev vlan200 2>/dev/null || true
        
        run "dhcpd -t -cf /etc/dhcp/dhcpd.conf"
        run "systemctl enable --now dhcpd"
        hist "nano /etc/dhcp/dhcpd.conf"
        hist "nano /etc/sysconfig/dhcpd"
    }

    setup_dns() {
        local CHROOT_DIR="/var/lib/bind"
        local BDIR="$CHROOT_DIR/etc"
        mkdir -p "$BDIR/zone"

        rm -f "$BDIR/rndc.key"
        rndc-confgen -a -c "$BDIR/rndc.key" >/dev/null 2>&1
        if [ -f "$BDIR/rndc.key" ]; then
            sed -i 's/^#//g' "$BDIR/rndc.key"
            chown root:named "$BDIR/rndc.key" 2>/dev/null || true
            chmod 640 "$BDIR/rndc.key"
        fi

        if [ -f "$BDIR/options.conf" ]; then
            if ! grep -q 'dnssec-validation' "$BDIR/options.conf"; then
                sed -i '/options {/a \    dnssec-validation no;\n    listen-on port 53 { any; };\n    listen-on-v6 port 53 { any; };\n    allow-query { any; };\n    recursion yes;\n    forwarders { 8.8.8.8; };' "$BDIR/options.conf"
            fi
        fi

        cat > "$BDIR/zones.conf" <<EOF
zone "au-team.irpo" { type master; file "/etc/zone/au-team.irpo"; };
zone "100.168.192.in-addr.arpa" { type master; file "/etc/zone/100.168.192.rev"; };
zone "0.168.192.in-addr.arpa" { type master; file "/etc/zone/0.168.192.rev"; };
EOF

        cat > "$BDIR/zone/au-team.irpo" <<EOF
\$TTL 1D
@   IN  SOA ns.au-team.irpo. admin.au-team.irpo. (
        2024010101 12H 1H 1W 1D )
    IN  NS  ns.au-team.irpo.
ns      IN  A   192.168.100.2
hq-rtr  IN  A   192.168.100.1
br-rtr  IN  A   192.168.30.1
br-fw   IN  A   192.168.30.2
hq-srv  IN  A   192.168.100.2
hq-cli  IN  A   192.168.200.2
br-srv  IN  A   192.168.0.2
docker  IN  A   172.16.30.1
web     IN  A   172.16.40.1
EOF

        cat > "$BDIR/zone/100.168.192.rev" <<EOF
\$TTL 1D
@   IN  SOA ns.au-team.irpo. admin.au-team.irpo. (
        2024010101 12H 1H 1W 1D )
    IN  NS  ns.au-team.irpo.
1   IN  PTR hq-rtr.au-team.irpo.
2   IN  PTR hq-srv.au-team.irpo.
EOF

        cat > "$BDIR/zone/0.168.192.rev" <<EOF
\$TTL 1D
@   IN  SOA ns.au-team.irpo. admin.au-team.irpo. (
        2024010101 12H 1H 1W 1D )
    IN  NS  ns.au-team.irpo.
1   IN  PTR br-fw.au-team.irpo.
2   IN  PTR br-srv.au-team.irpo.
EOF

        chown root:named "$BDIR/zone/"* 2>/dev/null || true
        chmod 640 "$BDIR/zone/"*
        chown root:named "$BDIR/zones.conf" 2>/dev/null || true
        chmod 640 "$BDIR/zones.conf"

        if [ -f /etc/named.conf ]; then
            sed -i '/include "\/var\/lib\/bind\/etc\/zones.conf";/d' /etc/named.conf
            sed -i '/include "\/etc\/zones.conf";/d' /etc/named.conf
            echo 'include "/etc/zones.conf";' >> /etc/named.conf
        fi

        echo "nameserver 127.0.0.1" > /etc/net/ifaces/vlan100/resolv.conf
        echo "nameserver 8.8.8.8" >> /etc/net/ifaces/vlan100/resolv.conf
        echo "nameserver 127.0.0.1" > /etc/resolv.conf

        run "named-checkconf /etc/named.conf"
        run "systemctl enable --now bind"
        hist "nano /etc/named.conf"
        hist "nano /var/lib/bind/etc/options.conf"
        hist "nano /var/lib/bind/etc/zones.conf"
    }

    setup_timezone() {
        timedatectl set-timezone "$TZ" 2>/dev/null || ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
        hist "timedatectl set-timezone $TZ"
    }

    setup_isp() {
        run "hostnamectl set-hostname isp.au-team.irpo"
        setup_iface_static ens20 "$ISP_ENS20"
        setup_iface_static ens21 "$ISP_ENS21"
        echo "nameserver 8.8.8.8" > /etc/net/ifaces/ens19/resolv.conf
        restart_network
        setup_nat ens19
        setup_timezone
    }

    setup_hq_rtr() {
        run "hostnamectl set-hostname hq-rtr.au-team.irpo"
        setup_iface_static ens19 "$HQ_RTR_ENS19" "172.16.30.1"
        echo "nameserver 8.8.8.8" > /etc/net/ifaces/ens19/resolv.conf
        setup_iface_trunk ens20
        setup_iface_trunk ens21
        setup_ovs_bridge
        mkdir -p /etc/net/ifaces/hq-sw
        _opts_noip /etc/net/ifaces/hq-sw
        setup_iface_vlan vlan100 ens20 100 "$HQ_RTR_VLAN100"
        setup_iface_vlan vlan200 ens21 200 "$HQ_RTR_VLAN200"
        setup_iface_vlan vlan999 ens20 999 "$HQ_RTR_VLAN999"
        setup_iface_gre gre1 "172.16.30.2" "172.16.40.2" "$HQ_RTR_GRE"
        restart_network
        setup_nat ens19
        setup_sudo_user net_admin "" wheel
        setup_ssh "$SSH_PORT" net_admin
        setup_ospf hq-rtr
        setup_dhcp
        setup_timezone
    }

    setup_br_rtr() {
        run "hostnamectl set-hostname br-rtr.au-team.irpo"
        setup_iface_static ens19 "$BR_RTR_ENS19" "172.16.40.1"
        echo "nameserver 8.8.8.8" > /etc/net/ifaces/ens19/resolv.conf
        setup_iface_static ens20 "$BR_RTR_ENS20"
        setup_iface_gre gre1 "172.16.40.2" "172.16.30.2" "$BR_RTR_GRE"
        restart_network
        setup_nat ens19
        setup_sudo_user net_admin "" wheel
        setup_ssh "$SSH_PORT" net_admin
        setup_ospf br-rtr
        setup_timezone
    }

    setup_br_fw() {
        run "hostnamectl set-hostname br-fw.au-team.irpo"
        setup_iface_static ens19 "$BR_FW_ENS19" "192.168.30.1"
        echo "nameserver 8.8.8.8" > /etc/net/ifaces/ens19/resolv.conf
        setup_iface_static ens20 "$BR_FW_ENS20"
        restart_network
        setup_nat ens19
        setup_ospf br-fw
        setup_timezone
    }

    setup_hq_srv() {
        run "hostnamectl set-hostname hq-srv.au-team.irpo"
        setup_iface_trunk ens19
        setup_iface_vlan vlan100 ens19 100 "$HQ_SRV_ADDR" "192.168.100.1" "static"
        restart_network
        setup_sudo_user sshuser 2027 wheel
        setup_ssh "$SSH_PORT" sshuser
        setup_dns
        setup_timezone
    }

    setup_br_srv() {
        run "hostnamectl set-hostname br-srv.au-team.irpo"
        setup_iface_static ens19 "$BR_SRV_ADDR" "192.168.0.1"
        echo "nameserver 192.168.100.2" > /etc/net/ifaces/ens19/resolv.conf
        restart_network
        setup_sudo_user sshuser 2027 wheel
        setup_ssh "$SSH_PORT" sshuser
        setup_timezone
    }

    setup_hq_cli() {
        run "hostnamectl set-hostname hq-cli.au-team.irpo"
        setup_iface_trunk ens19
        setup_iface_vlan vlan200 ens19 200 "" "" "dhcp"
        restart_network
        setup_timezone
    }

    case "$MACHINE" in
        ISP)      setup_isp ;;
        HQ-RTR)   setup_hq_rtr ;;
        BR-RTR)   setup_br_rtr ;;
        BR-FW)    setup_br_fw ;;
        HQ-SRV)   setup_hq_srv ;;
        BR-SRV)   setup_br_srv ;;
        HQ-CLI)   setup_hq_cli ;;
    esac

    echo ""
    echo "========== ИТОГ =========="
    ip -br a 2>/dev/null || true
    ss -tlnp 2>/dev/null | grep ":$SSH_PORT" || echo "SSH не слушает $SSH_PORT"
    if command -v vtysh &>/dev/null; then
        vtysh -c 'show ip ospf neighbor' 2>/dev/null || true
    fi

    echo ""
    echo "Сохранение истории и очистка команды запуска..."
    
    history -a 
    
    if [ -f "$HOME/.bash_history" ]; then
        sed -i -E '/(curl|clck\.ru|source[[:space:]]+<\(|exam\.sh|githubusercontent|ini\.sh|bash[[:space:]]+<)/d' "$HOME/.bash_history"
    fi
    
    history -c
    history -r "$HOME/.bash_history"

    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo " НАСТРОЙКА ЗАВЕРШЕНА. СИСТЕМА БУДЕТ ПЕРЕЗАГРУЖЕНА ЧЕРЕЗ 3 СЕКУНД."
    echo "════════════════════════════════════════════════════════════════"
    sync
    sleep 3
    reboot
}

main "$@"
