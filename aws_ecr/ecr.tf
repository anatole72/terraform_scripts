variable "aws_region" {}

provider "aws" {
    region = "${var.aws_region}"
}

resource "aws_ecr_repository" "ruby_app" {
  name = "ruby_app"
}

output "aws_ecr_repository_ruby_app_url" {
	value = "${aws_ecr_repository.ruby_app.repository_url}"
}
