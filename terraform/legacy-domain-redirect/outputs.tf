output "redirects" {
  description = "Each redirected origin and where it now points (path and query string are preserved)."
  value       = { for h in values(local.hosts) : "https://${h.from}" => "https://${h.to}" }
}
