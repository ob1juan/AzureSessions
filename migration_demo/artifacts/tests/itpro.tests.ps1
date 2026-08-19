
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

Describe "Azure managed modernization databases" {
    It "deploys an Azure SQL logical server and database" {
        $servers = @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Sql/servers')
        $databases = @(Get-AzResource -ResourceGroupName $env:resourceGroup -ResourceType 'Microsoft.Sql/servers/databases')
        $servers.Count | Should -BeGreaterThan 0
        $databases.Name | Should -Match '/AdventureWorks$'
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
