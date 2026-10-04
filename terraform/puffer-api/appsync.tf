# The AppSync API and its DynamoDB data source. The schema, resolvers and
# pipeline functions are NOT here: puffer-api's graphql-v* pipeline deploys
# them as a generated CloudFormation stack (scripts/generate-appsync-template.mjs)
# that takes this API's ID and the data source's name as parameters. Setting
# `schema` here would fight that stack on every apply.

resource "aws_appsync_graphql_api" "main" {
  name                = local.name
  authentication_type = "AMAZON_COGNITO_USER_POOLS"

  # Every resolver scopes reads/writes by the caller's Cognito `sub`.
  user_pool_config {
    user_pool_id   = aws_cognito_user_pool.main.id
    aws_region     = var.aws_region
    default_action = "ALLOW"
  }

  # Resolver errors only, without request/response bodies (they carry
  # children's names and answers).
  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_logs.arn
    field_log_level          = "ERROR"
    exclude_verbose_content  = true
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [schema]
  }
}

resource "aws_cloudwatch_log_group" "appsync" {
  name              = "/aws/appsync/apis/${aws_appsync_graphql_api.main.id}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

data "aws_iam_policy_document" "appsync_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["appsync.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "appsync_logs" {
  name               = "${local.name}-appsync-logs"
  assume_role_policy = data.aws_iam_policy_document.appsync_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "appsync_logs" {
  role       = aws_iam_role.appsync_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppSyncPushToCloudWatchLogs"
}

# --- DynamoDB data source -------------------------------------------------------
#
# Name is alphanumeric/underscore only (AppSync rejects hyphens), and is
# published to puffer-api as APPSYNC_DATA_SOURCE_NAME.

resource "aws_appsync_datasource" "table" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "PufferTable"
  type             = "AMAZON_DYNAMODB"
  service_role_arn = aws_iam_role.appsync_datasource.arn

  dynamodb_config {
    table_name = aws_dynamodb_table.main.name
    region     = var.aws_region
  }
}

resource "aws_iam_role" "appsync_datasource" {
  name               = "${local.name}-appsync-datasource"
  assume_role_policy = data.aws_iam_policy_document.appsync_assume_role.json
  tags               = local.tags
}

# Exactly the operations puffer-api's resolvers issue today (GetItem,
# PutItem, Query), plus Query on index/GSI1 for childProgress. A resolver
# using a new operation needs it added here first.
data "aws_iam_policy_document" "appsync_datasource" {
  statement {
    sid       = "Table"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
    resources = [aws_dynamodb_table.main.arn]
  }

  statement {
    sid       = "GSI1"
    actions   = ["dynamodb:Query"]
    resources = ["${aws_dynamodb_table.main.arn}/index/GSI1"]
  }
}

resource "aws_iam_role_policy" "appsync_datasource" {
  name   = "dynamodb"
  role   = aws_iam_role.appsync_datasource.id
  policy = data.aws_iam_policy_document.appsync_datasource.json
}
