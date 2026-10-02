terraform {
  required_version = ">= 1.15"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  # Partial configuration, same as ../amplify: bucket/key/region come from
  # a gitignored backend.hcl (`terraform init -backend-config=backend.hcl`).
  # No aws provider is declared -- this module creates no AWS resources; the
  # S3 backend picks up credentials from the standard AWS credential chain
  # on its own.
  backend "s3" {
    use_lockfile = true
  }
}

# Scoped to the pufferpanic.com zone only -- see variables.tf.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
