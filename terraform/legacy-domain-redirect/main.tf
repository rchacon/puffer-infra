# Redirects the retired pufferpanic.com hostnames to their pufferpower.com
# equivalents (puffer-infra#5 -- the app was renamed because "Puffer Panic"
# collides with an existing iOS app). Path and query string are preserved,
# so old bookmarks and deep links still land in the right place.
#
# The redirect happens at Cloudflare's edge: no Amplify app (or anything
# else in AWS) has a domain association on pufferpanic.com anymore.

locals {
  # prefix => { from = "<prefix>.source_domain", to = "<prefix>.target_domain" },
  # with the apex ("") mapping to the bare domains.
  hosts = {
    for p in var.redirect_prefixes : p => {
      from = p == "" ? var.source_domain : "${p}.${var.source_domain}"
      to   = p == "" ? var.target_domain : "${p}.${var.target_domain}"
    }
  }
}

# Placeholder records so each hostname resolves to Cloudflare's edge, where
# the redirect rule below runs. `100::` is Cloudflare's documented
# "discard" IPv6 address for redirect-only hostnames -- nothing is ever
# served from it, because a proxied request is answered by the redirect
# before it would reach an origin.
#
# proxied = true (orange-cloud), unlike every other record in this repo:
# the Amplify modules' records are grey-cloud because Amplify's own
# CloudFront serves them, but here Cloudflare's proxy *is* the server --
# a grey-cloud record would hand clients the dead 100:: address directly
# and redirect rules would never run. Cloudflare's Universal SSL cert
# covers the apex and one level of subdomain (*.pufferpanic.com), which
# includes every prefix here.
resource "cloudflare_record" "redirect" {
  for_each = local.hosts

  zone_id = var.cloudflare_zone_id
  name    = each.value.from
  type    = "AAAA"
  content = "100::"
  ttl     = 1 # "automatic" -- required for proxied records
  proxied = true
}

# One Single Redirect rule per hostname (the zone's
# http_request_dynamic_redirect entry-point ruleset -- a zone has exactly
# one, and this resource owns all of it). Each target is built with
# concat() against a literal host rather than one regex_replace() rule over
# all hosts: regex functions in rule expressions depend on the Cloudflare
# plan, while concat() works on every plan. The free plan allows 10 Single
# Redirect rules, plenty for 3-4 hostnames.
#
# 301 (permanent): the rename is permanent, so let browsers and search
# engines cache the move.
resource "cloudflare_ruleset" "redirect" {
  zone_id     = var.cloudflare_zone_id
  name        = "Redirect ${var.source_domain} to ${var.target_domain}"
  description = "Redirect retired ${var.source_domain} hostnames to their ${var.target_domain} equivalents, preserving path and query string."
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  dynamic "rules" {
    for_each = local.hosts
    content {
      description = "${rules.value.from} -> ${rules.value.to}"
      expression  = "(http.host eq \"${rules.value.from}\")"
      action      = "redirect"
      enabled     = true

      action_parameters {
        from_value {
          status_code           = 301
          preserve_query_string = true
          target_url {
            expression = "concat(\"https://${rules.value.to}\", http.request.uri.path)"
          }
        }
      }
    }
  }
}
