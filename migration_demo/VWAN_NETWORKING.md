# Azure Virtual WAN and Hyper-V private networking

The migration demo connects its simulated on-premises Hyper-V network to Azure through a secured Azure Virtual WAN hub.

## Address plan

| Network | Prefix | Purpose |
| --- | --- | --- |
| Azure migration-demo VNet | `10.16.0.0/16` | Azure host VM, Bastion, and private endpoints |
| Azure Virtual WAN hub | `10.20.0.0/23` | Managed virtual hub infrastructure |
| Hyper-V internal network | `10.10.1.0/24` | Nested SQL, Ubuntu, and appliance VMs |
| Ubuntu VPN endpoint | `10.10.1.102` | Hyper-V next hop and strongSwan endpoint |

The prefixes must not overlap. Change `virtualHubAddressPrefix` at deployment time if `10.20.0.0/23` conflicts with another connected network.

## Traffic flow

1. The nested Windows workload sends `10.16.0.0/16` traffic to `10.10.1.102` through a persistent guest route.
2. Ubuntu forwards the packet into an IKEv2/IPsec tunnel terminated by the Azure Virtual WAN VPN gateway.
3. The Windows Hyper-V host translates the outer IKE/IPsec NAT-T traffic and exposes UDP 500/4500 through its dedicated public IP.
4. The Virtual WAN hub learns `10.10.1.0/24` from the VPN site and advertises it to the connected Azure VNet.
5. Virtual hub routing intent sends private branch-to-VNet traffic through Azure Firewall Standard. The firewall policy allows only the two configured private prefixes in either direction.

The Azure VNet does not need a user-defined route table for the Hyper-V prefix. Routing intent manages the hub connection's route-table association and propagation, so the deployment deliberately leaves those optional connection fields empty. The Azure VM NIC has IP forwarding enabled for the nested endpoint scenario.

The host VM's static instance-level public IP is both the configured VPN-site address and the outbound address for IKEv2/IPsec. The host subnet therefore does not use an Azure NAT Gateway. Attaching a subnet NAT Gateway would change the tunnel's outbound source while inbound UDP 500/4500 still targets the VM public IP, causing asymmetric VPN traffic.

## VPN protocol

Azure Virtual WAN site-to-site VPN supports IKEv1/IKEv2 IPsec, not OpenVPN. The Ubuntu VM therefore uses strongSwan with IKEv2, AES-256, SHA-256, DH group 14, and PFS group 14 for the actual site-to-site tunnel.

The deployment also installs and enables the OpenVPN service on Ubuntu so it is available for optional lab extensions. OpenVPN is not used as the transport to Azure Virtual WAN. Using OpenVPN as the Azure-facing protocol would require a separate Virtual WAN point-to-site design and would not advertise the Hyper-V subnet as a site-to-site branch.

## Provisioned Azure resources

- Standard Azure Virtual WAN
- Standard Virtual WAN hub with routing-intent-managed connection associations and propagation
- Azure Firewall Standard in the secured virtual hub
- Firewall policy and bidirectional private-prefix network rules
- Virtual hub private-traffic routing intent
- Virtual WAN VPN gateway
- VPN site and IKEv2/IPsec connection for `10.10.1.0/24`
- Hub connection to the migration-demo Azure VNet
- Dedicated public IP, symmetric instance-level egress, and NSG rules for the Hyper-V host VPN endpoint

## Secrets

The template automatically derives a stable, deployment-specific key from Azure-generated random key material, so the deployment form does not request a VPN shared key. Bootstrap stores the value in Key Vault as `vwanVpnSharedKey` and saves it to `Virtual WAN VPN Shared Key.txt` on the Hyper-V host's shared desktop. The host retrieves the Key Vault secret while configuring Ubuntu and transfers it through the existing SSH session in a temporary mode-600 file.

Do not put the pre-shared key in documentation, logs, or source control. Delete the desktop copy when it is no longer needed.

## Validation

On the Hyper-V host, open the deployment status report and confirm **Hyper-V to Azure vWAN VPN** is complete. The integration tests additionally verify that:

- the Virtual WAN, hub, firewall, VPN gateway, site, and connection exist;
- the generated shared key exists in Key Vault and matches the host desktop copy;
- the firewall is Standard, private routing intent is present, and the host subnet has no NAT Gateway override;
- UDP 500/4500 map to the reserved Ubuntu endpoint and Linux forwarding is enabled;
- strongSwan reports the `azure-vwan` connection as established;
- OpenVPN is enabled for optional use; and
- the nested SQL VM has a persistent route to the Azure VNet through Ubuntu.

If the tunnel is down, verify that Ubuntu still owns `10.10.1.102`, UDP 500 and 4500 are allowed to the host VPN public IP, the Hyper-V NAT mappings target `10.10.1.102`, and the Azure VPN gateway has completed provisioning. Force-rerun the **Hyper-V to Azure vWAN VPN** component after correcting the issue.

## Cost

Azure Firewall, the Virtual WAN hub, and the Virtual WAN VPN gateway accrue hourly charges even when little traffic crosses the lab. Delete the demo resource group when the exercise is complete.
