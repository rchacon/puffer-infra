# terraform/

Each subdirectory is an independent Terraform root module. Apply `bootstrap/` once,
then `amplify/` before `amplify-website/` (see the cert-reuse note under
`amplify-website/`), then `legacy-domain-redirect/`. `puffer-api/` (the backend) is
independent of the Amplify modules and has one state per environment.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.15
- AWS credentials for the target account (env vars, an AWS CLI profile, or SSO —
  anything the AWS provider's standard credential chain picks up)
- For `amplify/` and `amplify-website/` (same requirements, against different repos):
  - The **AWS Amplify GitHub App** installed/authorized for the app's repo
    (`rchacon/puffer-app` for `amplify/`, `rchacon/puffer-website` for
    `amplify-website/`), **and** that repo added to the App's repository access list
    (GitHub → Settings → Applications → AWS Amplify → Configure) — each repo has to be
    added individually. Both steps are required — a missing repo on the access list
    fails the first build with a misleading `Unable to assume specified IAM Role`.
  - A **GitHub personal access token** (classic), scope **`admin:repo_hook` only** —
    used once at `CreateApp` to register Amplify's webhook. Can be the same token for
    both modules.
  - For the custom domain (second apply only): the domain hosted as a **zone in
    Cloudflare**, a **Cloudflare API token** scoped `Zone:DNS:Edit` on that zone
    (dashboard → My Profile → API Tokens → "Edit zone DNS" template), and the
    **Zone ID** (dashboard → the domain's Overview tab). Both modules point at the
    same `pufferpower.com` zone — the token/zone ID can be reused, just copied into
    each module's own `terraform.tfvars`.

## `bootstrap/` — one-time state backend

Creates the S3 bucket that holds every other module's Terraform state (state locking
uses the S3 backend's native `use_lockfile`, so no separate lock table is needed).
Encryption is the AWS-managed `aws/s3` KMS key. Run once per AWS account, with local
state:

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output   # note state_bucket_name
```

The `state_bucket_name` output is what `amplify/`'s and `amplify-website/`'s
`backend.hcl` and `terraform.tfvars` need below — Terraform backend blocks can't
reference outputs, and `bootstrap/` has no S3 backend to read via
`terraform_remote_state`, so the value is copied by hand into each module's files.

## `amplify/` — Amplify Hosting + Cloudflare DNS

Backend config and account-specific variables are supplied via gitignored files.

```bash
cd terraform/amplify

cat > backend.hcl <<EOF
bucket  = "<state_bucket_name from bootstrap output>"
key     = "amplify/terraform.tfstate"
region  = "us-west-2"
encrypt = true
EOF

cat > terraform.tfvars <<EOF
state_bucket_name   = "<state_bucket_name from bootstrap output>"
github_access_token = "<classic PAT, scope admin:repo_hook only>"
EOF

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

### Two-pass apply

Stand the app up on its default URL first, then attach the custom domain — so the
build is proven before any DNS changes, and the Cloudflare zone/token aren't needed
until the second pass.

**Pass 1 — app on the default URL** (`enable_custom_domain` defaults to `false`):

```bash
terraform apply
open "$(terraform output -raw default_domain)"
```

Confirm the build succeeds in the Amplify console and the game loads (start screen
renders, a round plays, audio prompts play). Push a trivial commit to `main` and
confirm auto-build fires.

**Pass 2 — custom domain.** Add the domain settings to `terraform.tfvars`:

```hcl
enable_custom_domain = true
cloudflare_api_token = "<Zone:DNS:Edit token for the pufferpower.com zone>"
cloudflare_zone_id   = "<zone ID from the pufferpower.com Overview tab>"
# domain_name defaults to "pufferpower.com"
# subdomain_prefixes defaults to ["app"] -> app.pufferpower.com; override if you want something else
```

```bash
terraform plan    # expect: 1 aws_amplify_domain_association + the cloudflare_record resources
terraform apply
```

The new Cloudflare records are additive (grey-cloud, `proxied = false`) and don't
touch any existing zone records. This module only ever manages the `app` subdomain —
the apex (`pufferpower.com`) and `www` are reserved for a separate Puffer Panic
marketing site. Domain verification is asynchronous — watch the
Amplify console's **Custom domains** tab (or re-run `terraform plan`); don't trust
`apply`'s exit code for the domain association. Once it shows **Available**:

```bash
dig +short app.pufferpower.com
curl -sI https://app.pufferpower.com | head -1
```

## `amplify-website/` — marketing site Amplify Hosting + Cloudflare DNS

Same shape as `amplify/`, against `rchacon/puffer-website` and the apex/`www`
instead.

```bash
cd terraform/amplify-website

cat > backend.hcl <<EOF
bucket  = "<state_bucket_name from bootstrap output>"
key     = "amplify-website/terraform.tfstate"
region  = "us-west-2"
encrypt = true
EOF

cat > terraform.tfvars <<EOF
state_bucket_name   = "<state_bucket_name from bootstrap output>"
github_access_token = "<classic PAT, scope admin:repo_hook only>"
EOF

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

**Pass 1 — app on the default URL** (`enable_custom_domain` defaults to `false`):

```bash
terraform apply
open "$(terraform output -raw default_domain)"
```

Confirm the build succeeds in the Amplify console and the site renders. Push a
trivial commit to `main` and confirm auto-build fires.

**Pass 2 — custom domain.** Add the domain settings to `terraform.tfvars`:

```hcl
enable_custom_domain = true
cloudflare_api_token = "<Zone:DNS:Edit token for the pufferpower.com zone>"
cloudflare_zone_id   = "<zone ID from the pufferpower.com Overview tab>"
# domain_name defaults to "pufferpower.com"
# subdomain_prefixes defaults to ["", "www"] -> pufferpower.com + www.pufferpower.com
```

```bash
terraform plan    # expect: 1 aws_amplify_domain_association + the cloudflare_record resources
terraform apply
```

This module only ever manages the apex + `www` — `amplify/`'s `app` record is
untouched. Apply `amplify/`'s custom domain first: ACM then reuses its
already-validated cert here, so `amplify-website/`'s `cloudflare_record.cert_verification`
is disabled (`count = 0`) — the validation record it would create already exists in
`amplify/`'s state. If a future apply shows this module needs a different validation
record, set `count = 1` and re-apply. Once the domain association shows **Available**
in the Amplify console:

```bash
dig +short pufferpower.com
dig +short www.pufferpower.com
curl -sI https://pufferpower.com | head -1
```

## `legacy-domain-redirect/` — pufferpanic.com → pufferpower.com redirects

The app's original domain, `pufferpanic.com`, was retired because "Puffer Panic" is
already the name of an unrelated iOS app. The zone stays in Cloudflare, but it now
only redirects: `pufferpanic.com`, `www.pufferpanic.com`, `app.pufferpanic.com` and
`api.pufferpanic.com` each send a `301` to the same host and path on `pufferpower.com`, with the query
string preserved. The module creates one proxied (orange-cloud) `AAAA 100::`
placeholder record per hostname, plus a Cloudflare Single Redirect ruleset. No
Amplify domain association or AppSync domain exists on `pufferpanic.com`.

Needs a Cloudflare API token with **Zone:DNS:Edit** *and* **Zone:Single Redirect:Edit**
on the `pufferpanic.com` zone (it can be the same token as the Amplify modules, if
that token has both permissions on both zones).

```bash
cd terraform/legacy-domain-redirect

cat > backend.hcl <<EOF
bucket  = "<state_bucket_name from bootstrap output>"
key     = "legacy-domain-redirect/terraform.tfstate"
region  = "us-west-2"
encrypt = true
EOF

cat > terraform.tfvars <<EOF
cloudflare_api_token = "<token: Zone:DNS:Edit + Zone:Single Redirect:Edit on pufferpanic.com>"
cloudflare_zone_id   = "<zone ID from the pufferpanic.com Overview tab>"
EOF

terraform init -backend-config=backend.hcl
terraform plan    # first apply: 4 cloudflare_record + 1 cloudflare_ruleset
terraform apply
```

```bash
curl -sI 'https://app.pufferpanic.com/foo?x=1' | grep -iE '^(HTTP|location)'
# HTTP/2 301
# location: https://app.pufferpower.com/foo?x=1
```

### Cutover order (one-time, pufferpanic.com → pufferpower.com)

The redirect records have the same names as the old Amplify records in
`pufferpanic.com`, so they can only be created once the Amplify modules have moved off
that zone. Expect downtime on the old domain: `app.pufferpanic.com` goes down at
step 1, and the apex and `www` go down at step 2. Neither comes back until step 3
adds the redirects. The Amplify modules don't wait for domain verification
(`wait_for_verification = false`), so the new `pufferpower.com` hosts may not serve
HTTPS until step 4 finishes. Until then, the step 3 redirects can land on hosts that
aren't ready yet. Run the steps back to back.

1. `amplify/`: in `terraform.tfvars`, point `cloudflare_zone_id` at the `pufferpower.com`
   zone, with a token that has DNS:Edit on **both** zones. The plan should replace the
   domain association and the Cloudflare records (destroyed in the old zone, created
   in the new zone). Apply.
2. `amplify-website/`: same change → plan → apply.
3. `legacy-domain-redirect/`: set it up as above → plan → apply.
4. Wait for both apps' custom domains to show **Available**. `amplify-website/` creates
   no cert-verification record of its own (`count = 0`; it relies on reusing
   `amplify/`'s), and nothing in Terraform checks that this still holds on the new
   domain. Confirm it yourself:

   ```bash
   for app in <amplify app_id> <amplify-website app_id>; do
     aws amplify get-domain-association --app-id "$app" --domain-name pufferpower.com \
       --query 'domainAssociation.[domainStatus,certificateVerificationDNSRecord]' --output text
   done
   ```

   If the website's verification record differs from the game's, or it is stuck in
   `PENDING_VERIFICATION`, set `amplify-website/`'s `cloudflare_record.cert_verification`
   to `count = 1` and re-apply.

## `puffer-api/` — backend: Cognito, DynamoDB, AppSync, Lambda shells

The backend for [`rchacon/puffer-api`](https://github.com/rchacon/puffer-api). Terraform
creates each piece once; puffer-api's three tag-triggered workflows only push new
*code* into it:

| puffer-api tag | Deploys | Via |
| --- | --- | --- |
| `postconfirmation-v*` | the Cognito Post Confirmation Lambda | `aws lambda update-function-code` |
| `progressprojector-v*` | the DynamoDB-stream progress projector Lambda | `aws lambda update-function-code` |
| `graphql-v*` | schema + resolvers + pipeline functions | a generated CloudFormation stack (`puffer-api-graphql`) |

This module creates:
- the `puffer-power-<env>` DynamoDB table (with `GSI1` and a `NEW_IMAGE` stream);
- the Cognito user pool (Essentials tier, email username) with `game` and `portal`
  app clients;
- the AppSync API and its DynamoDB data source (**never the schema**: the
  `graphql-v*` stack owns it);
- both Lambdas, with placeholder code, plus the stream event source mapping;
- one OIDC deploy role per tag prefix;
- puffer-api's GitHub Actions repository variables (prod only);
- (gated) the `api.pufferpower.com` custom domain.

Managed Login (`auth.pufferpower.com`), SES, Google/Apple sign-in, the `preSignUp`
and `deleteMyAccount` Lambdas, and the `VITE_*` wiring into `amplify/` follow in
later PRs (#4).

### Prerequisites

- **`puffer-terraform` IAM permissions.** The user's policy only covers the Amplify
  modules. Add [`puffer-api/terraform-user-policy.json`](puffer-api/terraform-user-policy.json)
  to it (IAM console → Users → `puffer-terraform` → Add permissions → Create inline
  policy → JSON) before the first plan.
- **The GitHub OIDC provider** (`token.actions.githubusercontent.com`) must already
  exist in the account. It does: `cd-infra`'s bootstrap created it, and there can only
  be one per account. This module references it by ARN; it never creates it.
- **A GitHub fine-grained token** for prod: repository access *only*
  `rchacon/puffer-api`, permission **Variables: Read and write**. Used to publish
  the deploy workflows' repository variables.
- For the custom domain (second pass): the Cloudflare token and the `pufferpower.com`
  zone ID, the same ones `amplify/` uses.

### Setup (prod)

```bash
cd terraform/puffer-api

cat > backend.hcl <<EOF
bucket  = "<state_bucket_name from bootstrap output>"
key     = "puffer-api/prod/terraform.tfstate"
region  = "us-west-2"
encrypt = true
EOF

cat > terraform.tfvars <<EOF
env          = "prod"
github_token = "<fine-grained token: Variables read/write on rchacon/puffer-api>"
EOF

terraform init -backend-config=backend.hcl
terraform plan    # pass 1: ~37 resources (29 AWS + 8 github_actions_variable)
terraform apply
```

A dev stack uses its own `backend.hcl` key (`puffer-api/dev/terraform.tfstate`) and
`env = "dev"`, with no `github_token`: dev doesn't publish repository variables, since
puffer-api's workflows deploy to whatever those name. Run it from a separate
checkout or re-`init -reconfigure` between envs.

**Pass 2 — custom domain.** Add to `terraform.tfvars`, then plan/apply again (expect
an ACM certificate + validation, the AppSync domain + association, and 2 Cloudflare
records):

```hcl
enable_custom_domain = true
cloudflare_api_token = "<Zone:DNS:Edit token for pufferpower.com>"
cloudflare_zone_id   = "<pufferpower.com zone ID>"
# api_subdomain defaults to "api" -> api.pufferpower.com (use e.g. "api-dev" for dev)
```

### After the first apply

1. **Deploy the real code** by tagging puffer-api: `graphql-v*` first (an API with no
   schema rejects every request), then `postconfirmation-v*` and `progressprojector-v*`.
   Until then the Lambdas run placeholders. Post Confirmation passes sign-ups through
   without writing a profile, and the projector acknowledges records without writing
   summaries.
2. **Rebuild progress summaries once** after the first real `progressprojector-v*`
   deploy, in case attempts were recorded while the placeholder ran:

   ```bash
   aws lambda invoke --function-name puffer-power-prod-progress-projector \
     --cli-binary-format raw-in-base64-out --payload '{"rebuild":{}}' /dev/stdout
   ```

3. Once the custom domain is live, apply `legacy-domain-redirect/` so
   `api.pufferpanic.com` redirects too.

## Validating without AWS credentials

`terraform fmt -check -recursive` and `terraform validate` (after
`terraform init -backend=false`) need no AWS credentials — the same checks CI runs:

```bash
terraform fmt -check -recursive terraform/
for dir in $(find terraform -name '*.tf' -printf '%h\n' | sort -u); do
  terraform -chdir="$dir" init -backend=false -input=false
  terraform -chdir="$dir" validate
done
```
