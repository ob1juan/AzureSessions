# Lab 03: Azure Migrate Setup

Configure the Azure Migrate project and appliance, register the Hyper-V source, discover the nested workloads, and prepare the environment for assessment and migration demonstrations.

## Outcomes

- Open and configure the Azure Migrate project.
- Register the migration appliance.
- Add Hyper-V source credentials and discover the demo VMs.
- Create an initial assessment and prepare migration resources.

## Prerequisites

- Completed [Lab 02 - Login to Host VM](02-login-to-host-vm.md).
- The host VM and nested workloads are available.
- The Azure Migrate project created by the deployment is in the active subscription.
- The appliance URL is reachable from the host: `https://migdem-am:44368/`.

## Part 1: Open the Azure Migrate project

1. In the Azure portal, search for **Azure Migrate**.
2. Open the migration project created by the ARM deployment.
3. Review the project overview and select **Discovery and assessment**.

   ![Open the Azure Migrate project.](images/26-amportal.png)

4. Select **Discover** and choose **Hyper-V** as the source environment.

   ![Create or open the Azure Migrate project setup.](images/27-amproject.png)

5. Review the discovery requirements and download the appliance package or setup instructions if the portal requests them.

## Part 2: Configure the Azure Migrate appliance

1. From the host VM, open `https://migdem-am:44368/`.
2. Confirm the appliance landing page is available.

   ![Open the Azure Migrate appliance.](images/24-amappliance.png)

3. Sign in to the appliance with the lab-provided appliance credentials.

   ![Sign in to the Azure Migrate appliance.](images/25-amappliancelogin.png)

4. Select the Azure Migrate project and subscription shown in the portal.
5. Start appliance registration and copy the registration key from the Azure portal when prompted.

   ![Start appliance registration from the portal.](images/28-amdiscovery.png)

6. In the appliance, select the registration option and enter the key.

   ![Generate or enter the appliance registration key.](images/29-amkey.png)

7. Copy the key using the provided copy control or clipboard workflow.

   ![Copy the appliance registration key.](images/30-amkeycopy.png)

   ![Review the copied appliance key.](images/31-amkeyclipboard.png)

   ![Review the appliance key in a text editor before pasting it.](images/32-amkeynotepad.png)

8. Paste the key into the appliance registration field and verify the value before continuing.

   ![Paste the appliance registration key.](images/33-amkeypaste.png)

   ![Verify the appliance registration key.](images/34-amkeyverify.png)

9. Complete the Microsoft sign-in and device authorization flow if requested.

   ![Start appliance sign-in.](images/35-amappliancelogin.png)

   ![Enter the appliance sign-in code.](images/36-amappliancecode.png)

   ![Copy the appliance sign-in code to the clipboard.](images/37-amapplianceloginclipboard.png)

   ![Complete appliance device sign-in.](images/38-amappliancedevicelogin.png)

   ![Select the user for appliance sign-in.](images/39-amapplianceuserselect.png)

10. Confirm that the appliance registration is complete.

   ![Confirm appliance registration.](images/40-amappliancelogincomplete.png)

   ![Register the appliance with Azure Migrate.](images/41-amapplianceregister.png)

## Part 3: Configure source discovery

1. In the appliance, open the source discovery configuration.
2. Add the Hyper-V host details for the nested environment.
3. Add the Windows, SQL, and Linux credentials required for discovery. Use the lab credential flow and keep passwords out of notes and source control.

   ![Open the appliance migration configuration.](images/42-amportalmsi.png)

   ![Start appliance configuration.](images/43-amportalmsistart.png)

   ![Review appliance configuration resources.](images/44-amportalmsiresources.png)

4. Retrieve the appliance or source credentials from the deployed Key Vault when required.

   ![Open the appliance credentials flow.](images/45-amappliancecreds.png)

   ![Select the administrator password secret.](images/46-amportaladminpwkv.png)

   ![Review the password secret details.](images/47-amportaladminpwkv2.png)

   ![Retrieve the administrator password.](images/48-amportaladminpw.png)

   ![Confirm the administrator password value.](images/48-amportaladminpw2.png)

   ![Copy the administrator password securely.](images/49-amportaladminpwcopy.png)

   ![Copy the administrator password to the secure clipboard flow.](images/50-amportaladminpwclipboard.png)

5. Add and validate the Windows credentials used to discover the Hyper-V workloads.

   ![Configure Windows credentials.](images/51-amappliancewindowscred.png)

   ![Configure Hyper-V discovery.](images/52-amappliancehvdiscovery.png)

