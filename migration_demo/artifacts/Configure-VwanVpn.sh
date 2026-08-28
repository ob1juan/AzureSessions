#!/usr/bin/env bash
set -euo pipefail

# Configures the nested Ubuntu VM as the IKEv2/IPsec endpoint for Azure Virtual WAN.
# Azure Virtual WAN site-to-site connections do not support the OpenVPN protocol, so
# strongSwan terminates the site-to-site tunnel. The OpenVPN package/service is also
# installed and enabled for optional lab use, but it is not the vWAN tunnel transport.

VPN_SHARED_KEY_FILE="${VPN_SHARED_KEY_FILE:-}"
VPN_SITE_PUBLIC_IP="${VPN_SITE_PUBLIC_IP:-}"
VPN_GATEWAY_PUBLIC_IP="${VPN_GATEWAY_PUBLIC_IP:-}"
HYPERV_NETWORK_PREFIX="${HYPERV_NETWORK_PREFIX:-10.10.1.0/24}"
AZURE_NETWORK_PREFIX="${AZURE_NETWORK_PREFIX:-10.16.0.0/16}"

log() { echo "[Configure-VwanVpn] $*"; }
fail() { echo "[Configure-VwanVpn] ERROR: $*" >&2; exit 1; }

is_ipv4() {
    local ip="$1"
    local octet
    IFS='.' read -r -a octets <<<"${ip}"
    [ "${#octets[@]}" -eq 4 ] || return 1
    for octet in "${octets[@]}"; do
        [[ "${octet}" =~ ^[0-9]+$ ]] || return 1
        [ "${octet}" -ge 0 ] && [ "${octet}" -le 255 ] || return 1
    done
}

is_ipv4_cidr() {
    local value="$1"
    local ip="${value%/*}"
    local prefix="${value#*/}"
    [ "${ip}" != "${prefix}" ] || return 1
    is_ipv4 "${ip}" || return 1
    [[ "${prefix}" =~ ^[0-9]+$ ]] && [ "${prefix}" -ge 0 ] && [ "${prefix}" -le 32 ]
}

[ -n "${VPN_SHARED_KEY_FILE}" ] || fail 'VPN_SHARED_KEY_FILE is required.'
[ -f "${VPN_SHARED_KEY_FILE}" ] || fail "Shared-key file not found: ${VPN_SHARED_KEY_FILE}"
is_ipv4 "${VPN_SITE_PUBLIC_IP}" || fail "Invalid VPN_SITE_PUBLIC_IP: ${VPN_SITE_PUBLIC_IP}"
is_ipv4 "${VPN_GATEWAY_PUBLIC_IP}" || fail "Invalid VPN_GATEWAY_PUBLIC_IP: ${VPN_GATEWAY_PUBLIC_IP}"
is_ipv4_cidr "${HYPERV_NETWORK_PREFIX}" || fail "Invalid HYPERV_NETWORK_PREFIX: ${HYPERV_NETWORK_PREFIX}"
is_ipv4_cidr "${AZURE_NETWORK_PREFIX}" || fail "Invalid AZURE_NETWORK_PREFIX: ${AZURE_NETWORK_PREFIX}"

VPN_SHARED_KEY="$(tr -d '\r\n' <"${VPN_SHARED_KEY_FILE}")"
rm -f "${VPN_SHARED_KEY_FILE}"
[ -n "${VPN_SHARED_KEY}" ] || fail 'The VPN shared key is empty.'
trap 'VPN_SHARED_KEY=""' EXIT

log 'Installing strongSwan and OpenVPN packages.'
export DEBIAN_FRONTEND=noninteractive
printf '%s\n' \
    'iptables-persistent iptables-persistent/autosave_v4 boolean true' \
    'iptables-persistent iptables-persistent/autosave_v6 boolean true' |
    sudo debconf-set-selections
sudo apt-get update -y
sudo apt-get install -y strongswan openvpn iptables-persistent

log 'Enabling IPv4 forwarding for the Hyper-V private network.'
sudo tee /etc/sysctl.d/99-arcbox-vwan.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOF
sudo sysctl --system >/dev/null

log 'Writing the strongSwan IKEv2/IPsec configuration.'
sudo tee /etc/ipsec.conf >/dev/null <<EOF
config setup
    uniqueids=no

