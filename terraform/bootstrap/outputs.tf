# This value is what every other terraform/ directory's gitignored
# backend.hcl (and terraform.tfvars, where a module needs the bucket name
# as a variable too) should reference -- Terraform backend blocks can't
# reference other resources/outputs, so this is documentation of the
# literal value to copy, not something consumed programmatically.
# bootstrap/ has no S3 backend at all (it's what creates the bucket), so
# this can't be read via terraform_remote_state either.

output "state_bucket_name" {
  description = "S3 bucket holding Terraform state for the rest of terraform/."
  value       = aws_s3_bucket.terraform_state.bucket
}
