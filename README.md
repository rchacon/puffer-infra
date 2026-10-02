# Puffer Infra

AWS infrastructure as code for [Puffer Panic](https://github.com/rchacon/puffer-app),
a small React reading game for kids, and its marketing site.

Both apps are hosted on **AWS Amplify Hosting**, each built and auto-deployed from its
own repo's `main` branch, and split across one domain (`pufferpower.com`, registered
and DNS-hosted in **Cloudflare**):

- The game (`rchacon/puffer-app`) at **app.pufferpower.com**.
- The marketing site (`rchacon/puffer-website`) at **pufferpower.com** (apex) and
  **www.pufferpower.com**.

The original domain, `pufferpanic.com`, was retired because "Puffer Panic" is
already the name of an unrelated iOS app. Its hostnames now 301-redirect to the matching
`pufferpower.com` host, keeping the path and query string.

See [`terraform/README.md`](terraform/README.md) for per-directory setup and usage.

## Layout

| Directory | What it does |
| --- | --- |
| `terraform/bootstrap/` | One-time: the S3 bucket that stores every other directory's Terraform state. Run once, with local state. |
| `terraform/amplify/` | The game's Amplify app + branch, and (gated) its custom domain + Cloudflare DNS records. |
| `terraform/amplify-website/` | The marketing site's Amplify app + branch, and (gated) its custom domain + Cloudflare DNS records. |
| `terraform/legacy-domain-redirect/` | Cloudflare redirect rules (and proxied placeholder records) that send the retired `pufferpanic.com` hostnames to `pufferpower.com`. |
