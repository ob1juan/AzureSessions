# Lab 04: Migrate SQL Server with Azure Database Migration Service

Create Azure Database Migration Service, register the self-hosted Integration Runtime on the Hyper-V host, and perform an offline migration of the `AdventureWorksLT2022` database from the nested SQL Server VM to Azure SQL Database.

## Outcomes

- Create an Azure Database Migration Service instance.
- Register the self-hosted Integration Runtime on the Hyper-V host.
- Connect Azure Database Migration Service to the nested SQL Server VM.
- Map the source `AdventureWorksLT2022` database to the provisioned Azure SQL Database.
- Run and verify an offline database migration.

## Prerequisites

- Completed [Lab 03 - Azure Migrate Setup](03-azure-migrate-setup.md).
- The deployment status report shows **SQL Server Integration Runtime** as completed.
- The nested SQL Server VM is running and reachable from the Hyper-V host as `migdem-sql`. If you chose another naming prefix during deployment, use `<prefix>-sql` instead.
- The source `AdventureWorksLT2022` database is online on the nested SQL Server.
- The target Azure SQL logical server and `AdventureWorksLT2022` database created by the deployment are available.
- You can retrieve the managed database administrator username and password from the deployment Key Vault.

> [!IMPORTANT]
> This lab uses an **offline migration**. Applications should stop writing to the source database before the migration begins. The source database remains available, but changes made after migration starts might not be copied to Azure SQL Database.

## Part 1: Create Azure Database Migration Service

1. In the Azure portal, search for **Azure Database Migration Service** and select **Create**.
2. On **Create Data Migration Service**, select the subscription and resource group used for the migration demo.
3. Select the same Azure region as the deployed demo resources.
4. Enter a unique migration service name.

   ![Configure the Azure Database Migration Service instance.](images/95-portaldms.png)

5. Select **Review + create**, verify the settings, and then select **Create**.

   ![Review and create Azure Database Migration Service.](images/96-portaldmscreate.png)

6. Wait for the deployment to complete, and then select **Go to resource**.

   ![Confirm the Azure Database Migration Service deployment completed.](images/97-portaldmsdone.png)

## Part 2: Start a migration and configure the runtime

1. On the Database Migration Service overview, select **New Migration**.

   ![Start a new database migration.](images/98-portaldmsnewmigration.png)

2. In the migration scenario wizard, select:
   - **Source server type:** SQL Server
   - **Target server type:** Azure SQL Database
   - **Migration mode:** Offline
3. Expand **Install, setup and configure Self-hosted Integration Runtime**, and select **Configure runtime settings**.

   ![Open the self-hosted Integration Runtime settings.](images/99-portaldmsconfigruntime.png)

4. In **Configure integration runtime**, copy **key 1**. Keep the portal pane open while you register the runtime.

   ![Display the Integration Runtime authentication keys.](images/100-portaldmskeys.png)

   ![Copy the first Integration Runtime authentication key.](images/101-portaldmscopykey.png)

5. Return to the Azure Bastion session connected to the Hyper-V host. Open the Bastion clipboard and paste the key into the remote clipboard.

   ![Transfer the authentication key through the Bastion clipboard.](images/102-hypervdmsclipboard.png)

6. Paste the key into **Microsoft Integration Runtime Configuration Manager**.

   ![Paste the authentication key into Integration Runtime Configuration Manager.](images/103-hypervpastkey.png)

7. If Configuration Manager is not already open, open **Microsoft Integration Runtime** from the Windows Start menu. The deployment automation installs the runtime on the Hyper-V host.

   ![Open Microsoft Integration Runtime on the Hyper-V host.](images/105-hypervopenruntime.png)

8. Select **Register**. For the node name, enter a recognizable name such as `MigDem-Host`, and then select **Finish**. Leave **Enable remote access from intranet** cleared unless your environment specifically requires it.

   ![Register the self-hosted Integration Runtime node.](images/106-hypervregisterruntime.png)

9. Return to the portal, refresh the runtime status, and continue after the node reports as connected.

## Part 3: Connect to the source SQL Server

1. For **Source Infrastructure Type**, select **Virtual Machine**.
2. Select the demo subscription, resource group, and region.
3. Enter a unique tracking resource name, such as `migdem-sql-tracking`. Azure creates this free SQL Server instance resource to track the migration.

   ![Configure the SQL Server tracking resource.](images/107-portaldmssource.png)

   ![Review the source infrastructure and SQL Server instance details.](images/108-portaldmssouce2.png)

4. Select **Next: Connect to source SQL Server**.
5. Enter the source connection details:
   - **Source server name:** `migdem-sql`, or `<prefix>-sql` if you used a different prefix
   - **Authentication type:** SQL Authentication
   - **User name:** the SQL administrator login for the nested SQL Server
   - **Password:** retrieve the current source SQL credential through the lab credential flow
