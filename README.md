# Puffer Infra

AWS infrastructure as code for [Puffer Panic](https://github.com/rchacon/puffer-panic),
a small React reading game for kids.

The React app is hosted on **AWS Amplify Hosting**, built and auto-deployed from the
`main` branch of `rchacon/puffer-panic`, and served at **pufferpanic.com** (registered
and DNS-hosted in **Cloudflare**).

See [`terraform/README.md`](terraform/README.md) for per-directory setup and usage.

## Layout

| Directory | What it does |
| --- | --- |
| `terraform/bootstrap/` | One-time: the S3 bucket that stores every other directory's Terraform state. Run once, with local state. |
| `terraform/amplify/` | The Amplify app + branch, and (gated) its custom domain + Cloudflare DNS records. |
