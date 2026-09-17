#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

die() { printf 'Deployment stopped: %s\n' "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }

command -v gcloud >/dev/null || die "Google Cloud CLI is required. Open this installer in Google Cloud Shell."
command -v terraform >/dev/null || die "Terraform is required. Google Cloud Shell includes Terraform."

active_account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"
[[ -n "$active_account" ]] || die "Sign in to Google Cloud before deploying."

project_id="${GOOGLE_CLOUD_PROJECT:-${CLOUDSDK_CORE_PROJECT:-}}"
if [[ -z "$project_id" ]]; then
  project_id="$(gcloud config get-value project 2>/dev/null || true)"
fi
[[ -n "$project_id" && "$project_id" != "(unset)" ]] || die "Select a Google Cloud project in the tutorial first."

project_state="$(gcloud projects describe "$project_id" --format='value(lifecycleState)' 2>/dev/null || true)"
[[ "$project_state" == "ACTIVE" ]] || die "The selected project is unavailable: $project_id"

billing_enabled="$(gcloud billing projects describe "$project_id" --format='value(billingEnabled)' 2>/dev/null || true)"
[[ "$billing_enabled" == "True" || "$billing_enabled" == "true" ]] || die "Enable billing for $project_id, then run this step again."

printf '\nGoogle account: %s\nProject: %s\n\n' "$active_account" "$project_id"
read -r -p "Deploy the private Global Front Desk workspace to this project? [y/N] " answer
[[ "$answer" == "y" || "$answer" == "Y" ]] || die "Nothing was changed."

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

info "Preparing the customer-owned deployment"
terraform init -input=false

info "Showing the infrastructure Google will create"
terraform plan -input=false -out=.deployment.tfplan -var="project_id=$project_id"

printf '\nThis plan creates one VM, one encrypted disk, a dedicated network, firewall rules, a static IP, and a runtime service account.\n'
read -r -p "Approve this deployment? [y/N] " approve
[[ "$approve" == "y" || "$approve" == "Y" ]] || die "The plan was not applied."

info "Creating the private workspace"
terraform apply -input=false -auto-approve .deployment.tfplan

dashboard_url="$(terraform output -raw dashboard_url)"
owner_setup_url="$(terraform output -raw owner_setup_url)"
cat > deployment-result.txt <<EOF
Private dashboard: $dashboard_url
One-time owner setup: $owner_setup_url
EOF
chmod 0600 deployment-result.txt

info "Waiting for the private workspace"
printf 'Google is installing Global Front Desk on the new server. This normally takes 5-10 minutes.\n'
ready=false
for attempt in $(seq 1 90); do
  if curl --proto '=https' --tlsv1.2 -fsS --max-time 10 "$dashboard_url/health/ready" >/dev/null 2>&1; then
    ready=true
    break
  fi
  if (( attempt % 6 == 0 )); then
    printf 'Still installing... (%d minutes elapsed)\n' "$((attempt / 6))"
  fi
  sleep 10
done

if [[ "$ready" != true ]]; then
  printf '\nThe server is still installing. Your links are safe in deployment-result.txt.\n'
  printf 'To check progress, run:\n  %s\n\n' "$(terraform output -raw installation_log_command)"
  exit 1
fi

info "Your private workspace is ready"
printf 'Your one-time setup link is saved in:\n  %s/deployment-result.txt\n\n' "$script_dir"
printf 'Open this link now:\n%s\n' "$owner_setup_url"
