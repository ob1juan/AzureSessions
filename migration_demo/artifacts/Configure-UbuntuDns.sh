#!/usr/bin/env bash
set -euo pipefail

# Configure-UbuntuDns.sh
# -----------------------------------------------------------------------------
# Sets DNS resolvers directly on the nested Ubuntu VM.
#
# The Hyper-V InternalNAT DHCP scope on the host is supposed to hand DNS to the
# guest via DHCP option 6, but that intermittently does not reach this Ubuntu
# image: /etc/resolv.conf ends up empty and name resolution fails completely
# (breaking apt, Azure Arc onboarding, and the app stacks). Rather than rely on
# DHCP delivering DNS, this script configures the resolvers deterministically
# inside the guest using three complementary mechanisms so that resolution works
# immediately and survives reboots:
#   1. A systemd-resolved drop-in (the resolver manager on this image).
#   2. A netplan drop-in so the configuration is persistent and the link ignores
#      any (missing/incorrect) DNS handed out by DHCP.
#   3. A guaranteed-working /etc/resolv.conf written right now.
#
# Env vars (all optional):
#   DNS_SERVERS  Space- or comma-separated resolver IPs, in priority order.
#                Defaults to the Azure platform DNS followed by public resolvers.
#   DNS_SEARCH   Optional DNS search/suffix domain.
# -----------------------------------------------------------------------------

DNS_SERVERS="${DNS_SERVERS:-168.63.129.16 1.1.1.1 8.8.8.8}"
DNS_SEARCH="${DNS_SEARCH:-}"

# Normalize: allow comma- or space-separated input, collapse whitespace, and
# fall back to sane defaults if the caller passed an empty/blank value.
DNS_SERVERS="$(printf '%s' "${DNS_SERVERS}" | tr ',' ' ' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
if [ -z "${DNS_SERVERS}" ]; then
    DNS_SERVERS="168.63.129.16 1.1.1.1 8.8.8.8"
fi

log() { echo "[Configure-UbuntuDns] $*"; }

log "Requested DNS servers: ${DNS_SERVERS}"
[ -n "${DNS_SEARCH}" ] && log "Search domain: ${DNS_SEARCH}"

# Basic validation: every entry must look like an IPv4 address.
for s in ${DNS_SERVERS}; do
    if ! printf '%s' "${s}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "Invalid DNS server '${s}' in DNS_SERVERS" >&2
        exit 1
    fi
done

# -----------------------------------------------------------------------------
# 1) Configure systemd-resolved (the DNS manager on this Ubuntu image).
# -----------------------------------------------------------------------------
if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-resolved\.service'; then
    log 'Configuring systemd-resolved drop-in'
    sudo mkdir -p /etc/systemd/resolved.conf.d
    {
        echo '[Resolve]'
        echo "DNS=${DNS_SERVERS}"
        echo 'FallbackDNS=1.1.1.1 8.8.8.8'
        [ -n "${DNS_SEARCH}" ] && echo "Domains=${DNS_SEARCH}"
    } | sudo tee /etc/systemd/resolved.conf.d/arcbox-dns.conf >/dev/null
    sudo systemctl enable systemd-resolved >/dev/null 2>&1 || true
    sudo systemctl restart systemd-resolved || log 'WARNING: failed to restart systemd-resolved; continuing.'
fi

# -----------------------------------------------------------------------------
# 2) Persist the configuration in netplan and stop the link from using DHCP DNS.
# -----------------------------------------------------------------------------
PRIMARY_IFACE="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -n1)"
if [ -z "${PRIMARY_IFACE}" ]; then
    PRIMARY_IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '$2 !~ /^lo/ {print $2; exit}')"
fi
log "Primary interface: ${PRIMARY_IFACE:-unknown}"

if [ -n "${PRIMARY_IFACE}" ] && [ -d /etc/netplan ]; then
    NP_ADDR="$(printf '%s' "${DNS_SERVERS}" | tr ' ' ',')"
    log 'Writing netplan drop-in /etc/netplan/99-arcbox-dns.yaml'
    {
        echo 'network:'
        echo '  version: 2'
        echo '  ethernets:'
        echo "    ${PRIMARY_IFACE}:"
        echo '      dhcp4: true'
        echo '      dhcp4-overrides:'
        echo '        use-dns: false'
        echo '      nameservers:'
        echo "        addresses: [${NP_ADDR}]"
        [ -n "${DNS_SEARCH}" ] && echo "        search: [${DNS_SEARCH}]"
    } | sudo tee /etc/netplan/99-arcbox-dns.yaml >/dev/null
    sudo chmod 600 /etc/netplan/99-arcbox-dns.yaml
    log 'Applying netplan configuration'
    sudo netplan apply || log 'WARNING: netplan apply reported an error; continuing.'
fi

# -----------------------------------------------------------------------------
# 3) Guarantee a working /etc/resolv.conf right now.
#    When systemd-resolved is active, point resolv.conf at its real upstream
#    resolver list (not the 127.0.0.53 stub) so glibc queries the resolvers
#    directly. Otherwise, write a static file that nothing else manages.
# -----------------------------------------------------------------------------
if systemctl is-active --quiet systemd-resolved 2>/dev/null && [ -e /run/systemd/resolve/resolv.conf ]; then
    log 'Pointing /etc/resolv.conf at the systemd-resolved upstream resolver list'
    sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
else
    log 'Writing a static /etc/resolv.conf'
    sudo rm -f /etc/resolv.conf
    {
        for s in ${DNS_SERVERS}; do echo "nameserver ${s}"; done
        [ -n "${DNS_SEARCH}" ] && echo "search ${DNS_SEARCH}"
        echo 'options timeout:2 attempts:2'
    } | sudo tee /etc/resolv.conf >/dev/null
fi

log 'Effective /etc/resolv.conf:'
{ cat /etc/resolv.conf 2>/dev/null || sudo cat /etc/resolv.conf 2>/dev/null; } || true

# -----------------------------------------------------------------------------
# 4) Verify resolution actually works before reporting success.
# -----------------------------------------------------------------------------
log 'Verifying DNS resolution'
resolved_ok=0
for host in management.azure.com archive.ubuntu.com login.microsoftonline.com; do
    if getent hosts "${host}" >/dev/null 2>&1; then
        log "Resolved ${host} successfully."
        resolved_ok=1
        break
    fi
    log "Could not resolve ${host} yet; trying the next host."
done

if [ "${resolved_ok}" -ne 1 ]; then
    log 'ERROR: DNS resolution still failing after configuration.'
    exit 1
fi

log 'DNS configuration complete.'
