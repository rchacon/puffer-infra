# Amplify Hosting for the Puffer Panic marketing site (rchacon/pufferpanic.com
# on GitHub; local clone directory puffer-website) -- an Astro static site,
# no client-side router (`astro build` emits one index.html per route, no
# SPA fallback needed). This module claims the apex (pufferpanic.com) and
# www -- see ../amplify/variables.tf's subdomain_prefixes comment and
# domain-layout notes: ../amplify is only ever allowed the `app` prefix.
#
# No build_spec override here: unlike puffer-panic, this repo already
# commits its own amplify.yml (pins Node 22 via nvm, `npm ci`, `npm run
# build`, dist baseDirectory) -- Amplify auto-detects and uses it, so
# duplicating it into Terraform would just be two copies to keep in sync.
#
# One-time manual prerequisites before `terraform apply` works (see
# terraform/README.md): install the AWS Amplify GitHub App for
# rchacon/pufferpanic.com AND add that repo to the App's repository access
# list (both steps -- the second is easy to miss and its build failure,
# "Unable to assume specified IAM Role", points nowhere near the real
# cause). This is a separate GitHub App authorization from ../amplify's --
# each repo has to be added to the access list individually.

resource "aws_amplify_app" "puffer_website" {
  name         = "puffer-website"
  repository   = var.github_repository
  access_token = var.github_access_token
  platform     = "WEB"

  tags = {
    Project = "puffer-panic"
  }
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.puffer_website.id
  branch_name = var.branch_name

  enable_auto_build = true
  stage             = "PRODUCTION"

  tags = {
    Project = "puffer-panic"
  }
}

# --- Custom domain (gated on enable_custom_domain) -----------------------
#
# See ../amplify/main.tf for the full rationale on wait_for_verification =
# false and why Amplify (not this module) owns the ACM certificate.
resource "aws_amplify_domain_association" "puffer_website" {
  count = var.enable_custom_domain ? 1 : 0

  app_id                = aws_amplify_app.puffer_website.id
  domain_name           = var.domain_name
  wait_for_verification = false

  dynamic "sub_domain" {
    for_each = toset(var.subdomain_prefixes)
    content {
      branch_name = aws_amplify_branch.main.branch_name
      prefix      = sub_domain.value
    }
  }
}

# --- Cloudflare DNS records --------------------------------------------------
#
# See ../amplify/main.tf for the detailed rationale on parsing Amplify's
# space-delimited dns_record / certificate_verification_dns_record strings
# (deliberately not trimspace()'d -- the leading space on the empty-name
# apex record is significant) and the try()/precondition guards against
# empty strings (reused cert validation, or a transient empty sub_domain
# record right after the association is created).
locals {
  cert_verification = var.enable_custom_domain ? split(" ", aws_amplify_domain_association.puffer_website[0].certificate_verification_dns_record) : []

  sub_records = var.enable_custom_domain ? {
    for sd in aws_amplify_domain_association.puffer_website[0].sub_domain :
    sd.prefix => split(" ", sd.dns_record)
  } : {}
}

# ACM domain-ownership validation record for the Amplify-managed cert.
resource "cloudflare_record" "cert_verification" {
  count = var.enable_custom_domain ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = try(trimsuffix(local.cert_verification[0], "."), "")
  type    = try(local.cert_verification[1], "CNAME")
  content = try(trimsuffix(local.cert_verification[2], "."), "")
  ttl     = 300
  proxied = false

  lifecycle {
    precondition {
      condition     = length(local.cert_verification) == 3
      error_message = "aws_amplify_domain_association.puffer_website returned an empty certificate_verification_dns_record for ${var.domain_name} -- ACM reused an already-validated certificate (e.g. ../amplify's app.pufferpanic.com cert validated first), so there is no new validation record to create. Comment out cloudflare_record.cert_verification and re-apply; the domain still verifies against the existing record."
    }
  }
}

# One record per served subdomain prefix. The apex ("") sets name to the
# bare domain -- Cloudflare CNAME-flattens at the zone apex, so an apex
# CNAME is valid here (no Route53-style ALIAS workaround needed).
#
# proxied = false (grey-cloud, DNS-only): Amplify already fronts this with
# its own CloudFront distribution and manages its own ACM certificate;
# stacking Cloudflare's proxy on top would be two CDNs in front of each
# other for no benefit, and would likely break Amplify's own domain
# verification besides.
resource "cloudflare_record" "subdomain" {
  for_each = var.enable_custom_domain ? toset(var.subdomain_prefixes) : toset([])

  zone_id = var.cloudflare_zone_id
  name    = each.value == "" ? var.domain_name : each.value
  type    = try(local.sub_records[each.value][1], "CNAME")
  content = try(trimsuffix(local.sub_records[each.value][2], "."), "")
  ttl     = 300
  proxied = false

  lifecycle {
    precondition {
      condition     = try(length(local.sub_records[each.value]) == 3, false)
      error_message = "aws_amplify_domain_association.puffer_website returned no dns_record for subdomain prefix '${each.key}' yet. Re-run `terraform apply` once the domain association has registered with Amplify."
    }
  }
}
