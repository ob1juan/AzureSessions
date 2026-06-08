# AzureSessions

This repository contains working assets used for SLED Azure Enablement Sessions, with a focus on Azure Arc scenarios and hands-on deployment content.

## Getting Started Lab Path

Use the guided lab sequence below to run the full demo from a new subscription through migration and modernization outcomes:

1. [Lab 01 - Azure Trial Subscription](migration_demo/lab_guides/01-azure-trial-subscription.md)
2. [Lab 02 - Environment Setup](migration_demo/lab_guides/02-environment-setup.md)
3. [Lab 03 - Azure Migrate Assessment (VMs and Databases)](migration_demo/lab_guides/03-azure-migrate-assessment.md)
4. [Lab 04 - Azure Migrate Migration (VMs and Databases)](migration_demo/lab_guides/04-azure-migrate-migration.md)
5. [Lab 05 - Web App Modernization](migration_demo/lab_guides/05-web-app-modernization.md)

Each lab guide is written to be runnable independently, but the best experience is to follow them in order.

## Architecture and Migration Demo

This repository provisions a full-scale Hybrid Cloud environment to demonstrate assessment and modernization using **Azure Migrate** and **Azure Arc**.

The architecture uses a Hyper-V host to simulate a legacy on-premises datacenter. Within this host, nested virtual machines run traditional multi-tier applications:
- **Windows Server (IIS)**: Hosting a legacy ASP.NET Web Forms storefront.
- **Windows Server (SQL)**: Hosting the Microsoft SQL Server AdventureWorks database.
- **Ubuntu Linux**: Hosting a PHP commerce interface backed by a PostgreSQL database.

### Why Hyper-V?
By leveraging Hyper-V to run native nested VMs, this environment accurately replicates an **on-premises datacenter**. This allows us to effectively demonstrate the full lifecycle of a migration journey using **Azure Migrate**:
1. **Discovery & Assessment**: Deploying the Azure Migrate appliance to the Hyper-V host to discover the live VMs, capture performance data, assess cloud readiness, and calculate sizing/costs.
2. **Replication & Migration**: Showing how Azure Migrate securely replicates these running workloads from the Hyper-V host directly into Azure without application downtime.
3. **Hybrid Management**: Onboarding the on-premises servers into Azure Arc for unified management, Defender for SQL, and monitoring alongside native cloud resources.

### Architecture Diagram

```mermaid
graph TD
    subgraph Azure Cloud
        Arc[Azure Arc]
        Migrate[Azure Migrate]
        Monitor[Azure Monitor / Log Analytics]
        APIM[Azure API Management]
        Defender[Microsoft Defender for Cloud]
    end

    subgraph On-Premises Datacenter
        HyperV[Hyper-V Host]
        
        subgraph Nested Virtual Machines
            WinIIS["Windows VM<br>(IIS / ASP.NET)"]
            WinSQL["Windows VM<br>(SQL Server)"]
            Ubuntu["Linux VM<br>(Apache / PostgreSQL)"]
        end
        
        HyperV --> WinIIS
        HyperV --> WinSQL
        HyperV --> Ubuntu
    end

    WinIIS -.-> |Onboarded via Arc| Arc
    WinSQL -.-> |Onboarded via Arc| Arc
    Ubuntu -.-> |Onboarded via Arc| Arc

    Arc -.-> Monitor
    Arc -.-> Defender

    Migrate -.-> |Appliance Discovery & Replication| HyperV
```

## Deploy Migration Demo (ARM)

Use the button below to deploy the migration demo from the ARM template:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fob1juan%2FAzureSessions%2Fmain%2Fmigration_demo%2Fazure%2FARM%2Fazuredeploy.json)

## Demo Usage Summary

At a high level, run the demo as follows:

1. Complete Azure subscription onboarding and budget controls using [Lab 01 - Azure Trial Subscription](migration_demo/lab_guides/01-azure-trial-subscription.md).
2. Deploy and validate the nested environment using [Lab 02 - Environment Setup](migration_demo/lab_guides/02-environment-setup.md).
3. Discover and assess workloads with Azure Migrate using [Lab 03 - Azure Migrate Assessment (VMs and Databases)](migration_demo/lab_guides/03-azure-migrate-assessment.md).
4. Execute migration waves for VMs and data platforms using [Lab 04 - Azure Migrate Migration (VMs and Databases)](migration_demo/lab_guides/04-azure-migrate-migration.md).
5. Move web workloads toward managed platforms using [Lab 05 - Web App Modernization](migration_demo/lab_guides/05-web-app-modernization.md).
