variable "project_id" {
  description = "Customer-owned Google Cloud project for the private workspace."
  type        = string
}

variable "installation_id" {
  description = "Authoritative Global Front Desk installation ID from onboarding."
  type        = string

  validation {
    condition     = can(regex("^gfd-[a-f0-9-]{36}$", var.installation_id))
    error_message = "Copy the gfd- installation ID exactly from Global Front Desk onboarding."
  }
}

variable "deployment_name" {
  description = "Prefix for resources created by this deployment."
  type        = string
  default     = "global-front-desk"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", var.deployment_name))
    error_message = "Use 1-40 lowercase letters, numbers, or hyphens, beginning with a letter."
  }
}

variable "region" {
  description = "Region for the private workspace."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zone for the private workspace."
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "Machine size for the application."
  type        = string
  default     = "e2-medium"
}

variable "source_image" {
  description = "Supported Ubuntu base image."
  type        = string
  default     = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
}

variable "installer_url" {
  description = "HTTPS URL of the signed Global Front Desk installer."
  type        = string
  default     = "https://benson8lany.github.io/GlobalFrontDesk-Deploy/install.sh"

  validation {
    condition     = can(regex("^https://", var.installer_url))
    error_message = "The installer URL must use HTTPS."
  }
}

variable "release_channel" {
  description = "Signed software release channel."
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["preview", "stable"], var.release_channel)
    error_message = "Release channel must be preview or stable."
  }
}