6. Select **Validate** and wait for a successful result.

   ![Validate Hyper-V discovery credentials.](images/53-amappliancevalidate.png)

   ![Confirm successful validation.](images/54-amappliancevalidatesuccess.png)

7. Add SQL and Linux credentials when the lab flow requires database or Linux workload discovery.

   ![Configure SQL credentials.](images/55-amappliancesqlcred.png)

   ![Configure Linux credentials.](images/56-appliancelinuxcred.png)

   ![Configure Windows credentials.](images/57-amappliancewincred.png)

8. Review the configured credential set before starting discovery.

   ![Review all appliance credentials.](images/59-amapplianceallcreds.png)

## Part 4: Create an assessment

1. Return to the Azure Migrate project and select **Assess and migrate servers**.
2. Create or open a server assessment.
3. Select the discovered VMs and configure:
   - Target Azure region
   - Performance-based or as-is sizing
   - Comfort factor
   - Reserved instance and discount assumptions
4. Run the assessment and review readiness, recommended sizes, estimated monthly cost, and confidence.

   ![Open the business case view.](images/60-businesscase.png)

   ![Review business case details.](images/61-businesscase2.png)

   ![Select workloads for the business case.](images/62-businesscaseworkloads.png)

   ![Review selected workloads.](images/63-businesscaseworkloads2.png)

   ![Start the business case.](images/64-businesscasestart.png)

5. Open the assessment results and capture the migration recommendations.

   ![Review the assessment results.](images/65-assessment.png)

## Part 5: Prepare migration resources

1. Open the **Migrate** experience from the Azure Migrate project.
2. Confirm the migration project and target subscription.
3. Review the target resource group, virtual network, subnet, and recovery services configuration.

   ![Open the Azure Migrate migration experience.](images/66-amportalmigrate.png)

   ![Review Azure Migrate migration settings.](images/67-amportalmigratedl.png)

4. Create or select the Key Vault and credentials required by the migration workflow.

   ![Open the migration credential configuration.](images/68-vaultcreds.png)

   ![Copy the vault credential value securely.](images/69-vaultcredsclipboard.png)

   ![Review the vault credential value.](images/70-vaultcredsnotepad.png)

   ![Enter the vault credential value.](images/71-vaultcredspaste.png)

   ![Save the vault credentials.](images/72-vaultcredssave.png)

5. Download the Hyper-V replication or migration components when prompted.

   ![Copy the migration download link.](images/73-amportalcopylink.png)

   ![Copy the Hyper-V migration link.](images/74-hypervlinkclipboard.png)

   ![Paste the Hyper-V migration link.](images/75-hypervpastlink.png)

   ![Download the Azure Site Recovery provider.](images/76-hypervdownloadasr.png)

   ![Open the downloaded provider package.](images/77-hypervopenasr.png)

6. Install and register the Hyper-V migration provider on the host when the demo requires replication.

   ![Install the Hyper-V migration provider.](images/78-hypervmigrateinstall.png)

   ![Register the Hyper-V migration provider.](images/79-hypervmigrateregister.png)

   ![Confirm provider registration.](images/80-hypervmigratedone.png)

7. Return to the Azure portal and refresh the migration status.

   ![Refresh migration status.](images/81-refresh.png)

8. Allow discovery, assessment, or replication to finish before starting the next demo activity.

   ![Wait for the migration operation to complete.](images/82-wait.png)

## Completion checklist

- The appliance is registered to the correct Azure Migrate project.
- Hyper-V discovery is validated.
- `migdem-iis`, `migdem-sql`, and `migdem-ubuntu` appear as discovered machines.
- An assessment has been created and its results are recorded.
- Migration resources and credentials are configured when the migration portion of the demo is being shown.

## Troubleshooting

- **The appliance page is unreachable:** Confirm `migdem-am` is running, the host can resolve its name, and the appliance port `44368` is accessible.
- **Registration fails:** Verify the project, subscription, tenant, and registration key are from the same environment.
- **Discovery returns no machines:** Recheck Hyper-V credentials, host connectivity, firewall rules, and the appliance validation status.
- **Assessment data is incomplete:** Leave discovery running long enough to collect performance data, then refresh the project.
- **Provider installation fails:** Confirm the host has internet access, adequate permissions, and that the downloaded provider matches the migration workflow.
