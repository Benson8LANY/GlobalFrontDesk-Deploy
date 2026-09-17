# Customer-owned Google Cloud deployment

This package powers the customer-owned **Deploy to Google Cloud** button.

The customer opens a Google Cloud Shell tutorial, selects a billing-enabled project, enables the required APIs, and runs `deploy.sh`. Terraform shows the complete plan before creating a dedicated network, static IP, Shielded VM, encrypted boot disk, and runtime service account. The application then installs from the signed Global Front Desk release channel.

The deployment does not request access to the customer's Gmail account. After the server is running, the customer creates their own Google OAuth application and authorizes Gmail from inside the private workspace.

## Public deployment repository

Google Cloud Shell must be able to clone this directory from a customer-accessible Git repository. Publish only this deployment package to the public deployment repository. Do not publish application source, signing keys, control-plane code, customer data, or credentials.

The website should use a URL shaped like:

```text
https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/OWNER/DEPLOYMENT_REPOSITORY&cloudshell_git_branch=main&cloudshell_tutorial=tutorial.md&cloudshell_workspace=.&show=terminal
```

## Release-distribution requirement

The signed installer and release files are published at `https://benson8lany.github.io/GlobalFrontDesk-Deploy/`. The signed runtime images referenced by the release manifest must be anonymously pullable by a newly created customer VM. Do not enable the website button until those images are public and a clean customer project completes the full deployment test.
