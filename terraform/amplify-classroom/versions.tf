terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  # Partial configuration -- bucket/key/region are supplied via `terraform
  # init -backend-config=backend.hcl` (gitignored), using the
  # state_bucket_name output from ../bootstrap. Left empty here since the
  # bucket name is account-specific and shouldn't be hardcoded into
  # version-controlled config. `use_lockfile` (native S3 state locking,
  # Terraform >= 1.10) isn't account-specific, so it's set directly here
  # instead of routed through backend.hcl.
  backend "s3" {
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

# The domain's DNS is hosted at Cloudflare (this module never registers or
# migrates it). This provider only ever creates the subdomain +
# certificate-verification records Amplify needs -- see main.tf.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
