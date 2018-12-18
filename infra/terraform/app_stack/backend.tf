# Add configuration for Backend Here.

terraform {
  backend "s3" {
    bucket = "schittamuru-terraform-state"
    key    = "app-stack-terraform.tfstate"
    region = "us-east-1"
  }
}


