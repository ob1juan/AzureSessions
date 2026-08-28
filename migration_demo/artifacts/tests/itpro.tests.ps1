
BeforeDiscovery {
    $namingPrefix = $env:namingPrefix
    $VMs = @("$namingPrefix-SQL", "$namingPrefix-pgsql")
    $null = Connect-AzAccount -Identity -Tenant $env:tenantId -Subscription $env:subscriptionId
}

Describe "Hyper-V host Azure Arc connection" {
    It "Azure Arc Connected Machine exists and is connected" {
        $connectedMachine = Get-AzConnectedMachine -Name $env:COMPUTERNAME -ResourceGroupName $env:resourceGroup -SubscriptionId $env:subscriptionId
        $connectedMachine | Should -Not -BeNullOrEmpty
        $connectedMachine.Status | Should -Be "Connected"
    }
}

Describe "Azure resource providers" {
    It "Microsoft.DataMigration is registered" {
        (Get-AzResourceProvider -ProviderNamespace 'Microsoft.DataMigration').RegistrationState | Should -Be 'Registered'
    }
}

Describe "Azure Virtual WAN hybrid network" {
    It "deploys the Virtual WAN and secured virtual hub" {
        @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Network/virtualWans').Count | Should -Be 1
        @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Network/virtualHubs').Count | Should -Be 1
        $firewall = Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Network/azureFirewalls' -ExpandProperties
        @($firewall).Count | Should -Be 1
        $firewall.Properties.sku.tier | Should -Be 'Standard'
        @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Network/virtualHubs/routingIntent').Count | Should -Be 1
        @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections').Count | Should -Be 1
    }

    It "deploys the site-to-site VPN gateway, site, and connection" {
        @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Network/vpnGateways').Count | Should -Be 1
        @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Network/vpnSites').Count | Should -Be 1
        @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Network/vpnGateways/vpnConnections').Count | Should -Be 1
    }

    It "uses the host public IP symmetrically without a subnet NAT Gateway" {
        $hostNic = Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Network/networkInterfaces' -Name "$($env:namingPrefix)-Host-NIC" -ExpandProperties
        $hostNic.Properties.enableIPForwarding | Should -BeTrue
        $hostNic.Properties.ipConfigurations[0].properties.publicIPAddress.id | Should -Not -BeNullOrEmpty

        $vnet = Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Network/virtualNetworks' -Name "$($env:namingPrefix)-VNet" -ExpandProperties
        $hostSubnet = $vnet.Properties.subnets | Where-Object { $_.name -eq "$($env:namingPrefix)-Subnet" } | Select-Object -First 1
        $hostSubnet | Should -Not -BeNullOrEmpty
        $hostSubnet.properties.natGateway | Should -BeNullOrEmpty
    }
}

# Assert that the Hyper-V virtual machines in $VMs exists, are running and connected as Azure Arc-enabled servers

Describe "<vm>" -ForEach $VMs {
    BeforeAll {
        $vm = $_
    }
    It "VM exists" {
        $vmobject = Get-VM -Name $vm
        $vmobject | Should -Not -BeNullOrEmpty
    }
    It "VM is running" {
        $vmobject = Get-VM -Name $vm
        $vmobject.State | Should -Be "Running"
    }
    It "Azure Arc Connected Machine exists" {
        $connectedMachine = Get-AzConnectedMachine -Name $vm -ResourceGroupName $env:resourceGroup -SubscriptionId $env:subscriptionId
        $connectedMachine | Should -Not -BeNullOrEmpty
    }
    It "Azure Arc Connected Machine is connected" {
        $connectedMachine = Get-AzConnectedMachine -Name $vm -ResourceGroupName $env:resourceGroup -SubscriptionId $env:subscriptionId
        $connectedMachine.Status | Should -Be "Connected"
    }
}

Describe "ArcBox demo websites" {
    It "SQL website responds from the SQL VM" {
        $sqlVmName = "$($env:namingPrefix)-SQL"
        $ipAddress = (Get-VMNetworkAdapter -VMName $sqlVmName).IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        $response = Invoke-WebRequest -Uri "http://$ipAddress/sql.aspx" -UseBasicParsing -TimeoutSec 30
        $response.Content | Should -Match 'SQL Server products|AdventureWorks'
    }

    It "PostgreSQL website responds from the Ubuntu VM" {
        $ubuntuVmName = "$($env:namingPrefix)-pgsql"
        $ipAddress = (Get-VMNetworkAdapter -VMName $ubuntuVmName).IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        $response = Invoke-WebRequest -Uri "http://$ipAddress/" -UseBasicParsing -TimeoutSec 30
        $response.Content | Should -Match 'PostgreSQL AdventureWorks storefront'
    }
}

