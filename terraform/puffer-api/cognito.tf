# One user pool shared by the game and the parent portal (true SSO), with an
# app client per app. Parents sign in through Cognito Managed Login (OAuth
# authorization code + PKCE). The Managed Login domain (auth.pufferpower.com),
# its branding, SES and the Google / Apple identity providers land in later
# PRs -- see #4.
#
# MFA is deliberately off for v1 (puffer-api docs/architecture.md, "Cognito"):
# per-user MFA would also challenge parents in the game. Revisit when the
# portal gets write access.

resource "aws_cognito_user_pool" "main" {
  name = local.name

  # Managed Login (v2 branding) requires Essentials or Plus.
  user_pool_tier = "ESSENTIALS"

  # Email is the username, verified by an emailed code.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Cognito's built-in sender (~50 emails/day) is fine until launch; prod
  # moves to SES with the Managed Login domain PR.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  mfa_configuration = "OFF"

  lambda_config {
    post_confirmation = aws_lambda_function.this["post_confirmation"].arn
  }

  deletion_protection = local.is_prod ? "ACTIVE" : "INACTIVE"

  tags = local.tags
}

# Public clients (no secret -- a browser / native app can't keep one), OAuth
# authorization code grant only. SRP + refresh token auth flows match the
# console's defaults for a single-page app client.
#
# prevent_user_existence_errors and token revocation are set per client in
# Cognito (there's no pool-level switch), so both clients set them.
locals {
  app_clients = {
    game = {
      callback_urls = var.game_callback_urls
      logout_urls   = var.game_logout_urls
      # A kid's tablet should stay signed in.
      refresh_token_days = 365
    }
    portal = {
      callback_urls      = var.portal_callback_urls
      logout_urls        = var.portal_logout_urls
      refresh_token_days = 30
    }
  }
}

resource "aws_cognito_user_pool_client" "app" {
  for_each = local.app_clients

  name         = each.key
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = each.value.callback_urls
  logout_urls                          = each.value.logout_urls

  # Google / SignInWithApple join this list once those providers exist.
  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = each.value.refresh_token_days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}
