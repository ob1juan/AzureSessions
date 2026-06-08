# Lab 02: Environment Setup for the Migration Demo

Use this guide to deploy and validate the AzureSessions migration demo environment.

## Outcomes

- Deploy the migration demo infrastructure in Azure
- Validate Hyper-V nested VM readiness
- Confirm demo applications are reachable

## Prerequisites

- Completed Lab 01: Azure subscription ready
- Contributor or Owner permissions in the target subscription
- Enough regional quota for the lab VM sizes
- Public internet access to Azure endpoints

## Deployment Options

### Option A: Deploy from the README button

1. Open the deployment button in the repository README.
2. Fill the ARM template parameters.
3. Start the deployment and monitor in Resource Group > Deployments.

### Option B: Deploy with Azure CLI

```bash
az deployment sub create \
  --name migration-demo-deploy \
  --location <azure-region> \
  --template-file migration_demo/azure/ARM/azuredeploy.json \
  --parameters @migration_demo/azure/ARM/azuredeploy.parameters.json
```

Adjust parameters for your region, naming prefix, and environment constraints.

## Validate Host and Nested VMs

After deployment completes:

1. Connect to the host/client VM.
2. Open the desktop shortcut for deployment status:
   - Refresh Azure Deployment Status
3. Confirm component completion for:
   - Hyper-V network setup
   - Azure Migrate Appliance VM
   - ArcBox-SQL VM
   - ArcBox-Ubuntu VM
4. Confirm host file entries resolve nested VM names.

## Validate Demo Workloads

Check that the sample applications are available:

- SQL/IIS storefront endpoint (HTTPS)
- Ubuntu/PostgreSQL storefront endpoint (HTTPS)

Use the generated desktop shortcuts and the deployment status HTML report for current endpoints.

## Azure Migrate Appliance Access

The environment deploys an Azure Migrate appliance VM named:

- migdem-am

Open the appliance UI on the host using:

- https://migdem-am:44368/

## Notes

- The Azure Migrate appliance VM is intentionally not Arc-enabled.
- The appliance VHD is downloaded during deployment from Microsoft fwlink:
  - https://go.microsoft.com/fwlink/?linkid=2191848

## Troubleshooting

- If a component fails, rerun the logon script with forced components.
- Use the deployment status report to identify the failed component and message.
- Verify required providers are registered:

```bash
az provider show --namespace Microsoft.Migrate --query registrationState -o tsv
az provider show --namespace Microsoft.HybridCompute --query registrationState -o tsv
az provider show --namespace Microsoft.GuestConfiguration --query registrationState -o tsv
```
