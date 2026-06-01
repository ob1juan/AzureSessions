
BeforeDiscovery {
    $namingPrefix = $env:namingPrefix
    $VMs = @("$namingPrefix-SQL", "$namingPrefix-Ubuntu")
    $null = Connect-AzAccount -Identity -Tenant $env:tenantId -Subscription $env:subscriptionId
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
    It "SQL website responds from ArcBox-SQL" {
        $ipAddress = (Get-VMNetworkAdapter -VMName "$namingPrefix-SQL").IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        $response = Invoke-WebRequest -Uri "http://$ipAddress/sql.aspx" -UseBasicParsing -TimeoutSec 30
        $response.Content | Should -Match 'SQL Server products'
    }

    It "PostgreSQL website responds from ArcBox-Ubuntu" {
        $ipAddress = (Get-VMNetworkAdapter -VMName "$namingPrefix-Ubuntu").IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        $response = Invoke-WebRequest -Uri "http://$ipAddress/" -UseBasicParsing -TimeoutSec 30
        $response.Content | Should -Match 'PostgreSQL widgets'
    }
}
