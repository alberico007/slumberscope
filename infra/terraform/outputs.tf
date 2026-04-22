output "public_ip" {
  value       = azurerm_public_ip.pip.ip_address
  description = "Public IP of the inference VM"
}

output "fqdn" {
  value       = local.fqdn
  description = "Fully-qualified DNS name for Caddy / TLS"
}

output "endpoint" {
  value       = "https://${local.fqdn}/classify"
  description = "URL the iOS app should POST to"
}

output "ssh_command" {
  value       = "ssh ${var.admin_username}@${local.fqdn}"
  description = "SSH convenience command"
}
