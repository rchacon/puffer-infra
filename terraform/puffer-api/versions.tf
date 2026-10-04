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
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # Partial configuration, same as ../amplify: bucket/key/region come from a
  # gitignored backend.hcl. One state per environment -- the key is
  # puffer-api/<env>/terraform.tfstate, and each env has its own tfvars
  # setting `env` (see terraform/README.md).
  backend "s3" {
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

# AppSync custom domains are served through CloudFront, so their ACM
# certificate must live in us-east-1 regardless of the API's own region (the
# same rule as Cognito custom domains). Only the certificate and its
# validation use this provider.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Writes the GitHub Actions repository variables puffer-api's deploy
# workflows read (github.tf). With no token (non-prod envs, which don't
# publish variables) the provider runs anonymously and is never called.
provider "github" {
  owner = var.github_owner
  token = var.github_token
}
