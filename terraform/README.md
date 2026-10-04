# terraform/

Each subdirectory is an independent Terraform root module. Apply `bootstrap/` once,
then `amplify/` before `amplify-website/` (see the cert-reuse note under
`amplify-website/`), then `legacy-domain-redirect/`.

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

## `amplify-classroom/` — classroom edition (class.pufferpower.com)

A second Amplify app for `rchacon/puffer-app`: the same repo, branch and repo-root
`amplify.yml` as `amplify/`, so both rebuild on every push to `main`. It's the free
**school-pilot build**: guest play only, storing nothing outside the browser.

What makes it different is its build environment, not its code. It sets
`VITE_EDITION=classroom` and **must never** be given the account/backend variables
(`VITE_COGNITO_*`, `VITE_GRAPHQL_*`) that the home edition (`amplify/`) gets once the
backend exists (#4). Without them, the game compiles with no account UI and makes no
backend calls. A precondition on `aws_amplify_app.puffer_classroom` fails the plan if
one is ever added here.

No new GitHub App step: `rchacon/puffer-app` is already on the AWS Amplify GitHub App's
access list from `amplify/`. A `github_access_token` (classic PAT, `admin:repo_hook`)
is still needed for `CreateApp`'s webhook registration.

```bash
cd terraform/amplify-classroom

cat > backend.hcl <<EOF
bucket  = "<state_bucket_name from bootstrap output>"
key     = "amplify-classroom/terraform.tfstate"
region  = "us-west-2"
encrypt = true
EOF

cat > terraform.tfvars <<EOF
state_bucket_name   = "<state_bucket_name from bootstrap output>"
github_access_token = "<classic PAT, scope admin:repo_hook only>"
EOF

terraform init -backend-config=backend.hcl
terraform plan
```

**Pass 1: app on the default URL** (`enable_custom_domain` defaults to `false`):

```bash
terraform apply
open "$(terraform output -raw default_domain)"
```

Confirm the build succeeds and the game plays. **Pass 2: custom domain.** Add the same
`enable_custom_domain`, `cloudflare_api_token` and `cloudflare_zone_id` settings as the
other Amplify modules to `terraform.tfvars`. `subdomain_prefixes` defaults to
`["class"]`, and a validation rejects `""`, `www` and `app`.

```bash
terraform plan    # expect: 1 aws_amplify_domain_association + 1 cloudflare_record (class)
terraform apply
dig +short class.pufferpower.com
curl -s https://class.pufferpower.com/version.json
```

`cloudflare_record.cert_verification` is `count = 0`, as in `amplify-website/`: ACM
reuses `amplify/`'s already-validated certificate for the domain. When puffer moves to
its own AWS accounts (#11), this app moves with the other two. In an account where
nothing has validated the domain yet, the first module to attach it needs `count = 1`.

## `legacy-domain-redirect/` — pufferpanic.com → pufferpower.com redirects

The app's original domain, `pufferpanic.com`, was retired because "Puffer Panic" is
already the name of an unrelated iOS app. The zone stays in Cloudflare, but it now
only redirects: `pufferpanic.com`, `www.pufferpanic.com` and `app.pufferpanic.com`
each send a `301` to the same host and path on `pufferpower.com`, with the query
string preserved. The module creates one proxied (orange-cloud) `AAAA 100::`
placeholder record per hostname, plus a Cloudflare Single Redirect ruleset. No
Amplify domain association exists on `pufferpanic.com`. `api` is added to
`redirect_prefixes` once the API (#4) ships on `api.pufferpower.com`.

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
terraform plan    # expect: 3 cloudflare_record + 1 cloudflare_ruleset
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
