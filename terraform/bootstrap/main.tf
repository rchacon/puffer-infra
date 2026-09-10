# One-time bootstrap: creates the S3 bucket that holds Terraform's OWN
# state for every other terraform/ directory in this repo (amplify/, and
# anything added later). State locking uses the S3 backend's native
# `use_lockfile` (Terraform >= 1.10), so no separate DynamoDB table is
# needed. Applied once, with local state -- there's nothing else yet to
# store this config's own state in. Not touched again as part of normal
# day-to-day workflow once it exists.

terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# Bucket name includes the account ID since S3 bucket names must be
# globally unique across every AWS account, not just this one.
resource "aws_s3_bucket" "terraform_state" {
  bucket = "puffer-panic-terraform-state-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# AWS-managed key (aws/s3), not a customer-managed CMK: leaving
# kms_master_key_id unset with sse_algorithm = "aws:kms" selects the
# account's aws/s3 managed key -- nothing to provision, rotate, or pay a
# monthly key charge for. `encrypt = true` in each module's backend.hcl
# still applies on top of this bucket-default encryption.
#
# trivy:ignore:AVD-AWS-0132 -- deliberate: a customer-managed KMS key was
# considered and rejected for this project (single small state bucket, one
# maintainer); the AWS-managed key is the intentional choice here, not an
# oversight.
#trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
