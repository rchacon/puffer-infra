output "table_name" {
  description = "DynamoDB table name (TABLE_NAME for puffer-api's Lambdas)."
  value       = aws_dynamodb_table.main.name
}

output "user_pool_id" {
  description = "Cognito user pool ID."
  value       = aws_cognito_user_pool.main.id
}

output "app_client_ids" {
  description = "Cognito app client IDs, keyed by app (game, portal). Public clients -- not secrets."
  value       = { for k, c in aws_cognito_user_pool_client.app : k => c.id }
}

output "appsync_api_id" {
  description = "AppSync API ID (APPSYNC_API_ID for puffer-api's graphql-v* pipeline)."
  value       = aws_appsync_graphql_api.main.id
}

output "appsync_data_source_name" {
  description = "AppSync DynamoDB data source name (APPSYNC_DATA_SOURCE_NAME)."
  value       = aws_appsync_datasource.table.name
}

output "graphql_url" {
  description = "GraphQL endpoint: the custom domain once enable_custom_domain = true, else AppSync's default URL."
  value       = var.enable_custom_domain ? "https://${local.api_hostname}/graphql" : aws_appsync_graphql_api.main.uris["GRAPHQL"]
}

output "graphql_stack_name" {
  description = "CloudFormation stack name the graphql-v* pipeline deploys (the deploy role is scoped to it)."
  value       = local.graphql_stack_name
}

output "lambda_function_names" {
  description = "Lambda function names, keyed by function."
  value       = { for k, f in aws_lambda_function.this : k => f.function_name }
}

output "deploy_role_arns" {
  description = "OIDC deploy role ARNs, keyed by tag prefix."
  value       = { for k, r in aws_iam_role.deploy : k => r.arn }
}
