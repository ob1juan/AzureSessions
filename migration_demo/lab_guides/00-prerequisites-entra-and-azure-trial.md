# Prerequisites: Create a Trial Microsoft Entra Tenant and Azure Subscription

Complete this guide before starting [Lab 01 - Azure Trial Subscription](01-azure-trial-subscription.md). The flow below uses the `ob1juan` Microsoft account and creates a dedicated Microsoft Entra tenant together with an Azure trial subscription for the labs.

> **Important:** Microsoft currently does not allow a free tenant or a trial subscription to create an additional Workforce tenant from the Microsoft Entra admin center. For a trial environment, start with the Azure free-account sign-up. The sign-up creates the initial Microsoft Entra tenant, and the Azure trial subscription is created in that tenant. The separate **Manage tenants > Create** flow is included for reference only and requires an eligible paid billing arrangement.

## Outcomes

- Create or confirm a dedicated Microsoft Entra tenant for the lab.
- Create an Azure Free Account trial subscription in that tenant.
- Confirm the `ob1juan` account is a Global Administrator and subscription owner.
- Verify that the portal is operating in the new directory before deploying lab resources.

## Requirements and safety

- Use the `ob1juan` account; do not use the `rhodesjuan_microsoft` account for this lab environment.
- A phone number that can receive verification codes.
- A valid payment method for identity verification. Azure displays the offer and eligibility during sign-up; availability varies by country/region and account history.
- Use a private browser window or sign out of other Microsoft accounts first to avoid creating the trial in the wrong directory.
- Trial credits and free-service quotas are limited. Set a budget before deploying any lab resources.

## Part 1: Start the Azure Free Account sign-up

1. Open [Azure Free Account](https://azure.microsoft.com/free/).
2. Select **Start free** under **Azure free account**.

   ![Azure free account page showing the Azure free account offer and Start free button.](images/azure-free-account.png)

3. Sign in with the `ob1juan` Microsoft account. If prompted to choose an account, select `ob1juan`; do not continue with `rhodesjuan_microsoft`.
4. If this account has no directory yet, continue through the account-creation flow. Azure creates an initial Microsoft Entra tenant with an initial domain in the form `<name>.onmicrosoft.com`.
5. Complete the requested phone verification and payment-method verification. The payment method is used for identity validation; read the offer terms for the current region before accepting.
6. Review the Microsoft Customer Agreement, privacy statement, and trial offer terms, then select **Sign up** or **Create**.

### If the account already has a directory

If Azure shows an existing directory during sign-up, record its name and tenant ID. Do not create a second tenant from the Entra admin center while using a trial account. If the existing directory is not the dedicated lab directory, stop and use a separate `ob1juan` sign-up identity or an eligible paid subscription.

## Part 2: Verify the new Microsoft Entra tenant

1. Open [Microsoft Entra admin center](https://entra.microsoft.com).
2. Select the account menu in the upper-right corner and confirm the directory name and initial `onmicrosoft.com` domain.
3. Open **Entra ID > Overview > Properties** and record the **Tenant ID** for the lab notes.
4. Confirm that the account used to create the tenant has the **Global Administrator** role. The creator is assigned this role by default.

The following screenshots show the current paid-tenant reference flow. Do not use **Manage tenants > Create** for a free/trial tenant unless Microsoft shows that the account has the required eligibility and permissions:

![Microsoft Entra Overview page with Manage tenants selected.](https://learn.microsoft.com/en-us/entra/fundamentals/media/create-new-tenant/portal.png)

![Microsoft Entra Create a tenant configuration tab.](https://learn.microsoft.com/en-us/entra/fundamentals/media/create-new-tenant/create-new-tenant.png)

## Part 3: Create the Azure trial subscription in the new tenant

1. Open the [Azure portal](https://portal.azure.com).
2. Use the directory switcher in the upper-right corner and select the new Microsoft Entra directory.
3. Search for **Subscriptions** and select **Add**.

   ![Azure portal Subscriptions page with Add selected.](https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/media/create-subscription/subscription-add.png)

4. On the **Basics** tab:
   - Enter a recognizable name, such as `AzureSessions-Trial`.
   - Select the billing account and profile made available by the Azure Free Account sign-up.
   - Select the trial/free offer when it is presented. Do not choose Pay-As-You-Go unless the trial offer is unavailable and you intentionally accept chargeable usage.

   ![Azure subscription creation Basics tab.](https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/media/create-subscription/create-subscription-basics-tab.png)

5. On the **Advanced** tab:
   - Set **Subscription directory** to the new Microsoft Entra tenant.
   - Select a management group only if one is already available; otherwise leave the default.
   - Select the `ob1juan` account as a subscription owner.

   ![Azure subscription creation Advanced tab with subscription directory and owner fields.](https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/media/create-subscription/create-subscription-advanced-tab.png)

6. Add an optional tag such as `Purpose=AzureSessions`.
7. Select **Review + create**. Confirm that validation passes and that the subscription directory is the new tenant.
8. Select **Create** and wait for the subscription to finish provisioning.

> **Offer availability:** Some accounts or regions are not eligible for the Azure Free Account offer, and the portal may show a different purchase flow. Do not proceed with chargeable billing for a training environment without explicit approval.

## Part 4: Verify the tenant-to-subscription relationship

In the Azure portal, with the new directory still selected:

1. Open **Subscriptions** and confirm `AzureSessions-Trial` is listed.
2. Confirm **State** is **Enabled**.
3. Open the subscription and verify:
   - **Directory** is the new Microsoft Entra tenant.
   - `ob1juan` is listed as an owner or has equivalent access.
   - The subscription ID is recorded in the lab notes.
4. Open **Cost Management > Budgets** and create a budget with an alert well below the trial credit limit.
5. Use **Cloud Shell** or a local terminal to validate the active context:

   ```bash
   az login
   az account list --output table
   az account show --output table
   az account set --subscription "<AzureSessions-Trial>"
   az account show --query "{name:name,id:id,tenantId:tenantId,state:state}" --output table
   ```

The returned `tenantId` must match the tenant ID recorded in Part 2.

## Troubleshooting

- **The wrong account appears:** Open a private browser window, sign in only as `ob1juan`, and restart the Azure Free Account flow.
- **Create tenant is unavailable:** This is expected for many free/trial accounts. Use the Azure Free Account sign-up to create the initial tenant, or use an eligible paid billing account.
- **The trial offer is unavailable:** Check country/region and account eligibility. Do not substitute Pay-As-You-Go without approval.
- **The subscription is missing:** Switch directories, clear portal subscription filters, and refresh. A subscription is visible only in directories where the signed-in account has access.
- **Unexpected charges are a concern:** Stop deployments, delete the lab resource group, and review Cost Management before the trial credit expires.

## Continue

After the tenant and subscription checks pass, continue with [Lab 01 - Azure Trial Subscription](01-azure-trial-subscription.md), then [Lab 02 - Environment Setup](02-environment-setup.md).

## References

- [Quickstart: Access and create a new tenant](https://learn.microsoft.com/en-us/entra/fundamentals/create-new-tenant)
- [Create a Microsoft Customer Agreement subscription](https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
- [Azure free account](https://azure.microsoft.com/free/)
