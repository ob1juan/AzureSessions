# Migration Demo Deployment & Directory Structure Guide

This document provides a comprehensive overview of the folder and file structure for the `migration_demo` environment, along with a mapping of how the deployment transitions from native Azure infrastructure to the nested Hyper-V virtual machines.

## Repository Folder Structure

The `migration_demo` directory is organized into three primary pillars: Azure Infrastructure, Orchestration Artifacts, and Hyper-V/OS Configurations.

```text
migration_demo/
├── azure/                    # Azure native infrastructure-as-code
│   ├── ARM/                  # ARM Templates (azuredeploy.json)
│   └── bicep/                # Bicep equivalents for Azure deployments
│
├── artifacts/                # Automated scripts, payloads, and wrappers
│   ├── Bootstrap.ps1         # Initial script run by Azure Custom Script Extension
│   ├── ArcServersLogonScript.ps1 # Primary orchestrator for nested VMs
│   ├── DeploymentStatus.ps1  # HTML report generator for deployment progress
│   ├── apim/                 # Azure API Management manifests and configs
│   ├── dsc/                  # Desired State Configuration (DSC) for Hyper-V/VMs
│   ├── iis/                  # IIS and legacy ASP.NET Web Forms payloads
│   ├── postgres/             # Ubuntu Bash scripts (Configure-Postgres.sh)
│   └── monitoring/           # Azure Monitor Workbook templates
│
└── hyper-v/                  # Hyper-V specific automation
    ├── host/                 # Configurations for the Hyper-V parent host
    ├── guests/               # Base layouts for the nested VMs (iis, sql, ubuntu)
    └── powershell/modules/   # Custom Jumpstart PowerShell modules
```

## Deployment Flow Mapping: Azure to Hyper-V Nested VMs

The deployment simulates an on-premises datacenter migrating to Azure. To achieve this, it relies on "nested virtualization," where an Azure VM acts as a Hyper-V host encapsulating multiple smaller VMs. 

Here is the step-by-step mapping of how the deployment flows from the cloud down to the nested on-premises workloads:

### Step 1: Azure Infrastructure Provisioning
1. **Trigger:** The user clicks "Deploy to Azure" and submits the ARM template (`azure/ARM/azuredeploy.json`).
2. **Azure Resources:** Azure provisions the base Network (VNet), Bastion, Storage, and the core **Client VM** (a Windows Server Azure VM that supports nested virtualization).
3. **Bridge to Host:** The ARM template adds a Custom Script Extension to the Client VM, injecting `Bootstrap.ps1` from the `artifacts/` folder to run upon VM creation.

### Step 2: Hyper-V Host Bootstrap 
1. **Execution Context:** Native Azure VM (Client VM).
2. **Action (`Bootstrap.ps1`):** 
   - Downloads the `artifacts/` folder payloads locally to `C:\ArcBox`.
   - Installs the Hyper-V Windows feature on the Client VM.
   - Configures the internal Hyper-V Virtual Switch so nested VMs can route traffic.
   - Restarts the Azure VM to finalize Hyper-V installation and triggers auto-logon.

### Step 3: Nested VM Provisioning & App Configuration
1. **Execution Context:** Client VM (now acting as the Hyper-V Host), running on user logon.
2. **Action (`ArcServersLogonScript.ps1`):**
   - **Infrastructure Provisioning:** Uses `SetupADDS.ps1` and `common.dsc.yml` to spin up Active Directory, and provisions the three nested Hyper-V guests:
     - `migdem-iis` (Windows Server + IIS)
     - `migdem-sql` (Windows Server + SQL Server)
     - `migdem-ubuntu` (Ubuntu Linux)
   - **Application Configuration:**
     - Connects to the **SQL VM** via PowerShell Direct, deploying the AdventureWorks database.
     - Connects to the **IIS VM** via PowerShell Direct, deploying the legacy ASP.NET Web Forms storefront.
     - Connects to the **Ubuntu VM** via SSH, transferring `Configure-Postgres.sh` to install Apache, PHP, and the PostgreSQL schema instance.

### Step 4: Azure Arc Hybrid Onboarding
1. **Execution Context:** Nested Hyper-V VMs.
2. **Action (`installArcAgent*.ps1 / .sh`):**
   - `ArcServersLogonScript.ps1` executes the Arc onboarding scripts inside each target VM.
   - The on-premises nested VMs authenticate using the Service Principal or Managed Identity provided during the ARM template deployment.
   - The VMs project themselves back into the Azure portal as **Azure Arc-enabled servers**, ready for Azure Migrate assessments and centralized Microsoft Defender/Monitor management.

---

### Summary
- **Azure ARM (`azuredeploy.json`)** gets you the Cloud environment and a bare metal "Datacenter" (Client VM).
- **Host Bootstrap (`Bootstrap.ps1`)** turns that bare metal into a Hyper-V Hypervisor.
- **Nested Orchestration (`ArcServersLogonScript.ps1`)** populates your datacenter with active VMs and Legacy Apps.
- **Arc Scripts** hook those legacy applications back into Azure for hybrid management and migration planning.