# Lab 05: Web App Modernization Path

Use this guide to modernize the demo web applications after migration, moving from VM-hosted web tiers to managed Azure web platforms.

## Outcomes

- Define modernization target for ASP.NET and PHP workloads
- Move web tiers from IaaS VMs to PaaS where practical
- Keep database dependencies aligned with migration outcomes

## Workload Scope

- Legacy ASP.NET Web Forms storefront (Windows/IIS)
- PHP storefront on Ubuntu/Apache
- Back-end SQL and PostgreSQL data services

## Modernization Decision Matrix

Use this as a quick target selector:

1. ASP.NET Web Forms on full .NET Framework:
   - Near-term: Azure App Service (Windows)
   - Strategic: refactor to ASP.NET Core where feasible
2. PHP on Apache:
   - Azure App Service (Linux) or containerized deployment on Azure Container Apps
3. SQL back end:
   - Azure SQL Managed Instance or SQL on Azure VM depending on compatibility needs
4. PostgreSQL back end:
   - Azure Database for PostgreSQL Flexible Server

## Step 1: Baseline and Prepare

- Inventory app dependencies and config values
- Externalize secrets to Azure Key Vault
- Parameterize environment settings
- Establish CI/CD pipeline baseline

## Step 2: Web Tier Modernization

### ASP.NET Path

1. Package and deploy to Azure App Service (Windows).
2. Update app settings and connection strings.
3. Validate authentication/session behavior.

### PHP Path

1. Deploy code to Azure App Service (Linux) or container target.
2. Configure runtime version and startup command as needed.
3. Validate routing, extensions, and database connectors.

## Step 3: Data Tier Alignment

- Point application connection strings to migrated Azure databases.
- Apply least-privilege identities and managed identity where supported.
- Run smoke + regression tests on critical business flows.

## Step 4: Observability and Security

- Enable Application Insights and Log Analytics.
- Configure alerts for availability, latency, and failures.
- Apply Defender recommendations and HTTPS/TLS baseline.

## Step 5: Cutover and Optimization

- Execute staged cutover (test, pilot, production).
- Monitor performance and right-size plans.
- Decommission legacy VM web tiers after acceptance.

## Lab Deliverables

- Modernization architecture diagram (current vs target)
- Deployment evidence for modernized web endpoints
- Validation report for app functionality and performance
- Rollback plan and go-live checklist