conn azure-vwan
    auto=start
    type=tunnel
    keyexchange=ikev2
    authby=psk
    left=%defaultroute
    leftid=${VPN_SITE_PUBLIC_IP}
    leftsubnet=${HYPERV_NETWORK_PREFIX}
    right=${VPN_GATEWAY_PUBLIC_IP}
    rightid=%any
    rightsubnet=${AZURE_NETWORK_PREFIX}
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256-modp2048!
    ikelifetime=28800s
    lifetime=27000s
    rekeymargin=3m
    keyingtries=%forever
    dpddelay=30s
    dpdtimeout=120s
    dpdaction=restart
    forceencaps=yes
    mobike=no
EOF

ESCAPED_SHARED_KEY="${VPN_SHARED_KEY//\\/\\\\}"
ESCAPED_SHARED_KEY="${ESCAPED_SHARED_KEY//\"/\\\"}"
printf '%s %%any : PSK "%s"\n' "${VPN_SITE_PUBLIC_IP}" "${ESCAPED_SHARED_KEY}" |
    sudo tee /etc/ipsec.secrets >/dev/null
sudo chmod 600 /etc/ipsec.secrets
VPN_SHARED_KEY=''
ESCAPED_SHARED_KEY=''

log 'Allowing forwarded private traffic between Hyper-V and Azure.'
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow 500/udp >/dev/null
    sudo ufw allow 4500/udp >/dev/null
    sudo ufw route allow from "${HYPERV_NETWORK_PREFIX}" to "${AZURE_NETWORK_PREFIX}" >/dev/null
    sudo ufw route allow from "${AZURE_NETWORK_PREFIX}" to "${HYPERV_NETWORK_PREFIX}" >/dev/null
fi
if ! sudo iptables -C FORWARD -s "${HYPERV_NETWORK_PREFIX}" -d "${AZURE_NETWORK_PREFIX}" -j ACCEPT 2>/dev/null; then
    sudo iptables -I FORWARD 1 -s "${HYPERV_NETWORK_PREFIX}" -d "${AZURE_NETWORK_PREFIX}" -j ACCEPT
fi
if ! sudo iptables -C FORWARD -s "${AZURE_NETWORK_PREFIX}" -d "${HYPERV_NETWORK_PREFIX}" -j ACCEPT 2>/dev/null; then
    sudo iptables -I FORWARD 1 -s "${AZURE_NETWORK_PREFIX}" -d "${HYPERV_NETWORK_PREFIX}" -j ACCEPT
fi
if ! sudo iptables -t mangle -C FORWARD -s "${HYPERV_NETWORK_PREFIX}" -d "${AZURE_NETWORK_PREFIX}" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
    sudo iptables -t mangle -A FORWARD -s "${HYPERV_NETWORK_PREFIX}" -d "${AZURE_NETWORK_PREFIX}" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
fi
if ! sudo iptables -t mangle -C FORWARD -s "${AZURE_NETWORK_PREFIX}" -d "${HYPERV_NETWORK_PREFIX}" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
    sudo iptables -t mangle -A FORWARD -s "${AZURE_NETWORK_PREFIX}" -d "${HYPERV_NETWORK_PREFIX}" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
fi
sudo netfilter-persistent save >/dev/null

log 'Enabling the IPsec and OpenVPN services.'
sudo systemctl enable strongswan-starter.service
sudo systemctl restart strongswan-starter.service
if systemctl list-unit-files openvpn.service >/dev/null 2>&1; then
    sudo systemctl enable openvpn.service
fi

log "Waiting for the Azure vWAN tunnel to establish through ${VPN_GATEWAY_PUBLIC_IP}."
for attempt in $(seq 1 30); do
    if sudo ipsec status azure-vwan 2>/dev/null | grep -q 'ESTABLISHED'; then
        log 'Azure vWAN IKEv2/IPsec tunnel is established.'
        sudo ipsec status azure-vwan
        exit 0
    fi
    log "Tunnel is not established yet (attempt ${attempt} of 30)."
    sleep 10
done

sudo ipsec statusall || true
fail 'The Azure vWAN tunnel did not establish within five minutes.'
