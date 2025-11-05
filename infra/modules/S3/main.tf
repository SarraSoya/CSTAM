resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "this" {
  bucket        = "${var.environment}-ingestion-data-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${var.environment}-ingestion-data" }
}

# (Optional) keep private by default (AWS default is private; policy is not required)
# You can add lifecycle rules, versioning, or SSE if you want.

# Simple public access block (defense-in-depth)
resource "aws_s3_bucket_public_access_block" "block" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
