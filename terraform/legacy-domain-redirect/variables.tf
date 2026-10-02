# Needs two permissions on the pufferpanic.com zone: "Zone:DNS:Edit" (the
# placeholder records) and "Zone:Single Redirect:Edit" (the ruleset). Never
# the legacy account-wide Global API Key. Unlike ../amplify, there's no
# placeholder default -- this module has no pass without Cloudflare.
variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit + Zone:Single Redirect:Edit on source_domain's zone."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for source_domain (Cloudflare dashboard -> the domain's Overview tab, right sidebar)."
  type        = string
}

variable "source_domain" {
  description = "The retired domain whose hostnames redirect to target_domain."
  type        = string
  default     = "pufferpanic.com"
}

variable "target_domain" {
  description = "The domain every redirect lands on, with the same prefix and path."
  type        = string
  default     = "pufferpower.com"
}

# Mirrors the prefixes ../amplify and ../amplify-website served on the old
# domain ("app"; apex + "www"). These hostnames must NOT also have records
# in those modules' state -- apply this module only after both have moved
# to target_domain (see terraform/README.md, "Cutover order").
#
# "api" is deliberately absent: puffer-infra#4 provisions the API directly
# on api.pufferpower.com, and should append "api" here when it ships so
# api.pufferpanic.com redirects too.
variable "redirect_prefixes" {
  description = "Subdomain prefixes of source_domain to redirect (\"\" = the apex). Each <prefix>.source_domain 301s to <prefix>.target_domain."
  type        = list(string)
  default     = ["", "www", "app"]
}
