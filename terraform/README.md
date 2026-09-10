# terraform/

Each subdirectory is an independent Terraform root module. Apply `bootstrap/` once,
then `amplify/`.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.15
- AWS credentials for the target account (env vars, an AWS CLI profile, or SSO —
  anything the AWS provider's standard credential chain picks up)
- For `amplify/`:
  - The **AWS Amplify GitHub App** installed/authorized for `rchacon/puffer-panic`,
    **and** that repo added to the App's repository access list (GitHub → Settings →
    Applications → AWS Amplify → Configure). Both steps are required — a missing repo
    on the access list fails the first build with a misleading
    `Unable to assume specified IAM Role`.
  - A **GitHub personal access token** (classic), scope **`admin:repo_hook` only** —
    used once at `CreateApp` to register Amplify's webhook.
  - For the custom domain (second apply only): the domain hosted as a **zone in
    Cloudflare**, a **Cloudflare API token** scoped `Zone:DNS:Edit` on that zone
    (dashboard → My Profile → API Tokens → "Edit zone DNS" template), and the
    **Zone ID** (dashboard → the domain's Overview tab).

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

The `state_bucket_name` output is what `amplify/`'s `backend.hcl` and
`terraform.tfvars` need below — Terraform backend blocks can't reference outputs, and
`bootstrap/` has no S3 backend to read via `terraform_remote_state`, so the value is
copied by hand.

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
cloudflare_api_token = "<Zone:DNS:Edit token for the pufferpanic.com zone>"
cloudflare_zone_id   = "<zone ID from the pufferpanic.com Overview tab>"
# domain_name defaults to "pufferpanic.com"
# subdomain_prefixes defaults to ["app"] -> app.pufferpanic.com; override if you want something else
```

```bash
terraform plan    # expect: 1 aws_amplify_domain_association + the cloudflare_record resources
terraform apply
```

The new Cloudflare records are additive (grey-cloud, `proxied = false`) and don't
touch any existing zone records. This module only ever manages the `app` subdomain —
the apex (`pufferpanic.com`) and `www` are reserved for a separate Puffer Panic
marketing site. Domain verification is asynchronous — watch the
Amplify console's **Custom domains** tab (or re-run `terraform plan`); don't trust
`apply`'s exit code for the domain association. Once it shows **Available**:

```bash
dig +short app.pufferpanic.com
curl -sI https://app.pufferpanic.com | head -1
```

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
