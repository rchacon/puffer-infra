# Lambda *shells* for puffer-api's application Lambdas. Terraform creates the
# function, role, log group and wiring once, with placeholder code; each
# function's own tag pipeline (postconfirmation-v*, progressprojector-v*)
# replaces the code via `aws lambda update-function-code`. ignore_changes on
# the code attributes keeps a routine `terraform apply` from reverting a real
# deploy back to the placeholder -- the same shape as cd-infra's cd-api.
#
# Handler is index.handler: puffer-api's scripts/build.mjs emits a CJS
# index.js at the zip root for each Lambda.

locals {
  lambda_functions = {
    post_confirmation = {
      function_name = "${local.name}-post-confirmation"
      timeout       = 10 # Cognito gives triggers 5s; anything longer is moot
      memory_size   = 256
      # Cognito requires a trigger to return the event it was given, so a
      # no-op that does exactly that keeps sign-ups working before the first
      # real deploy (minus the parent profile it would have written).
      placeholder = "exports.handler = async (event) => event;"
    }
    progress_projector = {
      function_name = "${local.name}-progress-projector"
      # Covers the all-children rebuild ({"rebuild":{}}), a full table Scan.
      timeout     = 300
      memory_size = 256
      # Reports every record as processed. Summaries are rebuildable, so
      # anything this drops before the first real deploy is recovered by
      # invoking the real function with {"rebuild":{}} once.
      placeholder = "exports.handler = async () => ({ batchItemFailures: [] });"
    }
  }
}

data "archive_file" "placeholder" {
  for_each = local.lambda_functions

  type        = "zip"
  output_path = "${path.module}/build/${each.key}-placeholder.zip"

  source {
    filename = "index.js"
    content  = "// Placeholder -- puffer-api's deploy pipeline replaces this code.\n${each.value.placeholder}\n"
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  for_each = local.lambda_functions

  name               = each.value.function_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.tags
}

# Explicit log groups so retention is set (Lambda would otherwise create
# them on first invoke with infinite retention).
resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.lambda_functions

  name              = "/aws/lambda/${each.value.function_name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

data "aws_iam_policy_document" "lambda_logs" {
  for_each = local.lambda_functions

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda[each.key].arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda_logs" {
  for_each = local.lambda_functions

  name   = "logs"
  role   = aws_iam_role.lambda[each.key].id
  policy = data.aws_iam_policy_document.lambda_logs[each.key].json
}

resource "aws_lambda_function" "this" {
  for_each = local.lambda_functions

  function_name = each.value.function_name
  role          = aws_iam_role.lambda[each.key].arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = each.value.timeout
  memory_size   = each.value.memory_size

  filename         = data.archive_file.placeholder[each.key].output_path
  source_code_hash = data.archive_file.placeholder[each.key].output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

  tags = local.tags

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda_logs]

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# --- postConfirmation -----------------------------------------------------------
#
# Upserts PARENT#<sub>/PROFILE on sign-up: one PutCommand.

data "aws_iam_policy_document" "post_confirmation" {
  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.main.arn]
  }
}

resource "aws_iam_role_policy" "post_confirmation" {
  name   = "dynamodb"
  role   = aws_iam_role.lambda["post_confirmation"].id
  policy = data.aws_iam_policy_document.post_confirmation.json
}

resource "aws_lambda_permission" "cognito_post_confirmation" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this["post_confirmation"].function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

# --- progressProjector ----------------------------------------------------------
#
# Consumes the table's stream and overwrites progress summaries. IAM per
# puffer-api's docs/architecture.md ("What puffer-infra needs for derived
# progress"):
#   - stream read, for the event source mapping
#   - Query on the *base table* only -- never index/GSI1, which is only
#     eventually consistent; the projector's history read must be strongly
#     consistent
#   - PutItem (conditional) for the summaries
#   - Scan, only for the all-children rebuild

data "aws_iam_policy_document" "progress_projector" {
  statement {
    sid = "StreamRead"
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
    ]
    resources = [aws_dynamodb_table.main.stream_arn]
  }

  statement {
    sid       = "StreamList"
    actions   = ["dynamodb:ListStreams"]
    resources = ["${aws_dynamodb_table.main.arn}/stream/*"]
  }

  statement {
    sid       = "TableAccess"
    actions   = ["dynamodb:Query", "dynamodb:PutItem", "dynamodb:Scan"]
    resources = [aws_dynamodb_table.main.arn]
  }
}

resource "aws_iam_role_policy" "progress_projector" {
  name   = "dynamodb"
  role   = aws_iam_role.lambda["progress_projector"].id
  policy = data.aws_iam_policy_document.progress_projector.json
}

resource "aws_lambda_event_source_mapping" "progress_projector" {
  event_source_arn  = aws_dynamodb_table.main.stream_arn
  function_name     = aws_lambda_function.this["progress_projector"].arn
  starting_position = "LATEST"

  # The handler returns {batchItemFailures} so one bad record doesn't make
  # the whole batch retry.
  function_response_types = ["ReportBatchItemFailures"]

  # Bounded retries: the default (-1) retries a poison record until it ages
  # out of the stream (24h), blocking every record behind it on that shard.
  # Anything dropped here is recoverable with a rebuild.
  maximum_retry_attempts         = 10
  bisect_batch_on_function_error = true

  # Only inserted attempts. The projector re-checks this itself, but without
  # the filter every summary it writes would trigger another invocation.
  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT"]
        dynamodb = {
          NewImage = {
            SK = { S = [{ prefix = "ATTEMPT#" }] }
          }
        }
      })
    }
  }

  depends_on = [aws_iam_role_policy.progress_projector]
}
