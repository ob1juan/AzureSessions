# Lab 03: Azure Migrate Assessment for VMs and Databases

Use this guide to discover Hyper-V workloads and run Azure Migrate assessments for server and database migration planning.

## Outcomes

- Discover Hyper-V VMs with Azure Migrate appliance
- Build readiness and sizing assessments for VM migration
- Build SQL/database assessment insights for migration strategy

## Prerequisites

- Completed Lab 02 environment setup
- Azure Migrate project in the same subscription
- Access to the appliance UI: https://migdem-am:44368/

## Part A: Create Azure Migrate Project

1. In Azure portal, search for Azure Migrate.
2. Select Assess and migrate servers.
3. Create project:
   - Subscription and resource group
   - Geography and project name

## Part B: Discover Hyper-V Servers

1. In the Azure Migrate project, go to Discovery and assessment.
2. Select Discover.
3. Choose Hyper-V as source.
4. Download or confirm appliance setup script details if prompted.
5. On the appliance UI:
   - Register appliance to the project
   - Add Hyper-V host details
   - Start continuous discovery
6. Wait until all demo VMs are discovered.

Expected discovered targets include:

- SQL Windows VM
- Ubuntu Linux VM
- Optional additional workload VMs based on flavor

## Part C: Run VM Assessment

1. In Azure Migrate, create a server assessment group.
2. Add discovered VMs to the group.
3. Configure assessment properties:
   - Target region
   - Sizing criterion (performance-based recommended)
   - Comfort factor, reserved instances, and discount assumptions
4. Run assessment.
5. Review outputs:
   - Azure readiness
   - Recommended VM size
   - Estimated monthly cost
   - Dependency and confidence ratings

## Part D: Database Assessment (SQL)

1. In Azure Migrate, open Databases (if using database migration workflow).
2. Discover SQL instances from the SQL VM.
3. Start assessment for SQL workloads.
4. Review migration targets and readiness options:
   - SQL Server on Azure VM
   - Azure SQL Managed Instance
   - Azure SQL Database (where applicable)
5. Capture blockers and remediation recommendations.

## Deliverables

- One VM assessment report for discovered server group
- One SQL/database assessment summary with target recommendations
- Cost estimate and migration wave proposal

## Troubleshooting

- If VMs do not appear, verify appliance connectivity and Hyper-V credentials.
- If performance-based sizing has low confidence, extend discovery duration.
- If SQL discovery fails, validate SQL services are running and firewall rules allow discovery.
