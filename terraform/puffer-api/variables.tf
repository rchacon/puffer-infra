variable "aws_region" {
  description = "AWS region for everything except the custom domain's ACM certificate (always us-east-1)."
  type        = string
  default     = "us-west-2"
}

# Names every resource (puffer-power-<env>) and selects env-specific
# behavior: only prod gets deletion protection, and only prod publishes
# puffer-api's GitHub Actions variables (its tag-triggered workflows have one
# set of repository variables, so they deploy to exactly one env).
variable "env" {
  description = "Environment name: \"prod\" or \"dev\". One state file per env."
  type        = string

  validation {
    condition     = contains(["prod", "dev"], var.env)
    error_message = "env must be \"prod\" or \"dev\"."
  }
}

# --- Lambda ---------------------------------------------------------------

# puffer-api bundles its Lambdas with esbuild `target: 'node20'` (CJS), which
# runs unchanged on Node 22. Node 20 is past end of life on Lambda.
variable "lambda_runtime" {
  description = "Node.js runtime for puffer-api's Lambda functions."
  type        = string
  default     = "nodejs22.x"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the Lambda and AppSync log groups."
  type        = number
  default     = 30
}

# --- Cognito app clients ------------------------------------------------------
#
# Defaults are prod's. A dev tfvars adds its localhost URLs (e.g.
# http://localhost:5173/auth/callback). The logout URLs must match exactly
# what puffer-app passes as `logout_uri`.

variable "game_callback_urls" {
  description = "OAuth callback URLs for the game app client (web + Capacitor native scheme)."
  type        = list(string)
  default = [
    "https://app.pufferpower.com/auth/callback",
    "com.pufferpower.app://auth/callback",
  ]
}

variable "game_logout_urls" {
  description = "Sign-out redirect URLs for the game app client."
  type        = list(string)
  default = [
    "https://app.pufferpower.com/auth/logout",
    "com.pufferpower.app://auth/logout",
  ]
}

variable "portal_callback_urls" {
  description = "OAuth callback URLs for the parent portal app client."
  type        = list(string)
  default     = ["https://portal.pufferpower.com/auth/callback"]
}

variable "portal_logout_urls" {
  description = "Sign-out redirect URLs for the parent portal app client."
  type        = list(string)
  default     = ["https://portal.pufferpower.com/auth/logout"]
}

# --- Custom domain (gated, same two-pass shape as ../amplify) ------------------

variable "enable_custom_domain" {
  description = "Whether to attach the API's custom domain (<api_subdomain>.<domain_name>): ACM cert + AppSync domain + Cloudflare records."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Cloudflare-hosted domain the API's custom domain lives under."
  type        = string
  default     = "pufferpower.com"
}

variable "api_subdomain" {
  description = "Subdomain for the GraphQL API's custom domain. \"api\" for prod; use e.g. \"api-dev\" for dev."
  type        = string
  default     = "api"
}

# Zone:DNS:Edit on the pufferpower.com zone, same token as ../amplify. The
# default is the same well-formed placeholder ../amplify uses, so a pass with
# enable_custom_domain = false needs no Cloudflare credentials.
variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit on domain_name's zone. Required when enable_custom_domain = true."
  type        = string
  sensitive   = true
  default     = "unsetunsetunsetunsetunsetunsetunsetunset"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for domain_name. Required when enable_custom_domain = true."
  type        = string
  default     = null
}

# --- GitHub (puffer-api's deploy pipelines) -------------------------------------
#
# puffer-api uses GitHub's immutable OIDC subject format (its repo-level
# `use_immutable_subject` is on), so tokens carry
# `repo:rchacon@2160525/puffer-api@1370519811:ref:refs/tags/<tag>` -- owner
# and repo *IDs*, not just names. A trust policy written as
# `repo:rchacon/puffer-api:...` would never match. Check with
# `gh api repos/rchacon/puffer-api/actions/oidc/customization/sub`.

variable "github_owner" {
  description = "GitHub owner of the puffer-api repository."
  type        = string
  default     = "rchacon"
}

variable "github_owner_id" {
  description = "Numeric GitHub ID of github_owner (part of the immutable OIDC subject)."
  type        = string
  default     = "2160525"
}

variable "github_repository" {
  description = "Repository whose tag-triggered workflows deploy puffer-api's code."
  type        = string
  default     = "puffer-api"
}

variable "github_repository_id" {
  description = "Numeric GitHub ID of github_repository (part of the immutable OIDC subject)."
  type        = string
  default     = "1370519811"
}

# Fine-grained PAT scoped to rchacon/puffer-api only, permission
# "Variables: Read and write" (plus the implied "Metadata: Read"). Only
# needed by the env that publishes variables (prod).
variable "github_token" {
  description = "GitHub fine-grained token with Variables: read/write on github_repository. Required for prod; leave unset for other envs."
  type        = string
  sensitive   = true
  default     = null
}
