output "app_id" {
  description = "Amplify app ID for puffer-website."
  value       = aws_amplify_app.puffer_website.id
}

# The bare app-id domain (aws_amplify_app.puffer_website.default_domain
# alone) 404s -- Amplify's actual per-branch URL always needs the branch
# name prefixed. This output includes it so `terraform output` hands back
# something directly navigable.
output "default_domain" {
  description = "puffer-website's default, directly-navigable *.amplifyapp.com URL for the branch -- useful for confirming a deploy works independent of DNS/domain-association status."
  value       = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.puffer_website.default_domain}"
}

output "custom_domain_urls" {
  description = "puffer-website's custom domain URLs, one per served subdomain prefix (empty until enable_custom_domain = true). With the defaults: [\"https://pufferpanic.com\", \"https://www.pufferpanic.com\"]."
  value = var.enable_custom_domain ? [
    for p in var.subdomain_prefixes : "https://${p == "" ? "" : "${p}."}${var.domain_name}"
  ] : []
}
