# Lab 01: Sign Up for an Azure Trial Subscription

Use this guide to create an Azure subscription you can use for the migration demo labs.

## Outcomes

- Create a new Azure account
- Activate an Azure free trial subscription
- Validate that the subscription is ready for deployments

## Prerequisites

- A Microsoft account (or create one during sign-up)
- A phone number for verification
- A valid payment method for identity validation (usage beyond trial limits can incur charges)

## Steps

1. Open the official Azure free account page:
   - https://azure.microsoft.com/free/
2. Select Start free.
3. Sign in with an existing Microsoft account or create a new one.
4. Complete identity verification:
   - Phone verification
   - Card verification (authorization only; behavior depends on region and current offer)
5. Accept the terms and create the subscription.
6. Open the Azure portal:
   - https://portal.azure.com
7. Verify the subscription is active:
   - In the portal, search for Subscriptions.
   - Confirm your new subscription is listed with state Enabled.

## Post-Setup Checks

Run these checks from Azure CLI (Cloud Shell or local terminal):

```bash
az login
az account list --output table
az account show --output table
```

If multiple subscriptions are present, set the one for the labs:

```bash
az account set --subscription "<your-subscription-name-or-id>"
```

## Cost and Safety Recommendations

- Create a dedicated resource group for the demo and delete it after labs.
- Add a budget + alerts before deployment.
- Pause or stop non-essential compute resources when not in use.

## Troubleshooting

- If your trial offer is not available in your region, use Pay-As-You-Go and enforce strict budget alerts.
- If identity verification fails, retry from a private browser session and ensure profile details match your payment profile.
