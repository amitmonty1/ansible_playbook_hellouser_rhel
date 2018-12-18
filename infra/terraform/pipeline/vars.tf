variable "project_name" {
  default = "hellouser-ami-builder"
}

variable "vcs_provider" {
  default = "GitHub"
}

variable "artifact_name" {
  default = "2w-ami"
}

variable "owner" {
  default = "schittam"
}

variable "repo" {
  default = "ansible_playbook_hellouser"
}

variable "branch" {
  default = "master"
}

variable "bucket_name" {
  default = "schittamuru-terraform-state"
}

variable "region" {
  default = "us-east-1"
}

variable "oauth_token" {}
