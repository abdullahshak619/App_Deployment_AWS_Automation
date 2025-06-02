provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "example" {
  bucket = "my-aut-bucket-name-123456"  # Make sure it's globally unique!
  force_destroy = true  # Optional: allows deletion even if not empty
}
