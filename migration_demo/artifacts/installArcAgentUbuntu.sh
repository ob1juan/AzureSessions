#!/bin/sh
set -e

log() { echo "[installArcAgentUbuntu] $*"; }

# -----------------------------------------------------------------------------
# Wait until first-boot package activity has finished and the apt/dpkg locks are
# free. On a freshly booted Ubuntu image cloud-init and unattended-upgrades hold
# /var/lib/dpkg/lock-frontend and /var/lib/apt/lists/lock for several minutes.
# The Azure Arc installer (install_linux_azcmagent.sh) only waits 5 minutes for
# those locks and then aborts WITHOUT installing the agent, which is why the
# later 'azcmagent connect' fails with exit code 127 (azcmagent: not found).
# Waiting here first makes the install reliable.
# -----------------------------------------------------------------------------
wait_for_apt() {
    timeout_seconds="${1:-900}"
    deadline=$(( $(date +%s) + timeout_seconds ))

    # Let cloud-init finish its package work if the helper is present.
    if command -v cloud-init >/dev/null 2>&1; then
        log 'Waiting for cloud-init to finish (best effort)'
        sudo cloud-init status --wait >/dev/null 2>&1 || true
    fi

    log 'Waiting for apt/dpkg locks to be released'
    while true; do
        lock_busy=0
        for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock; do
            if sudo fuser "${lock}" >/dev/null 2>&1; then
                lock_busy=1
                break
            fi
        done

        # Also wait out any running apt/dpkg/unattended-upgrade processes.
        if [ "${lock_busy}" -eq 0 ]; then
            if pgrep -x apt >/dev/null 2>&1 || pgrep -x apt-get >/dev/null 2>&1 || \
               pgrep -x dpkg >/dev/null 2>&1 || pgrep -f unattended-upgrade >/dev/null 2>&1; then
                lock_busy=1
            fi
        fi

        if [ "${lock_busy}" -eq 0 ]; then
            log 'apt/dpkg locks are free.'
            return 0
        fi

        if [ "$(date +%s)" -ge "${deadline}" ]; then
            log "WARNING: apt/dpkg still busy after ${timeout_seconds}s; continuing anyway."
            return 0
        fi

        log 'apt/dpkg is busy; waiting 15s...'
        sleep 15
    done
}

# Block Azure IMDS
sudo ufw --force enable
sudo ufw deny out from any to 169.254.169.254
sudo ufw default allow incoming

# Make sure no first-boot package activity is holding the apt/dpkg locks.
wait_for_apt 900

# Download the installation package
wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh # 2>/dev/null

# Install the hybrid agent. Retry a few times in case a late unattended-upgrade
# run grabs the lock again between wait_for_apt and the install.
install_ok=0
i=1
while [ "${i}" -le 3 ]; do
    log "Installing the Azure Connected Machine agent (attempt ${i}/3)"
    if bash ~/install_linux_azcmagent.sh; then
        install_ok=1
        break
    fi
    log 'Agent install attempt failed; waiting for apt/dpkg locks before retrying.'
    wait_for_apt 900
    i=$(( i + 1 ))
done

# Verify the agent actually installed before attempting to connect, so failures
# surface here with a clear message instead of a confusing 'azcmagent: not found'.
if ! command -v azcmagent >/dev/null 2>&1; then
    echo "ERROR: azcmagent was not installed (install_ok=${install_ok}). The Azure Connected Machine agent installer could not complete, most likely because apt/dpkg was still busy." >&2
    exit 1
fi

ArcServerResourceName=$(hostname |sed -e "s/\b\(.\)/\u\1/g")

# Run connect command
azcmagent connect --access-token $accessToken --resource-group $resourceGroup --tenant-id $tenantId --location $Azurelocation --subscription-id $subscriptionId --resource-name "${ArcServerResourceName}" --cloud "AzureCloud" --correlation-id "d009f5dd-dba8-4ac7-bac9-b54ef3a6671a"
