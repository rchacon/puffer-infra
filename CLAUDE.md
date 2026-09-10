# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture

Terraform IaC for deploying [Puffer Panic](https://github.com/rchacon/puffer-panic)
(a React 19 + Vite + TypeScript single-page app) to AWS Amplify Hosting.

Each directory under `terraform/` is its own Terraform root module with independent
state (S3 backend, native `use_lockfile` locking, no DynamoDB table):

- `bootstrap/` — one-time. Creates the S3 bucket that holds every other module's
  state. Applied once with **local state** (there's nothing else yet to store its own
  state in). The state bucket uses the **AWS-managed `aws/s3` KMS key**, not a
  customer-managed key.
- `amplify/` — the Amplify app + `main` branch, plus (gated behind
  `enable_custom_domain`) the `aws_amplify_domain_association` and the Cloudflare DNS
  records Amplify needs. Amplify manages its own ACM certificate for the domain, so
  there is no ACM resource here.

Modules read account-specific values (state bucket name, Cloudflare token/zone,
GitHub PAT) from a gitignored `backend.hcl` (backend config) and a gitignored
`terraform.tfvars` — never hardcoded into version-controlled `.tf` files. See
`terraform/README.md` for the exact contents to generate.

### Things worth knowing before touching this repo

- **DNS is Cloudflare, not Route53.** `amplify/` manages only the specific
  subdomain + certificate-verification records Amplify needs, as `cloudflare_record`
  resources with `proxied = false` (grey-cloud) — Amplify already fronts the app with
  its own CloudFront distribution, so proxying through Cloudflare on top would be two
  CDNs for no benefit and would likely break Amplify's domain verification.
- **Amplify's `dns_record` / `certificate_verification_dns_record` outputs are
  space-delimited strings** (`"<name> <TYPE> <VALUE>"`), parsed with `split(" ", ...)`
  and deliberately **not** `trimspace`d — the leading space on the empty-name apex
  record is significant.
- **The GitHub connection needs two manual, one-time steps** Terraform can't do:
  install the AWS Amplify GitHub App for `rchacon/puffer-panic`, *and* add that repo
  to the App's repository access list (GitHub → Settings → Applications). The
  `github_access_token` variable is only a classic PAT with `admin:repo_hook` scope,
  used once at `CreateApp` to register the webhook.
- **Two-pass apply for `amplify/`.** First apply with `enable_custom_domain = false`
  to stand up the app on its default `*.amplifyapp.com` URL and prove the build works;
  then set `enable_custom_domain = true` (plus `domain_name` and the `cloudflare_*`
  vars) and apply again to attach the custom domain.

## Standing agreement on `terraform apply`

`terraform plan` freely. Always get explicit confirmation before `terraform apply` —
it creates real, billable AWS resources.

## Git conventions

PRs are merged with a merge commit (`gh pr merge --merge`), not squash or rebase —
preserves the individual commit history from the PR branch. After merging, delete the
branch both locally and remotely (`gh pr merge --merge --delete-branch`).

## Commands

Validate without AWS credentials (the same checks CI runs on every PR via
`.github/workflows/terraform-checks.yml` — `fmt`, per-directory `validate`, and a
Trivy IaC security scan):

```bash
terraform fmt -check -recursive terraform/
for dir in $(find terraform -name '*.tf' -printf '%h\n' | sort -u); do
  terraform -chdir="$dir" init -backend=false -input=false
  terraform -chdir="$dir" validate
done
```

See `terraform/README.md` for full per-directory setup (backend.hcl / terraform.tfvars
generation, init / plan / apply).
