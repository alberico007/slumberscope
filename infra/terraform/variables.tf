variable "resource_group_name" {
  type        = string
  description = "Resource group for the snoring inference VM"
  default     = "smarterpillow-snoring-rg"
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "eastus2"
}

variable "vm_size" {
  type        = string
  description = "VM SKU. B2s is fine for CPU YAMNet on ~1 req/30s."
  default     = "Standard_B2s"
}

variable "admin_username" {
  type        = string
  description = "Admin user on the VM"
  default     = "snoringadmin"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to the SSH public key to install on the VM"
  default     = "~/.ssh/id_rsa.pub"
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "CIDR allowed to reach port 22. Set to your current /32."
  # Intentionally no default — forces the caller to set this.
}

variable "dns_label" {
  type        = string
  description = "Leftmost label of the VM FQDN. Gives us <label>.<location>.cloudapp.azure.com"
}

variable "hmac_secret" {
  type        = string
  sensitive   = true
  description = "Shared HMAC secret. Also lives in the iOS app's Keychain. Pass via TF_VAR_hmac_secret."
}

variable "repo_url" {
  type        = string
  description = "Public git URL to clone the server code from"
  default     = "https://github.com/REPLACE_ME/smarterpillow-snoring-inference.git"
}
