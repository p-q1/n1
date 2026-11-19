#!/bin/bash
# t.sh — исправленная и полная версия для Alt Server (минимальная сборка)
# Запуск: bash t.sh

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "Совет: запускайте через 'source', чтобы команды попадали в историю."
fi

main() {
    set -u

    # ============================================================
    # 0. Проверка утилит и прав
    # ============================================================
    if [ "$EUID" -ne 0 ]; then
        echo "ОШИБКА: скрипт должен запускаться от имени root (sudo -i)."
        return 1
    fi

    local REQUIRED=(ip iptables sysctl hostnamectl timedatectl useradd usermod \
                    chpasswd sshd curl sed grep awk cat echo mkdir cp chmod chown \
                    ln systemctl ping ss)
    local MISSING=()
    local c
    for c in "${REQUIRED[@]}"; do
        command -v "$c" &>/dev/null || MISSING+=("$c")
    done
    if [ ${#MISSING[@]} -gt 0 ]; then
        echo "══════════════════════════════════════════════════════════════"
        echo " ОШИБКА: не найдены утилиты:"
        printf '  - %s\n' "${MISSING[@]}"
        echo " Установите пакеты: apt-get update && apt-get install -y \\"
        echo "   iproute2 iptables bind bind-utils dhcp-server frr \\"
        echo "   openssh-server sudo systemd-timesyncd iputils procps openvswitch"
        echo "══════════════════════════════════════════════════════════════"
        return 1
    fi
    echo "✓ Все утилиты найдены"

    # ============================================================
    # 1. Параметры по умолчанию
    # ============================================================
    local ISP_ENS20="172.16.30.1/28"
    local ISP_ENS21="172.16.40.1/28"
    local HQ_RTR_ENS19="172.16.30.2/28"
    local HQ_RTR_VLAN100="192.168.100.1/27"
    local HQ_RTR_VLAN200="192.168.200.1/28"
    local HQ_RTR_VLAN999="192.168.99.1/29"
    local HQ_RTR_GRE="10.10.10.1/30"
    local BR_RTR_ENS19="172.16.40.2/28"
    local BR_RTR_ENS20="192.168.30.1/30"
    local BR_RTR_GRE="10.10.10.2/30"
    local BR_FW_ENS19="192.168.30.2/30"
    local BR_FW_ENS20="192.168.0.1/28"
    local HQ_SRV_ADDR="192.168.100.2/27"
    local BR_SRV_ADDR="192.168.0.2/28"
    local HQ_CLI_NET="192.168.200.0/28"
    local SSH_PORT="2027"
    local OSPF_PASS="P@ssw0rd"
    local TZ="Europe/Moscow"

    # ============================================================
    # 2. Хелперы
    # ============================================================
    ask() { local p="$1" d="$2" v; read -r -p "$p [$d]: " v; echo "${v:-$d}"; }
    run() { eval "$1"; history -s "$1" 2>/dev/null || true; }
    hist() { history -s "$1" 2>/dev/null || true; }

    # ============================================================
    # 3. Выбор машины
    # ============================================================
    clear
    echo "=== Выбор машины ==="
    local MACHINE
    select MACHINE in ISP HQ-RTR BR-RTR BR-FW HQ-SRV BR-SRV HQ-CLI; do
        [ -n "$MACHINE" ] && break
    done
    echo "Выбрано: $MACHINE"

    # ============================================================
    # 4. Ввод параметров
    # ============================================================
    case "$MACHINE" in
        ISP)
            ISP_ENS20=$(ask "ISP ens20 (→HQ)" "$ISP_ENS20")
            ISP_ENS21=$(ask "ISP ens21 (→BR)" "$ISP_ENS21")
            ;;
        HQ-RTR)
            HQ_RTR_ENS19=$(ask "HQ-RTR ens19 (→ISP)" "$HQ_RTR_ENS19")
            HQ_RTR_VLAN100=$(ask "HQ-RTR vlan100" "$HQ_RTR_VLAN100")
            HQ_RTR_VLAN200=$(ask "HQ-RTR vlan200" "$HQ_RTR_VLAN200")
            HQ_RTR_VLAN999=$(ask "HQ-RTR vlan999" "$HQ_RTR_VLAN999")
            HQ_RTR_GRE=$(ask "HQ-RTR gre1" "$HQ_RTR_GRE")
            SSH_PORT=$(ask "Порт SSH" "$SSH_PORT")
            ;;
        BR-RTR)
            BR_RTR_ENS19=$(ask "BR-RTR ens19 (→ISP)" "$BR_RTR_ENS19")
            BR_RTR_ENS20=$(ask "BR-RTR ens20 (→BR-FW)" "$BR_RTR_ENS20")
            BR_RTR_GRE=$(ask "BR-RTR gre1" "$BR_RTR_GRE")
            SSH_PORT=$(ask "Порт SSH" "$SSH_PORT")
            ;;
        BR-FW)
            BR_FW_ENS19=$(ask "BR-FW ens19 (→BR-RTR)" "$BR_FW_ENS19")
            BR_FW_ENS20=$(ask "BR-FW ens20 (→BR-SRV)" "$BR_FW_ENS20")
            ;;
        HQ-SRV)
            HQ_SRV_ADDR=$(ask "HQ-SRV ens19" "$HQ_SRV_ADDR")
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

    # ============================================================
    # 5. Функции настройки etcnet (ПОЛНЫЕ ФАЙЛЫ OPTIONS)
    # ============================================================
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

    setup_iface_vlan_ip() {
        local iface="$1" addr="$2"
        local d="/etc/net/ifaces/$iface"
        mkdir -p "$d"
        _opts_static "$d"
        echo "$addr" > "$d/ipv4address"
        hist "nano /etc/net/ifaces/$iface/ipv4address"
    }

    setup_iface_dhcp() {
        local iface="$1"
        local d="/etc/net/ifaces/$iface"
        mkdir -p "$d"
        _opts_dhcp "$d"
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
        echo "$addr peer $remote_ip" > "$d/ipv4address"
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
    }

    setup_nat() {
        local out_iface="$1"
        enable_ip_forward
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
            echo "✗ ОШИБКА в sshd_config:"
            cat /tmp/sshd_err
        fi
    }

    # ============================================================
    # 6. Setup OSPF (FRR)
    # ============================================================
    setup_ospf() {
        local role="$1"

        [ -f /etc/frr/daemons ] || { echo "✗ /etc/frr/daemons не найден"; return 1; }
        sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
        run "systemctl enable --now frr"
        run "systemctl restart frr"

        local i=0
        while ! vtysh -c 'show version' &>/dev/null && [ $i -lt 15 ]; do
            sleep 1; i=$((i+1))
        done
        if ! vtysh -c 'show version' &>/dev/null; then
            echo "✗ vtysh не отвечает — OSPF не настроен"
            return 1
        fi

        case "$role" in
            hq-rtr)
                run "vtysh -c 'conf t' \
                    -c 'router ospf' \
                    -c 'passive-interface default' \
                    -c 'network 10.10.10.0/30 area 0' \
                    -c 'network 192.168.100.0/27 area 0' \
                    -c 'network 192.168.200.0/28 area 0' \
                    -c 'int gre1' \
                    -c 'no ip ospf passive' \
                    -c 'ip ospf authentication message-digest' \
                    -c 'ip ospf message-digest-key 1 md5 $OSPF_PASS' \
                    -c 'ip ospf network point-to-point' \
                    -c 'end'"
                ;;
            br-rtr)
                run "vtysh -c 'conf t' \
                    -c 'router ospf' \
                    -c 'passive-interface default' \
                    -c 'network 10.10.10.0/30 area 0' \
                    -c 'network 192.168.30.0/30 area 0' \
                    -c 'int gre1' \
                    -c 'no ip ospf passive' \
                    -c 'ip ospf authentication message-digest' \
                    -c 'ip ospf message-digest-key 1 md5 $OSPF_PASS' \
                    -c 'ip ospf network point-to-point' \
                    -c 'int ens20' \
                    -c 'no ip ospf passive' \
                    -c 'ip ospf network point-to-point' \
                    -c 'end'"
                ;;
            br-fw)
                # На BR-FW без аутентификации, как в гайде
                run "vtysh -c 'conf t' \
                    -c 'router ospf' \
                    -c 'passive-interface default' \
                    -c 'network 192.168.30.0/30 area 0' \
                    -c 'network 192.168.0.0/28 area 0' \
                    -c 'int ens19' \
                    -c 'no ip ospf passive' \
                    -c 'ip ospf network point-to-point' \
                    -c 'end'"
                ;;
        esac
        run "vtysh -c 'write memory'"
    }

    # ============================================================
    # 7. OVS-мост (HQ-RTR)
    # ============================================================
    setup_ovs_bridge() {
        run "systemctl enable --now openvswitch"
        sleep 2

        ovs-vsctl --may-exist add-br hq-sw
        ovs-vsctl --may-exist add-port hq-sw ens20
        ovs-vsctl --may-exist add-port hq-sw ens21
        
        ovs-vsctl --may-exist add-port hq-sw vlan100 -- set Interface vlan100 type=internal
        ovs-vsctl --may-exist add-port hq-sw vlan200 -- set Interface vlan200 type=internal
        ovs-vsctl --may-exist add-port hq-sw vlan999 -- set Interface vlan999 type=internal
        
        ovs-vsctl set Port ens20 vlan_mode=access tag=100
        ovs-vsctl set Port ens21 vlan_mode=access tag=200
        ovs-vsctl set Port vlan100 vlan_mode=access tag=100
        ovs-vsctl set Port vlan200 vlan_mode=access tag=200
        ovs-vsctl set Port vlan999 vlan_mode=access tag=999

        hist "ovs-vsctl show"
    }

    # ============================================================
    # 8. DHCP Server (HQ-RTR)
    # ============================================================
    setup_dhcp() {
        # Создаем директорию и файл аренды, иначе dhcpd упадёт
        mkdir -p /var/lib/dhcpd
        touch /var/lib/dhcpd/dhcpd.leases
        chown -R dhcpd:dhcpd /var/lib/dhcpd 2>/dev/null || chown -R root:root /var/lib/dhcpd

        cat > /etc/dhcp/dhcpd.conf <<EOF
ddns-update-style none;
subnet $HQ_CLI_NET netmask 255.255.255.240 {
    option routers 192.168.200.1;
    option subnet-mask 255.255.255.240;
    option domain-name "au-team.irpo";
    option domain-name-servers 192.168.100.2;
    range dynamic-bootp 192.168.200.2 192.168.200.10;
}
EOF
        echo 'DHCPDARGS=vlan200' > /etc/sysconfig/dhcpd
        
        # Ждем появления vlan200, чтобы dhcpd успешно стартовал
        for i in {1..10}; do
            ip link show vlan200 &>/dev/null && break
            sleep 1
        done

        run "systemctl enable --now dhcpd"
        hist "nano /etc/dhcp/dhcpd.conf"
    }

    # ============================================================
    # 9. BIND (HQ-SRV)
    # ============================================================
    setup_dns() {
        echo "nameserver 8.8.8.8" > /etc/resolv.conf

        local BDIR="/var/lib/bind/etc"
        mkdir -p "$BDIR/zone"

        # Создаем стандартные зоны, которых не хватает и из-за которых падает bind
        cat > "$BDIR/zone/localhost.rev" <<EOF
\$TTL 1D
@   IN  SOA localhost. root.localhost. (
        2024010101 12H 1H 1W 1D )
    IN  NS  localhost.
1   IN  PTR localhost.
EOF

        cat > "$BDIR/zone/127.in-addr.arpa" <<EOF
\$TTL 1D
@   IN  SOA localhost. root.localhost. (
        2024010101 12H 1H 1W 1D )
    IN  NS  localhost.
1   IN  PTR localhost.
EOF

        cat > "$BDIR/zone/0.in-addr.arpa" <<EOF
\$TTL 1D
@   IN  SOA localhost. root.localhost. (
        2024010101 12H 1H 1W 1D )
    IN  NS  localhost.
EOF

        cat > "$BDIR/zone/255.in-addr.arpa" <<EOF
\$TTL 1D
@   IN  SOA localhost. root.localhost. (
        2024010101 12H 1H 1W 1D )
    IN  NS  localhost.
EOF

        # Основной options.conf
        cat > "$BDIR/options.conf" <<EOF
options {
    directory "$BDIR";
    recursion yes;
    allow-query { any; };
    forwarders { 8.8.8.8; };
    listen-on { any; };
    listen-on-v6 { any; };
};

zone "." IN {
    type hint;
    file "/etc/bind/db.root";
};

zone "localhost" IN {
    type master;
    file "$BDIR/zone/localhost.rev";
};

zone "127.in-addr.arpa" IN {
    type master;
    file "$BDIR/zone/127.in-addr.arpa";
};

zone "0.in-addr.arpa" IN {
    type master;
    file "$BDIR/zone/0.in-addr.arpa";
};

zone "255.in-addr.arpa" IN {
    type master;
    file "$BDIR/zone/255.in-addr.arpa";
};

zone "au-team.irpo" {
    type master;
    file "$BDIR/zone/au-team.irpo";
};
zone "100.168.192.in-addr.arpa" {
    type master;
    file "$BDIR/zone/100.168.192.rev";
};
zone "0.168.192.in-addr.arpa" {
    type master;
    file "$BDIR/zone/0.168.192.rev";
};
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

        # Подключаем options.conf в основной конфиг
        if [ -f /etc/named.conf ]; then
            if ! grep -q 'include "/var/lib/bind/etc/options.conf";' /etc/named.conf; then
                echo 'include "/var/lib/bind/etc/options.conf";' >> /etc/named.conf
            fi
        fi

        named-checkconf /etc/named.conf 2>/dev/null || true
        run "systemctl enable --now bind"
        echo "nameserver 192.168.100.2" > /etc/resolv.conf
        hist "nano /var/lib/bind/etc/options.conf"
    }

    setup_timezone() {
        timedatectl set-timezone "$TZ" 2>/dev/null || ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
    }

    # ============================================================
    # 10. Setup-функции по машинам
    # ============================================================
    setup_isp() {
        run "hostnamectl set-hostname isp.au-team.irpo"
        setup_iface_static ens20 "$ISP_ENS20"
        setup_iface_static ens21 "$ISP_ENS21"
        restart_network
        setup_nat ens19
        setup_timezone
    }

    setup_hq_rtr() {
        run "hostnamectl set-hostname hq-rtr.au-team.irpo"
        setup_iface_static ens19 "$HQ_RTR_ENS19" "172.16.30.1"
        setup_iface_trunk ens20
        setup_iface_trunk ens21
        
        setup_ovs_bridge

        mkdir -p /etc/net/ifaces/hq-sw
        _opts_static /etc/net/ifaces/hq-sw
        setup_iface_vlan_ip vlan100 "$HQ_RTR_VLAN100"
        setup_iface_vlan_ip vlan200 "$HQ_RTR_VLAN200"
        setup_iface_vlan_ip vlan999 "$HQ_RTR_VLAN999"

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
        setup_iface_static ens20 "$BR_FW_ENS20"
        restart_network
        setup_nat ens19
        setup_ospf br-fw
        setup_timezone
    }

    setup_hq_srv() {
        run "hostnamectl set-hostname hq-srv.au-team.irpo"
        setup_iface_static ens19 "$HQ_SRV_ADDR" "192.168.100.1"
        restart_network
        setup_sudo_user sshuser 2027 wheel
        setup_ssh "$SSH_PORT" sshuser
        setup_dns
        setup_timezone
    }

    setup_br_srv() {
        run "hostnamectl set-hostname br-srv.au-team.irpo"
        setup_iface_static ens19 "$BR_SRV_ADDR" "192.168.0.1"
        restart_network
        setup_sudo_user sshuser 2027 wheel
        setup_ssh "$SSH_PORT" sshuser
        setup_timezone
    }

    setup_hq_cli() {
        run "hostnamectl set-hostname hq-cli.au-team.irpo"
        setup_iface_dhcp ens19
        restart_network
        setup_timezone
    }

    # ============================================================
    # 11. Запуск настройки
    # ============================================================
    case "$MACHINE" in
        ISP)      setup_isp ;;
        HQ-RTR)   setup_hq_rtr ;;
        BR-RTR)   setup_br_rtr ;;
        BR-FW)    setup_br_fw ;;
        HQ-SRV)   setup_hq_srv ;;
        BR-SRV)   setup_br_srv ;;
        HQ-CLI)   setup_hq_cli ;;
    esac

    # ============================================================
    # 12. Итоговая диагностика
    # ============================================================
    echo ""
    echo "========== ИТОГ =========="
    ip -br a 2>/dev/null || true
    ss -tlnp 2>/dev/null | grep ":$SSH_PORT" || echo "SSH не слушает $SSH_PORT"
    if command -v vtysh &>/dev/null; then
        vtysh -c 'show ip ospf neighbor' 2>/dev/null || true
    fi

    # ============================================================
    # 13. Очистка истории (надежная)
    # ============================================================
    echo ""
    echo "Очистка истории..."
    history -c
    if [ -f ~/.bash_history ]; then
        sed -i -E '/(curl|clck\.ru|source|exam\.sh|bash <|githubusercontent|ini\.sh)/d' ~/.bash_history
        sed -i -E '/^z([0-9]+|x)[[:space:]]*$/d' ~/.bash_history
    fi
    history -w 2>/dev/null || true

    echo "=== Настройка завершена ==="
}

main "$@"