6. Keep **Encrypt connection** and **Trust server certificate** selected, and then select **Next: Select databases for migration**.

   ![Connect to the source SQL Server.](images/109-portaldmsconnect.png)

## Part 4: Select the source and connect to Azure SQL Database

1. Select `AdventureWorksLT2022` as the source database. Do not select `ArcBoxDemo` for this exercise.

   ![Select AdventureWorksLT2022 as the source database.](images/115-portalselecdb.png)

2. Select **Next: Connect to target Azure SQL Database**.
3. In another portal tab, search for **Key vaults** and open the Key Vault deployed in the demo resource group.

   ![Open the deployment Key Vault.](images/110-portalsqlkvpassword.png)

4. Under **Objects**, select **Secrets**. Retrieve these secrets without recording their values:
   - `managedDatabaseAdminUsername`
   - `managedDatabaseAdminPassword`

   ![Open the managed database administrator secrets.](images/110-portalkvpassword2.png)

5. Open `managedDatabaseAdminPassword`, select its current version, and then select **Show Secret Value**.

   ![Open the managed database administrator password version.](images/111-portalkvpassword3.png)

   ![Show the managed database administrator password.](images/112-portalkvpassword4.png)

6. Copy the secret value. Repeat the process for `managedDatabaseAdminUsername` if needed.

   ![Copy the managed database administrator password.](images/113-portalkvpasswordcopy.png)

7. Return to the migration wizard and select the target Azure SQL logical server in the demo resource group.
8. Enter the managed database administrator username and password from Key Vault. Wait for the wizard to connect and load the target databases, and then select **Next: Map source and target databases**.

   ![Connect to the target Azure SQL Database server.](images/114-portaldmspw.png)

## Part 5: Map the database and select tables

1. Map source database `AdventureWorksLT2022` to target database `AdventureWorksLT2022`.

   ![Map the source database to the target Azure SQL Database.](images/115-portalselectdb2.png)

2. Select **Next: Select database tables to migrate**.
3. Expand the database and review the selected tables. Select all compatible application tables required for the exercise. The captured example migrates 11 of 12 tables.

   ![Select the database tables to migrate.](images/116-portalselecttables.png)

4. Select **Next: Database migration summary**.
5. Review the source, target, migration mode, Database Migration Service, database mapping, and selected table count. Correct any unexpected setting before continuing.
6. Select **Start migration**.

   ![Review the migration summary and start the migration.](images/117-portalstartmigration.png)

## Part 6: Monitor and verify the migration

1. On the migrations page, wait while the migration status changes from **Creating** to **In progress**.

   ![Wait while the migration is created.](images/118-portalmigrationinprogress.png)

   ![Monitor the offline migration in progress.](images/119-portalmigrationprogress2.png)

2. Refresh periodically until **Migration status** shows **Succeeded**.

   ![Confirm that the database migration succeeded.](images/120-portalmigrationcomplete.png)

3. Open the migration details and confirm that the expected tables completed without errors.
4. Open the target `AdventureWorksLT2022` database in the Azure portal or SQL Server Management Studio and verify that the migrated tables contain data.

## Completion checklist

- Azure Database Migration Service is deployed in the demo resource group.
- The self-hosted Integration Runtime node reports as connected.
- The source server `migdem-sql` is reachable through the runtime.
- Source and target `AdventureWorksLT2022` databases are mapped.
- The offline migration status is **Succeeded**.
- The expected tables and data are present in Azure SQL Database.

## Troubleshooting

- **The runtime does not connect:** Confirm the Integration Runtime service is running on the Hyper-V host, register it with a current key, and verify outbound HTTPS access.
- **The source server cannot be reached:** Confirm the nested SQL VM is running, resolve the correct `<prefix>-sql` host name from the Hyper-V host, and verify TCP port `1433` is allowed.
- **Source authentication fails:** Verify that SQL Authentication is selected and retrieve the current source SQL credential through the lab credential flow.
- **The target server cannot be reached:** Confirm the correct Azure SQL logical server is selected and that its firewall permits Azure services as configured by the deployment.
- **Target authentication fails:** Retrieve `managedDatabaseAdminUsername` and `managedDatabaseAdminPassword` again from the deployment Key Vault and avoid extra spaces when pasting.
- **The target database is missing:** Confirm the initial deployment completed successfully and that `AdventureWorksLT2022` exists on the Azure SQL logical server.
- **Some tables cannot be selected:** Review the table-level compatibility details in the wizard. Migrate the compatible tables and document any schema changes required for unsupported objects.
- **Migration remains in progress:** Open the migration details for table-level errors, verify that the runtime remains online, and confirm connectivity to both source and target servers.
