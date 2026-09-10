variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-west-2"
}

# ../bootstrap has no S3 backend at all (it's what creates the state
# bucket), so this can't be read via terraform_remote_state -- copy the
# literal value from ../bootstrap's state_bucket_name output into a
# gitignored terraform.tfvars.
variable "state_bucket_name" {
  description = "S3 bucket holding Terraform state for the rest of terraform/ (../bootstrap's state_bucket_name output)."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository URL the Amplify app builds from. Requires the AWS Amplify GitHub App to already be installed/authorized for this repo AND the repo added to the App's repository access list (one-time manual steps -- see terraform/README.md)."
  type        = string
  default     = "https://github.com/rchacon/puffer-panic"
}

# Confirmed by AWS's own docs (Amplify user guide, "Setting up the Amplify
# GitHub App for CloudFormation, CLI, and SDK deployments"): CreateApp
# always requires a token, even with the GitHub App already installed --
# the "zero-token" experience only exists inside the Console's own UI flow.
# This token only needs the classic PAT scope `admin:repo_hook` -- it's
# used once at creation time purely to register Amplify's webhook, never to
# read/write repo contents (the GitHub App installation grants repo
# access).
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
# never the legacy account-wide Global API Key. Only used when
# enable_custom_domain = true.
variable "cloudflare_api_token" {
  description = "Cloudflare API token scoped to Zone:DNS:Edit for the domain's zone only."
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for domain_name (Cloudflare dashboard -> the domain's Overview tab, right sidebar). Only used when enable_custom_domain = true."
  type        = string
  default     = ""
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
  description = "Subdomain prefixes under domain_name that Amplify serves. \"\" is the apex; Cloudflare CNAME-flattens the apex so an apex CNAME is valid."
  type        = list(string)
  default     = ["", "www"]
}
