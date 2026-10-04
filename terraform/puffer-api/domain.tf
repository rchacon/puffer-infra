# Custom domain for the GraphQL API (api.pufferpower.com for prod), gated on
# enable_custom_domain like ../amplify's: the first apply proves the API on its
# default *.appsync-api URL, the second attaches the domain.
#
# Unlike Amplify, AppSync doesn't manage a certificate for you: this module
# requests one in ACM -- in us-east-1, because AppSync custom domains are
# CloudFront-backed -- validates it through Cloudflare, then points a
# grey-cloud CNAME at the AppSync domain. Same shape as cd-infra's cd-api
# custom domain.

locals {
  api_hostname = "${var.api_subdomain}.${var.domain_name}"
}

resource "aws_acm_certificate" "api" {
  count    = var.enable_custom_domain ? 1 : 0
  provider = aws.us_east_1

  domain_name       = local.api_hostname
  validation_method = "DNS"
  tags              = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

# One hostname, no SANs, so domain_validation_options (a set) has exactly one
# element. trimsuffix: ACM returns fully-qualified names/values with a
# trailing "." that Cloudflare doesn't store.
locals {
  api_cert_validation = var.enable_custom_domain ? tolist(aws_acm_certificate.api[0].domain_validation_options)[0] : null
}

resource "cloudflare_record" "api_cert_validation" {
  count = var.enable_custom_domain ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(local.api_cert_validation.resource_record_name, ".")
  type    = local.api_cert_validation.resource_record_type
  content = trimsuffix(local.api_cert_validation.resource_record_value, ".")
  ttl     = 300
  proxied = false
}

# No wait_for_verification workaround needed (unlike ../amplify's domain
# association): cert -> Cloudflare record -> validation is an ordinary
# dependency chain, so the DNS exists by the time this waits on it.
resource "aws_acm_certificate_validation" "api" {
  count    = var.enable_custom_domain ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.api[0].arn
  validation_record_fqdns = [cloudflare_record.api_cert_validation[0].hostname]
}

resource "aws_appsync_domain_name" "api" {
  count = var.enable_custom_domain ? 1 : 0

  domain_name     = local.api_hostname
  certificate_arn = aws_acm_certificate_validation.api[0].certificate_arn
}

resource "aws_appsync_domain_name_api_association" "api" {
  count = var.enable_custom_domain ? 1 : 0

  api_id      = aws_appsync_graphql_api.main.id
  domain_name = aws_appsync_domain_name.api[0].domain_name
}

# Grey-cloud (DNS-only), like every Amplify record in this repo: the AppSync
# domain is already CloudFront-backed. AppSync allows any origin, so the
# Capacitor WebView origins (capacitor://localhost, https://localhost) work
# without a CORS allow-list.
resource "cloudflare_record" "api" {
  count = var.enable_custom_domain ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.api_subdomain
  type    = "CNAME"
  content = aws_appsync_domain_name.api[0].appsync_domain_name
  ttl     = 300
  proxied = false
}
