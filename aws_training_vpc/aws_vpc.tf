variable "vpc_cidr" {}
variable "vpc_region" {}
variable "vpc_az" {}
#We need this in other scripts to make ARNs
# variable "aws_account_number" {}

provider "aws" {
    region = "${var.vpc_region}"
}

resource "aws_vpc" "vpc1" {
    cidr_block = "${var.vpc_cidr}"
    enable_dns_hostnames = true
    tags {
        Owner = "Randy"
        Name = "Randy AWS Training"
    }
}

resource "aws_subnet" "private" {
    count = 3
    vpc_id = "${aws_vpc.vpc1.id}"
    availability_zone = "${var.vpc_region}${element(split(",",var.vpc_az),count.index)}"
    cidr_block = "${cidrsubnet(var.vpc_cidr,8,count.index + 1)}"
    tags {
        Name = "Private Subnet ${count.index}"
    }
}

resource "aws_subnet" "public" {
    count = 3
    availability_zone = "${var.vpc_region}${element(split(",",var.vpc_az),count.index)}"
    vpc_id = "${aws_vpc.vpc1.id}"
    cidr_block = "${cidrsubnet(var.vpc_cidr,8,count.index + 51)}"
    tags {
        Name = "Public Subnet ${count.index}"
    }
}

resource "aws_internet_gateway" "gw" {
    vpc_id = "${aws_vpc.vpc1.id}"
    tags {
        Owner = "Randy"
    }
}

resource "aws_eip" "nat_servers" {
    count = 3
    vpc = true
}

resource "aws_nat_gateway" "nat" {
    count = 3
    allocation_id = "${element(aws_eip.nat_servers.*.id, count.index)}"
    subnet_id = "${element(aws_subnet.public.*.id, count.index)}"
    depends_on = ["aws_internet_gateway.gw"]
}

resource "aws_route_table" "private_routes" {
    count = 3
    vpc_id = "${aws_vpc.vpc1.id}"
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = "${element(aws_nat_gateway.nat.*.id, count.index)}"
    }
    tags {
        Name = "Private subnet ${count.index + 1}"
    }
}

resource "aws_route_table" "public_routes" {
    vpc_id = "${aws_vpc.vpc1.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.gw.id}"
    }
    tags {
        Name = "Private subnets"
    }
}

resource "aws_route_table_association" "public" {
    count = 3
    subnet_id = "${element(aws_subnet.public.*.id,count.index)}"
    route_table_id ="${element(aws_route_table.public_routes.*.id,count.index)}"
}

resource "aws_route_table_association" "private" {
    count = 3
    subnet_id = "${element(aws_subnet.private.*.id,count.index)}"
    route_table_id ="${element(aws_route_table.private_routes.*.id,count.index)}"
}

output "aws_vpc_vpc1_id" {
    value = "${aws_vpc.vpc1.id}"
}

output "public_subnets" {
    value="${join(",",aws_subnet.public.*.id)}"
}

output "private_subnets" {
    value="${join(",",aws_subnet.private.*.id)}"
}

#output "aws_account_number" {
#    value="${var.aws_account_number}"
#}
