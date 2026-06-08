# Lab 04: Azure Migrate Migration for VMs and Databases

Use this guide to execute migration waves for server workloads and database workloads based on assessment outputs.

## Outcomes

- Replicate and migrate Hyper-V VMs to Azure
- Execute database migration plan for SQL workloads
- Validate cutover success and post-migration functionality

## Prerequisites

- Completed Lab 03 assessments
- Approved migration wave plan
- Target Azure network/subnet design prepared

## Part A: VM Replication Setup

1. In Azure Migrate, open Servers migration.
2. Select Replicate for Hyper-V discovered machines.
3. Configure replication settings:
   - Target subscription/resource group
   - Target VNet/subnet
   - Storage and availability options
4. Start replication for selected VMs.
5. Monitor replication health until protected state is healthy.

## Part B: Test Migration

1. Run Test migrate for each VM.
2. Use an isolated test subnet.
3. Validate:
   - OS boot
   - App process health
   - Network and DNS behavior
4. Clean up test migration resources after validation.

## Part C: Cutover Migration

1. Schedule a maintenance window.
2. Stop source app writes if required.
3. Run Migrate (cutover) for production migration.
4. Confirm VM startup in Azure.
5. Complete migration in Azure Migrate to finalize state.

## Part D: SQL Database Migration Execution

Choose the target architecture based on assessment recommendations.

- SQL on Azure VM:
  - Rehost VM and validate SQL service/database integrity.
- Azure SQL Managed Instance or Azure SQL Database:
  - Use Azure Database Migration Service (DMS) migration runbooks.

Validation checklist:

- Database schema and row counts
- Login/user mapping
- Application connection strings updated
- End-to-end app transaction test

## Post-Migration Tasks

- Enable backup and monitoring in Azure
- Apply security baseline and Defender plans
- Confirm RPO/RTO objectives
- Decommission or power down source workloads after acceptance

## Troubleshooting

- Replication issues: verify appliance health and bandwidth constraints.
- Boot issues after cutover: check VM generation/driver and network configs.
- SQL issues: validate compatibility level, collation, and connectivity/security rules.