Describe "Hyper-V host guest command-line access" {
    BeforeAll {
        $connectScript = 'C:\ArcBox\Connect-ArcBoxVm.ps1'
    }

    It "deploys the guest connection command" {
        $connectScript | Should -Exist
    }

    It "authenticates to the Windows SQL VM with PowerShell Direct" {
        $result = & $connectScript -Target Windows -Command '$env:COMPUTERNAME'
        $result | Should -Contain "$($env:namingPrefix)-SQL"
    }

    It "authenticates to the Linux PostgreSQL VM with SSH" {
        $result = & $connectScript -Target Linux -Command 'hostname'
        $result | Should -Contain "$($env:namingPrefix)-pgsql"
    }
}

Describe "Hyper-V private routing through Azure Virtual WAN" {
    BeforeAll {
        $connectScript = 'C:\ArcBox\Connect-ArcBoxVm.ps1'
    }

    It "establishes the Ubuntu strongSwan tunnel" {
        $status = & $connectScript -Target Linux -Command 'sudo ipsec status azure-vwan'
        $status -join "`n" | Should -Match 'ESTABLISHED'
    }

    It "reserves the Ubuntu gateway address and forwards IPsec NAT-T to it" {
        $ubuntuAddresses = (Get-VMNetworkAdapter -VMName "$($env:namingPrefix)-pgsql").IPAddresses
        $ubuntuAddresses | Should -Contain $env:ubuntuVpnGatewayIp

        foreach ($port in @(500, 4500)) {
            $mapping = @(Get-NetNatStaticMapping -NatName 'InternalNat' -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Protocol -eq 'UDP' -and
                    $_.ExternalPort -eq $port -and
                    [string]$_.InternalIPAddress -eq $env:ubuntuVpnGatewayIp -and
                    $_.InternalPort -eq $port
                })
            $mapping.Count | Should -Be 1
        }
    }

    It "enables Linux forwarding between the private networks" {
        $status = & $connectScript -Target Linux -Command 'sysctl -n net.ipv4.ip_forward'
        $status | Should -Contain '1'
    }

    It "enables OpenVPN for optional lab use" {
        $status = & $connectScript -Target Linux -Command 'systemctl is-enabled openvpn.service'
        $status | Should -Contain 'enabled'
    }

    It "adds a persistent Azure VNet route to the SQL VM" {
        $destinationPrefix = $env:azureVnetAddressPrefix
        $nextHop = $env:ubuntuVpnGatewayIp
        $route = Invoke-Command -VMName "$($env:namingPrefix)-SQL" -ScriptBlock {
            Get-NetRoute -PolicyStore PersistentStore -DestinationPrefix $using:destinationPrefix -ErrorAction SilentlyContinue |
                Where-Object { $_.NextHop -eq $using:nextHop } |
                Select-Object -First 1
        } -Credential (New-Object System.Management.Automation.PSCredential('Administrator', (ConvertTo-SecureString 'JS123!!' -AsPlainText -Force)))
        $route | Should -Not -BeNullOrEmpty
    }
}

Describe "Azure managed modernization databases" {
    It "deploys an Azure SQL logical server and database" {
        $servers = @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Sql/servers')
        $databases = @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Sql/servers/databases')
        $servers.Count | Should -BeGreaterThan 0
        $databases.Name | Should -Match '/AdventureWorksLT2022$'
    }

    It "deploys an Azure Database for PostgreSQL flexible server and database" {
        $servers = @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.DBforPostgreSQL/flexibleServers')
        $databases = @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.DBforPostgreSQL/flexibleServers/databases')
        $servers.Count | Should -BeGreaterThan 0
        $databases.Name | Should -Match '/adventureworks$'
    }

    It "publishes endpoints and stores the shared administrator credential" {
        $env:azureSqlServerFqdn | Should -Not -BeNullOrEmpty
        $env:azurePostgresqlServerFqdn | Should -Not -BeNullOrEmpty
        Get-Secret -Name managedDatabaseAdminUsername | Should -Not -BeNullOrEmpty
        Get-Secret -Name managedDatabaseAdminPassword | Should -Not -BeNullOrEmpty
    }
}
