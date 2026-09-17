locals {
  name         = var.deployment_name
  initial_fqdn = "${replace(google_compute_address.workspace.address, ".", "-")}.sslip.io"
}

resource "random_password" "owner_setup" {
  length  = 48
  special = false
}

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = substr("${local.name}-runtime", 0, 30)
  display_name = "Global Front Desk private runtime"

  depends_on = [google_project_service.iam]
}

resource "google_compute_network" "workspace" {
  project                 = var.project_id
  name                    = "${local.name}-network"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "workspace" {
  project       = var.project_id
  name          = "${local.name}-subnet"
  region        = var.region
  network       = google_compute_network.workspace.id
  ip_cidr_range = "10.42.0.0/24"
}

resource "google_compute_firewall" "web" {
  project       = var.project_id
  name          = "${local.name}-web"
  network       = google_compute_network.workspace.id
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gfd-web"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "iap_ssh" {
  project       = var.project_id
  name          = "${local.name}-iap-ssh"
  network       = google_compute_network.workspace.id
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["gfd-admin"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_address" "workspace" {
  project = var.project_id
  name    = "${local.name}-ip"
  region  = var.region

  depends_on = [google_project_service.compute]
}

resource "google_compute_instance" "workspace" {
  project      = var.project_id
  name         = "${local.name}-workspace"
  zone         = var.zone
  machine_type = var.machine_type
  tags         = ["gfd-web", "gfd-admin"]

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = var.source_image
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.workspace.id

    access_config {
      nat_ip = google_compute_address.workspace.address
    }
  }

  service_account {
    email  = google_service_account.runtime.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata_startup_script = templatefile("${path.module}/startup.sh.tftpl", {
    fqdn            = local.initial_fqdn
    installer_url   = var.installer_url
    release_channel = var.release_channel
    setup_token     = random_password.owner_setup.result
  })

  depends_on = [
    google_compute_firewall.web,
    google_compute_firewall.iap_ssh,
  ]
}

