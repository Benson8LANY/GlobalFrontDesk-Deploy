output "dashboard_url" {
  description = "Private customer dashboard created by this deployment."
  value       = "https://${local.initial_fqdn}"
}

output "owner_setup_url" {
  description = "Single-use link for creating the first owner account."
  value       = "https://${local.initial_fqdn}/login#setup=${random_password.owner_setup.result}"
  sensitive   = true
}

output "workspace_ip" {
  description = "Static public IP reserved for the private workspace."
  value       = google_compute_address.workspace.address
}

output "installation_log_command" {
  description = "Command for the customer administrator to inspect installation progress through IAP."
  value       = "gcloud compute ssh ${google_compute_instance.workspace.name} --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap --command='sudo tail -n 200 /var/log/global-front-desk-install.log'"
}

