# GitHub Actions repository variables on rchacon/puffer-api, read by its three
# deploy workflows (.github/workflows/deploy-*.yml) as `vars.<NAME>`. Fed
# straight from the resources, so a replaced role or function can't leave a
# stale value behind.
#
# Prod only: these are repository-level variables and each workflow deploys
# to whatever they name, so exactly one env can own them. A dev pipeline
# would need GitHub Environments in puffer-api (environment-scoped variables)
# first.

locals {
  github_actions_variables = local.is_prod ? {
    AWS_REGION = var.aws_region

    POSTCONFIRMATION_DEPLOY_ROLE_ARN = aws_iam_role.deploy["postconfirmation"].arn
    POST_CONFIRMATION_FUNCTION_NAME  = aws_lambda_function.this["post_confirmation"].function_name

    PROGRESSPROJECTOR_DEPLOY_ROLE_ARN = aws_iam_role.deploy["progressprojector"].arn
    PROGRESS_PROJECTOR_FUNCTION_NAME  = aws_lambda_function.this["progress_projector"].function_name

    GRAPHQL_DEPLOY_ROLE_ARN  = aws_iam_role.deploy["graphql"].arn
    APPSYNC_API_ID           = aws_appsync_graphql_api.main.id
    APPSYNC_DATA_SOURCE_NAME = aws_appsync_datasource.table.name
  } : {}
}

resource "github_actions_variable" "puffer_api" {
  for_each = local.github_actions_variables

  repository    = var.github_repository
  variable_name = each.key
  value         = each.value

  lifecycle {
    precondition {
      condition     = var.github_token != null
      error_message = "github_token is required for env = \"prod\" (it publishes puffer-api's GitHub Actions variables). See terraform/README.md."
    }
  }
}
