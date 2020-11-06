provider "aws" {
  region = "ap-northeast-1"
}

terraform {
  # https://github.com/hashicorp/terraform/releases
  required_version = "0.13.4"

  required_providers {
    # https://github.com/terraform-providers/terraform-provider-aws/releases
    aws = "3.14.0"
    # https://github.com/hashicorp/terraform-provider-archive/releases
    archive = "2.0.0"
  }
}
