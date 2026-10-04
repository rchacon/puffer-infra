# Amplify Hosting for the Puffer Power **classroom edition**
# (class.pufferpower.com) -- the same rchacon/puffer-app game as ../amplify,
# built from the same repo and branch, but as a separate Amplify app so its
# build-time environment can differ.
#
# The classroom edition is the free school-pilot build: guest play only,
# storing nothing outside the browser, so a teacher can get it approved
# without a data privacy agreement. That guarantee comes from what this
# app's build does NOT get: the game hides all account UI and makes no
# backend calls unless the VITE_COGNITO_* / VITE_GRAPHQL_URL account
# variables are present at build time. ../amplify (the home edition) will
# get those once the backend exists (#4); this app must never. The
# precondition on aws_amplify_app below enforces it, so a future edit can't
# quietly turn the pilot build into one that talks to the backend.
#
# Same build as ../amplify: puffer-app's repo-root amplify.yml (no
# build_spec here). Both apps auto-build on every push to the branch.
#
# Prerequisite: the AWS Amplify GitHub App must already have rchacon/puffer-app
# on its repository access list -- true already, since ../amplify builds the
# same repo -- so no new GitHub App step, just a github_access_token for
# CreateApp's webhook registration (see ../amplify/variables.tf).

locals {
  # Build-time env for the classroom edition. VITE_EDITION lets the game
  # tailor classroom-only bits (copy, the end-of-session summary) without a
  # second codebase; it's inert until the game reads it.
  environment_variables = {
    VITE_EDITION = "classroom"
  }

  # Prefixes of the game's account/backend variables (see
  # packages/account's accountConfig in puffer-app). Any of these in this
  # app's build would compile the account code in.
  forbidden_env_prefixes = ["VITE_COGNITO_", "VITE_GRAPHQL_"]
}

resource "aws_amplify_app" "puffer_classroom" {
  name         = "puffer-classroom"
  repository   = var.github_repository
  access_token = var.github_access_token
  platform     = "WEB"

  environment_variables = local.environment_variables

  # SPA fallback rewrite. Unlike the build spec, this stays in Terraform:
  # rewrites/redirects aren't part of amplify.yml, so this rule is live
  # config. The game has no client-side router, so this isn't strictly
  # required for the app to work, but it's harmless and keeps direct
  # navigation / refreshes on any unknown path returning the app instead of
  # a raw 404. This is AWS's own documented unconditional regex form, NOT
  # the fragile "/<*>" -> "/index.html" 404-200 pattern (cd-infra hit real
  # production breakage with the latter, #33): match any path with no
  # recognized static-file extension and rewrite to index.html. The
  # extension list must be exhaustive -- anything omitted gets rewritten to
  # text/html and breaks. `mp3`/`wav` are in the list because the game
  # ships committed audio clips under apps/game/public/audio/ that end up as
  # real files at /audio/*.mp3 in the deploy.
  custom_rule {
    source = "</^[^.]+$|\\.(?!(css|gif|ico|jpg|jpeg|js|json|map|mp3|png|svg|ttf|txt|wav|webp|woff|woff2)$)([^.]+$)/>"
    target = "/index.html"
    status = "200"
  }

  tags = {
    Project = "puffer-panic"
    App     = "classroom"
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for k in keys(local.environment_variables) :
        alltrue([for p in local.forbidden_env_prefixes : !startswith(k, p)])
      ])
      error_message = "The classroom edition must never be built with account/backend variables (${join(", ", local.forbidden_env_prefixes)}*): it's the no-data pilot build. Put them on ../amplify (home edition) instead."
    }
  }
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.puffer_classroom.id
  branch_name = var.branch_name

  enable_auto_build = true
  stage             = "PRODUCTION"

  tags = {
    Project = "puffer-panic"
    App     = "classroom"
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
resource "aws_amplify_domain_association" "puffer_classroom" {
  count = var.enable_custom_domain ? 1 : 0

  app_id                = aws_amplify_app.puffer_classroom.id
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
# field over by one. Index [0] is the record name, [1] the type, [2] the
# value; the value -- and, for cert_verification, the name -- can come back
# fully qualified with a trailing "." that Cloudflare doesn't store, so
# both get trimsuffix()'d. cloudflare_record.subdomain sets `name`
# explicitly instead and ignores [0].
#
# Either string can also come back EMPTY: `certificate_verification_dns_record`
# when ACM reused an already-validated cert for this domain (e.g. a sibling
# Amplify app / the marketing site validated one first), and a
# sub_domain.dns_record transiently right after the association is created.
# split(" ", "") is [""] (length 1), so a bare index would raise "Invalid
# index" mid-apply, after the domain association already exists. Each
# record below guards with try()/a precondition instead, so you get an
# actionable message and can re-run (or drop the cert record) rather than a
# stuck half-apply.
#
# sub_domain is a *set* of objects (unordered), so the map below is keyed
# by each object's known `prefix`. for_each on the resources themselves is
# driven by var.subdomain_prefixes (known at plan time), and only indexes
# into that map with those known keys.
locals {
  cert_verification = var.enable_custom_domain ? split(" ", aws_amplify_domain_association.puffer_classroom[0].certificate_verification_dns_record) : []

  sub_records = var.enable_custom_domain ? {
    for sd in aws_amplify_domain_association.puffer_classroom[0].sub_domain :
    sd.prefix => split(" ", sd.dns_record)
  } : {}
}

# ACM domain-ownership validation record for the Amplify-managed cert.
#
# Disabled (count = 0), same as ../amplify-website: ../amplify's
# app.pufferpower.com certificate is already validated for this domain, so
# ACM reuses that validation and certificate_verification_dns_record comes
# back empty -- and if it didn't, its record name would collide with the
# one ../amplify already manages in the same Cloudflare zone. Re-enable
# (count = 1) only if an apply shows local.cert_verification naming a
# genuinely different record (e.g. this app ever moves to an AWS account
# where nothing has validated the domain yet -- see puffer-infra#11).
resource "cloudflare_record" "cert_verification" {
  count = 0

  zone_id = var.cloudflare_zone_id
  name    = try(trimsuffix(local.cert_verification[0], "."), "")
  type    = try(local.cert_verification[1], "CNAME")
  content = try(trimsuffix(local.cert_verification[2], "."), "")
  ttl     = 300
  proxied = false

  lifecycle {
    precondition {
      condition     = length(local.cert_verification) == 3
      error_message = "aws_amplify_domain_association.puffer_classroom returned an empty certificate_verification_dns_record for ${var.domain_name} -- ACM reused an already-validated certificate, so there is no new validation record to create. Leave cloudflare_record.cert_verification at count = 0; the domain still verifies against the existing record."
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
      error_message = "aws_amplify_domain_association.puffer_classroom returned no dns_record for subdomain prefix '${each.key}' yet. Re-run `terraform apply` once the domain association has registered with Amplify."
    }
  }
}
