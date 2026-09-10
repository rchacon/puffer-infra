output "app_id" {
  description = "Amplify app ID for puffer-panic."
  value       = aws_amplify_app.puffer_panic.id
}

# The bare app-id domain (aws_amplify_app.puffer_panic.default_domain
# alone) 404s -- Amplify's actual per-branch URL always needs the branch
# name prefixed. This output includes it so `terraform output` hands back
# something directly navigable.
output "default_domain" {
  description = "puffer-panic's default, directly-navigable *.amplifyapp.com URL for the branch -- useful for confirming a deploy works independent of DNS/domain-association status."
  value       = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.puffer_panic.default_domain}"
}

output "custom_domain_url" {
  description = "puffer-panic's custom domain URL (null until enable_custom_domain = true)."
  value       = var.enable_custom_domain ? "https://${var.domain_name}" : null
}
