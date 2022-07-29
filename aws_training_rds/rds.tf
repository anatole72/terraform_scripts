variable "vpc_region" {}
variable "tfstate_bucket" {}
variable "rds_username" {}
variable "rds_password" {}
variable "rds_size" {}

provider "aws" {
    region = "${var.vpc_region}"
}

data "terraform_remote_state" "vpc" {
	backend = "s3"
	config {
		region = "${var.vpc_region}"
		bucket = "${var.tfstate_bucket}"
		key = "aws_training/vpc/terraform.tfstate"
	}
}

resource "aws_db_subnet_group" "rds_subnets" {
    name = "main"
    subnet_ids = ["${split(",",data.terraform_remote_state.vpc.public_subnets)}"]
    tags {
        Name = "RDS Subnets"
    }
}

resource "aws_security_group" "rds" {
    name="rds_access"
    description="Allow access to MySQL RDS"
    vpc_id="${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
    egress {
        from_port=0
        to_port=0
        protocol="-1"
        cidr_blocks=["0.0.0.0/0"]
    }
    ingress {
        from_port=3306
        to_port=3306
        protocol="tcp"
        cidr_blocks=["0.0.0.0/0"]
    }
}


resource "aws_db_instance" "db1" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.6.27"
  instance_class       = "${var.rds_size}"
  name                 = "mydb"
  username             = "${var.rds_username}"
  password             = "${var.rds_password}"
  db_subnet_group_name = "${aws_db_subnet_group.rds_subnets.name}"
  parameter_group_name = "default.mysql5.6"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"]
}

output "aws_db_instance_db1_address" {
	value = "${aws_db_instance.db1.address}"
}

output "aws_db_instance_db1_name" {
	value = "${aws_db_instance.db1.name}"
}

output "aws_security_group_rds_id" {
	value = "${aws_security_group.rds.id}"
}