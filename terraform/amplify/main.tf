# Amplify Hosting for puffer-panic (rchacon/puffer-panic) -- a React 19 +
# Vite 8 + TypeScript single-page app. `npm run build` runs `tsc -b && vite
# build`; the output directory is Vite's default `dist`. The app has no
# router and reads no VITE_* env vars (only Vite's built-in
# import.meta.env.BASE_URL), so this is a plain single-app build, no
# environment_variables block needed.
#
# One-time manual prerequisites before `terraform apply` works (see
# terraform/README.md): install the AWS Amplify GitHub App for the repo
# AND add the repo to the App's repository access list (both steps -- the
# second is easy to miss and its build failure, "Unable to assume
# specified IAM Role", points nowhere near the real cause).

resource "aws_amplify_app" "puffer_panic" {
  name         = "puffer-panic"
  repository   = var.github_repository
  access_token = var.github_access_token
  platform     = "WEB"

  # The repo has no .nvmrc / package.json "engines", and Vite 8 requires
  # Node 20.19+ or 22.12+ -- pin it explicitly here rather than relying on
  # whatever the Amplify build image happens to default to. `nvm` is
  # preinstalled on Amplify's managed build image with several Node
  # versions available.
  build_spec = <<-YAML
    version: 1
    frontend:
      phases:
        preBuild:
          commands:
            - nvm use 22 || nvm install 22
            - npm ci
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: dist
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  YAML

  # SPA fallback rewrite. puffer-panic has no client-side router, so this
  # isn't strictly required for the app to work, but it's harmless and
  # keeps direct navigation / refreshes on any unknown path returning the
  # app instead of a raw 404. This is AWS's own documented unconditional
  # regex form, NOT the fragile "/<*>" -> "/index.html" 404-200 pattern
  # (cd-infra hit real production breakage with the latter, #33): match any
  # path with no recognized static-file extension and rewrite to
  # index.html. The extension list must be exhaustive -- anything omitted
  # gets rewritten to text/html and breaks. `mp3`/`wav` are in the list
  # because puffer-panic ships committed audio clips under public/audio/
  # that end up as real files at /audio/*.mp3 in the deploy.
  custom_rule {
    source = "</^[^.]+$|\\.(?!(css|gif|ico|jpg|jpeg|js|json|map|mp3|png|svg|ttf|txt|wav|webp|woff|woff2)$)([^.]+$)/>"
    target = "/index.html"
    status = "200"
  }

  tags = {
    Project = "puffer-panic"
  }
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.puffer_panic.id
  branch_name = var.branch_name

  enable_auto_build = true
  stage             = "PRODUCTION"

  tags = {
    Project = "puffer-panic"
  }
}

# --- Custom domain (gated on enable_custom_domain) -----------------------
#
# wait_for_verification = false: this resource's own outputs
# (certificate_verification_dns_record, sub_domain[*].dns_record) are what
# the cloudflare_record resources below are built from, so the records this
# association needs to verify against don't exist yet at the moment this
# resource is created -- waiting here would deadlock against DNS that
# hasn't been created. Verification happens asynchronously in AWS's backend
# once the Cloudflare records exist; check status via the Amplify console
# or a follow-up `terraform plan`, not apply's exit code for this one
# resource. Amplify provisions and manages its own ACM certificate for the
# domain association -- unlike Cognito / API Gateway custom domains, there
# is no ACM resource to declare here.
resource "aws_amplify_domain_association" "puffer_panic" {
  count = var.enable_custom_domain ? 1 : 0

  app_id                = aws_amplify_app.puffer_panic.id
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
# Amplify's dns_record / certificate_verification_dns_record outputs are
# plain, loosely-documented, space-delimited strings of the shape
# "<name-or-empty> <TYPE> <VALUE>" -- e.g. `"www CNAME xyz.cloudfront.net"`,
# or `" CNAME xyz.cloudfront.net"` (leading space, empty name) for the
# apex. Deliberately NOT trimspace()'d before splitting -- trimming would
# eat that meaningful leading space on the empty-name case and shift every
# field over by one. Index [0] is the name (unused -- each record sets
# `name` explicitly), [1] the type, [2] the value (which comes fully
# qualified with a trailing "." that Cloudflare doesn't store).
#
# sub_domain is a *set* of objects (unordered), so the map below is keyed
# by each object's known `prefix`. for_each on the resources themselves is
# driven by var.subdomain_prefixes (known at plan time), and only indexes
# into that map with those known keys.
locals {
  cert_verification = var.enable_custom_domain ? split(" ", aws_amplify_domain_association.puffer_panic[0].certificate_verification_dns_record) : []

  sub_records = var.enable_custom_domain ? {
    for sd in aws_amplify_domain_association.puffer_panic[0].sub_domain :
    sd.prefix => split(" ", sd.dns_record)
  } : {}
}

# ACM domain-ownership validation record for the Amplify-managed cert.
resource "cloudflare_record" "cert_verification" {
  count = var.enable_custom_domain ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = local.cert_verification[0]
  type    = local.cert_verification[1]
  content = trimsuffix(local.cert_verification[2], ".")
  ttl     = 300
  proxied = false
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
  type    = local.sub_records[each.value][1]
  content = trimsuffix(local.sub_records[each.value][2], ".")
  ttl     = 300
  proxied = false
}
