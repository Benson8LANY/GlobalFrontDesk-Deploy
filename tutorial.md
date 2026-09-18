# Deploy your private Global Front Desk workspace

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

This guide creates one private application server in your Google Cloud account. Your email, OAuth credentials, AI key, database, and logs stay in that account.

## Choose your Google Cloud project

Select an empty project that your company controls. Billing must be active because Google charges your company for the server.

<walkthrough-project-setup billing="true"></walkthrough-project-setup>

The selected project is **<walkthrough-project-id/>**.

## Approve the required Google services

Global Front Desk needs Compute Engine for the private server and IAM for its restricted runtime identity.

<walkthrough-enable-apis apis="compute.googleapis.com,iam.googleapis.com,serviceusage.googleapis.com"></walkthrough-enable-apis>

These permissions apply only to the project selected above.

## Create the private workspace

Click **Run** on the command below. It shows the exact project and infrastructure before anything is created, then asks you to confirm.

```sh
bash deploy.sh "<walkthrough-project-id/>"
```

The deployment normally takes 5–10 minutes. Keep this browser tab open. The installer waits for the private workspace and prints the one-time owner setup link only when the site is ready.

## Open the private dashboard

After installation finishes, display the saved dashboard and owner setup links:

```sh
cat deployment-result.txt
```

Open the **One-time owner setup** link, create the owner account, enter the license delivered by email, add your AI provider key, and follow the private dashboard guide to create your company-owned Google OAuth application and connect Gmail.

## Complete

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Your private workspace runs in your project. Global Front Desk has no standing Google Cloud account and never receives your Google password.
