# Deploy your private Global Front Desk workspace

<walkthrough-tutorial-duration duration="25"></walkthrough-tutorial-duration>

This guide creates one private application server in **your** Google Cloud account. Allow 20–40 minutes for Cloud Shell, Google approvals, and installation. Enabling Google services can take 5–10 minutes by itself. Your email, OAuth credentials, AI key, database, and logs stay in your account.

Google bills your company directly. A typical always-on deployment costs roughly **$30–$45 USD per month**, depending on region, traffic, taxes, discounts, and future Google pricing. Before anything billable is created, Terraform shows the exact resource plan: one e2-medium VM, one 30 GB encrypted disk, a dedicated network and subnet, HTTPS and restricted IAP SSH firewall rules, one static IP, and one runtime service account.

If Google first shows **Open in Cloud Shell**, check **Trust repo** and click **Confirm**. This only copies the installer files into Cloud Shell. Seeing the files or a terminal prompt does **not** mean the server has been created. Use this tutorial panel to continue.

## Choose your Google Cloud project

Sign in with the Google account your company wants to use to own and pay for this server. This account can be different from the mailbox you automate later.

Click **Select a project** in this panel:

1. If your company already has a suitable billing-enabled project, select it.
2. If not, click **New project**, enter a recognizable project name, choose the company organization and billing account when offered, and click **Create**.
3. Return to this tutorial and select the new project.

An existing “My First Project” is also fine if your company controls it and billing is active. Google charges your company for the server only after you approve the deployment plan. If prompted to start or resume a tutorial, start this one from the beginning.

<walkthrough-project-setup billing="true"></walkthrough-project-setup>

Check the project **ID** carefully: **<walkthrough-project-id/>**. Two projects can have the same display name.

## Approve the required Google services

Global Front Desk needs Compute Engine for the private server and IAM for its restricted runtime identity. Click **Copy to Cloud Shell** beside the command below. If Google offers **Run**, click it; otherwise press **Enter** in the terminal. Run it only once. Google can take **5–10 minutes** to enable the services, and the terminal may be quiet while it works. Wait until the command prompt returns before clicking **NEXT**.

<walkthrough-enable-apis apis="compute.googleapis.com,iam.googleapis.com,serviceusage.googleapis.com"></walkthrough-enable-apis>

These permissions apply only to the project selected above.

## Create the private workspace

Click **Copy to Cloud Shell** beside the command below. If Google offers **Run**, click it; otherwise press **Enter** in the terminal. The project ID must appear after `bash deploy.sh`. Copying the command is not enough: it must run in the terminal.

```sh
bash deploy.sh "<walkthrough-project-id/>"
```

When prompted for the **Global Front Desk installation ID**, return to the onboarding page,
copy the value beginning with `gfd-`, paste it into Cloud Shell, and press **Enter**. This securely
links the private workspace to the correct purchase and setup checklist.

Next, copy the **temporary deployment code** from the same onboarding page and paste it at the
hidden prompt. **Nothing appears in the terminal while you paste this secret. That is expected.**
Paste it once, press **Enter**, and do not paste it a second time. The code lasts 24 hours, can
report only this installation's workspace address and readiness, and cannot activate or access the
private workspace. Global Front Desk verifies both values before Terraform can create any cloud
resources. If validation fails or you need to restart these prompts, run
`bash deploy.sh "<walkthrough-project-id/>"` again.

The installer prints your Google account and project ID, then asks **Deploy the private Global Front Desk workspace to this project? [y/N]**. Check both values. Type `y` and press **Enter** to proceed.

Terraform then shows a plan for the server, encrypted disk, network, firewall rules, static IP, and service account. Check that it is for the right project. At **Approve this deployment? [y/N]**, type `y` and press **Enter**. This creates billable Google Cloud resources. The installer may first download and verify Terraform; wait for that to finish.

**“Apply complete” is not the final step.** Keep this Cloud Shell tab open while the application installs on the server. Continue only after the terminal says **“Your private workspace is ready”** and prints a one-time owner setup link. If Cloud Shell disconnects or a command fails, check the existing resources and read any new Terraform plan before retrying.

## Open the private dashboard

After the terminal says **“Your private workspace is ready”**, open the one-time owner setup link it prints. It is also saved in `deployment-result.txt`; use the command below only if you cannot find the printed link. Keep the link private.

```sh
cat deployment-result.txt
```

The private workspace account is separate from your Global Front Desk purchasing account. Create its owner account with a password you choose, enter the software license delivered to your purchase email, add your own AI provider key, and follow the private dashboard checklist to create your company-owned Google OAuth application and connect Gmail. The server is deployed at this point; **email automation is not active until the Gmail setup is complete**.

## Complete

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Your private workspace runs in your project. Global Front Desk has no standing Google Cloud account and never receives your Google password.
