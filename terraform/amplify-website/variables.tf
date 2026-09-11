variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-west-2"
}

# ../bootstrap has no S3 backend at all (it's what creates the state
# bucket), so this can't be read via terraform_remote_state -- copy the
# literal value from ../bootstrap's state_bucket_name output into a
# gitignored terraform.tfvars. Same bucket ../amplify uses -- this module
# just writes to a different state key (see backend.hcl).
variable "state_bucket_name" {
  description = "S3 bucket holding Terraform state for the rest of terraform/ (../bootstrap's state_bucket_name output)."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository URL the Amplify app builds from. Requires the AWS Amplify GitHub App to already be installed/authorized for this repo AND the repo added to the App's repository access list (one-time manual steps -- see terraform/README.md). Note this repo is named pufferpanic.com on GitHub, not puffer-website -- that's the local clone's directory name only."
  type        = string
  default     = "https://github.com/rchacon/pufferpanic.com"
}

# See ../amplify/variables.tf for why CreateApp always needs a token even
# with the GitHub App already installed. Scope: admin:repo_hook only, used
# once to register Amplify's webhook -- never to read/write repo contents.
variable "github_access_token" {
  description = "GitHub personal access token (classic), scope: admin:repo_hook only. One-time bootstrapping credential for CreateApp's webhook registration."
  type        = string
  sensitive   = true
}

variable "branch_name" {
  description = "Git branch the Amplify app builds and auto-deploys from."
  type        = string
  default     = "main"
}

variable "domain_name" {
  description = "Apex domain served by the Amplify app -- pufferpanic.com, registered and DNS-hosted in Cloudflare. Only used when enable_custom_domain = true."
  type        = string
  default     = "pufferpanic.com"
}

# Scoped to "Zone:DNS:Edit" on this one zone (Cloudflare dashboard -> My
# Profile -> API Tokens -> Create Token -> "Edit zone DNS" template) --
# never the legacy account-wide Global API Key. Can be the same token
# ../amplify uses (same zone), just copied into this module's own tfvars --
# root modules don't share variables.
#
# The default is a deliberate well-formed placeholder: the cloudflare
# provider block is always instantiated and its api_token validator
# demands a 40-char [A-Za-z0-9-_] string, even for Pass 1 where
# enable_custom_domain = false and no cloudflare_* resource exists. This
# junk token is never sent anywhere in that case. Pass 2 overrides it with
# the real token in terraform.tfvars.
variable "cloudflare_api_token" {
  description = "Cloudflare API token scoped to Zone:DNS:Edit for the domain's zone only. Required when enable_custom_domain = true; leave as the default otherwise."
  type        = string
  sensitive   = true
  default     = "unsetunsetunsetunsetunsetunsetunsetunset"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for domain_name (Cloudflare dashboard -> the domain's Overview tab, right sidebar). Required only when enable_custom_domain = true."
  type        = string
  default     = null
}

# Gates the domain association + Cloudflare records so the first apply can
# stand up just the app/branch on the default *.amplifyapp.com URL --
# before the Cloudflare zone/token exist, and with zero DNS risk. Flip to
# true (and set domain_name / cloudflare_*) for the second apply.
variable "enable_custom_domain" {
  description = "Whether to attach the custom domain (aws_amplify_domain_association + Cloudflare DNS records)."
  type        = bool
  default     = false
}

variable "subdomain_prefixes" {
  description = "Subdomain prefixes under domain_name that Amplify serves. Default is [\"\", \"www\"] -> pufferpanic.com + www.pufferpanic.com. This is the marketing site's module -- it's the one place in this repo allowed to claim the apex/www records; keep ../amplify's subdomain_prefixes disjoint from these (currently [\"app\"])."
  type        = list(string)
  default     = ["", "www"]
}
