BeforeDiscovery {

    $null = Connect-AzAccount -Identity -Tenant $env:tenantId -Subscription $env:subscriptionId

}

Describe "ArcBox resource group" {
    BeforeAll {
        $ResourceGroupName = $env:resourceGroup
    }
    It "should have deployed resources" {
        (Get-AzResource -ResourceGroupName $ResourceGroupName).count | Should -BeGreaterThan 0
    }
}
