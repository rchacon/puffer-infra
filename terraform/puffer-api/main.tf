# Backend for Puffer Power (rchacon/puffer-api): Cognito, DynamoDB, AppSync
# and the shells of puffer-api's Lambdas. See puffer-api's
# docs/architecture.md for the full design.
#
# Ownership split -- Terraform creates each piece once; puffer-api's three
# tag-triggered pipelines only ever push new *code* into it:
#   - postconfirmation-v*  -> `aws lambda update-function-code` on the
#                             postConfirmation function (deploy role below)
#   - progressprojector-v* -> same, on the progressProjector function
#   - graphql-v*           -> a generated CloudFormation stack holding the
#                             schema, resolvers and pipeline functions
#                             (appsync.tf). Terraform owns the API and data
#                             source, never the schema.
#
# Files: main.tf (shared locals + DynamoDB), lambda.tf, cognito.tf,
# appsync.tf, domain.tf, deploy_roles.tf, github.tf.

data "aws_caller_identity" "current" {}

locals {
  name       = "puffer-power-${var.env}"
  account_id = data.aws_caller_identity.current.account_id
  is_prod    = var.env == "prod"

  tags = {
    Project = "puffer-power"
    App     = "api"
    Env     = var.env
  }
}

# --- DynamoDB: single table ----------------------------------------------------
#
# Mirrors puffer-api's scripts/create-table.js (the local equivalent) plus the
# stream. Named puffer-power-<env> (#3): a physical table name is unique per
# account + region, so dev and prod can never collide, and puffer-api's bare
# `TABLE_NAME ?? 'PufferPanicTable'` default is never relied on -- every
# Lambda gets TABLE_NAME explicitly (lambda.tf).
resource "aws_dynamodb_table" "main" {
  name         = local.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  # Sparse: only progress summaries carry GSI1PK/GSI1SK. Read by
  # childProgress (via the AppSync data source) to list a child's summaries
  # by status. Eventually consistent like every GSI, which is why the
  # projector deliberately never reads it.
  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  # Feeds progressProjector (lambda.tf). NEW_IMAGE is all it needs: it only
  # reacts to inserted attempts and reads the inserted item.
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  # Attempts are the irreplaceable source of truth (summaries are
  # rebuildable from them), so keep 35 days of point-in-time recovery.
  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = local.is_prod

  tags = local.tags
}
