# Puffer Infra

AWS infrastructure as code for [Puffer Panic](https://github.com/rchacon/puffer-panic),
a small React reading game for kids, and its marketing site.

Both apps are hosted on **AWS Amplify Hosting**, each built and auto-deployed from its
own repo's `main` branch, and split across one domain (`pufferpanic.com`, registered
and DNS-hosted in **Cloudflare**):

- The game (`rchacon/puffer-panic`) at **app.pufferpanic.com**.
- The marketing site (`rchacon/puffer-website`) at **pufferpanic.com** (apex) and
  **www.pufferpanic.com**.

See [`terraform/README.md`](terraform/README.md) for per-directory setup and usage.

## Layout

| Directory | What it does |
| --- | --- |
| `terraform/bootstrap/` | One-time: the S3 bucket that stores every other directory's Terraform state. Run once, with local state. |
| `terraform/amplify/` | The game's Amplify app + branch, and (gated) its custom domain + Cloudflare DNS records. |
| `terraform/amplify-website/` | The marketing site's Amplify app + branch, and (gated) its custom domain + Cloudflare DNS records. |
