# OIDC-trusted roles for puffer-api's three tag-triggered deploy workflows,
# one per tag prefix, so each pipeline can only touch its own component.
#
# The GitHub OIDC provider itself is an account-wide singleton that already
# exists in this account (created by cd-infra's bootstrap -- this account is
# shared with cd-platform). It's referenced by its deterministic ARN rather
# than created or looked up, which also avoids needing iam:List* on
# providers.

locals {
  github_oidc_provider_arn = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"

  # Immutable subject format -- see variables.tf's GitHub section.
  github_tag_subject_prefix = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:ref:refs/tags/"

  # puffer-api's deploy-graphql.yml hardcodes `--stack-name
  # puffer-api-graphql`. Prod keeps that name; other envs get a suffix
  # (puffer-api will need to read it from a variable once a dev pipeline
  # exists).
  graphql_stack_name = local.is_prod ? "puffer-api-graphql" : "puffer-api-graphql-${var.env}"

  deploy_roles = {
    postconfirmation  = { tag_prefix = "postconfirmation-v" }
    progressprojector = { tag_prefix = "progressprojector-v" }
    graphql           = { tag_prefix = "graphql-v" }
  }
}

data "aws_iam_policy_document" "deploy_assume_role" {
  for_each = local.deploy_roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_tag_subject_prefix}${each.value.tag_prefix}*"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each = local.deploy_roles

  name               = "${local.name}-${each.key}-deploy"
  assume_role_policy = data.aws_iam_policy_document.deploy_assume_role[each.key].json
  tags               = local.tags
}

# --- Lambda deploys (postconfirmation-v*, progressprojector-v*) ------------------
#
# `aws lambda update-function-code` + `aws lambda wait function-updated`
# (which polls GetFunctionConfiguration).

locals {
  lambda_deploy_targets = {
    postconfirmation  = "post_confirmation"
    progressprojector = "progress_projector"
  }
}

data "aws_iam_policy_document" "lambda_deploy" {
  for_each = local.lambda_deploy_targets

  statement {
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
    ]
    resources = [aws_lambda_function.this[each.value].arn]
  }
}

resource "aws_iam_role_policy" "lambda_deploy" {
  for_each = local.lambda_deploy_targets

  name   = "deploy"
  role   = aws_iam_role.deploy[each.key].id
  policy = data.aws_iam_policy_document.lambda_deploy[each.key].json
}

# --- GraphQL deploy (graphql-v*) -------------------------------------------------
#
# `aws cloudformation deploy` of the generated template, with no CloudFormation
# service role -- so the stack's AppSync calls (schema, resolvers, functions)
# run as this role too. AppSync access is scoped to this one API.

data "aws_iam_policy_document" "graphql_deploy" {
  statement {
    sid = "CloudFormationStack"
    actions = [
      "cloudformation:CreateChangeSet",
      "cloudformation:DescribeChangeSet",
      "cloudformation:ExecuteChangeSet",
      "cloudformation:DeleteChangeSet",
      "cloudformation:DescribeStacks",
      "cloudformation:DescribeStackEvents",
      "cloudformation:DescribeStackResources",
      "cloudformation:GetTemplate",
      "cloudformation:ListStackResources",
    ]
    resources = ["arn:aws:cloudformation:${var.aws_region}:${local.account_id}:stack/${local.graphql_stack_name}/*"]
  }

  # These two don't support resource-level permissions.
  statement {
    sid       = "CloudFormationTemplate"
    actions   = ["cloudformation:GetTemplateSummary", "cloudformation:ValidateTemplate"]
    resources = ["*"]
  }

  statement {
    sid     = "AppSyncApi"
    actions = ["appsync:*"]
    resources = [
      aws_appsync_graphql_api.main.arn,
      "${aws_appsync_graphql_api.main.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "graphql_deploy" {
  name   = "deploy"
  role   = aws_iam_role.deploy["graphql"].id
  policy = data.aws_iam_policy_document.graphql_deploy.json
}
