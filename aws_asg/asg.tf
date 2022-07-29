variable "vpc_region" {}
variable "tfstate_bucket" {}
variable "ami_id" {}
variable "aws_ssh_key_name" {}

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

data "terraform_remote_state" "sns" {
	backend = "s3"
	config {
		region = "${var.vpc_region}"
		bucket = "${var.tfstate_bucket}"
		key = "aws_training/sns/terraform.tfstate"
	}
}

data "terraform_remote_state" "bastion" {
	backend = "s3"
	config {
		region = "${var.vpc_region}"
		bucket = "${var.tfstate_bucket}"
		key = "aws_training/bastion/terraform.tfstate"
	}
}

data "terraform_remote_state" "rds" {
	backend = "s3"
	config {
		region = "${var.vpc_region}"
		bucket = "${var.tfstate_bucket}"
		key = "aws_training/rds/terraform.tfstate"
	}
}

resource "aws_security_group" "webserver-elb" {
	name="webserver_elb"
	description="traffic from the internet to the webservers"
	vpc_id="${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
	egress {
		from_port=0
		to_port=0
		protocol="-1"
		cidr_blocks=["0.0.0.0/0"]
	}
	ingress {
		from_port=80
		to_port=80
		protocol="tcp"
		cidr_blocks=["0.0.0.0/0"]
	}
}

resource "aws_elb" "webserver-elb" {
	name="webserver-elb"
	subnets=["${split(",",data.terraform_remote_state.vpc.public_subnets)}"]
	cross_zone_load_balancing = true
	idle_timeout = 60
	security_groups=["${aws_security_group.webserver-elb.id}"]
	listener {
		instance_port=80
		instance_protocol="http"
		lb_port=80
		lb_protocol="http"
	}
	health_check {
		healthy_threshold = 2
		unhealthy_threshold = 2
		timeout = 2
		target="HTTP:80/index.php"
		interval=10
	}
	tags {
		Name="webserver_elb"
		Owner="Anatole"
	}
	
}

resource "aws_security_group" "webservers-sg" {
	name="webserver_allow_from_internal"
	description="Allow traffic from the ELBs to the web servers"
	vpc_id="${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
	egress {
		from_port=0
		to_port=0
		protocol="-1"
		cidr_blocks=["0.0.0.0/0"]
	}
	ingress {
		from_port=80
		to_port=80
		protocol="tcp"
		security_groups=["${aws_security_group.webserver-elb.id}"]
	}
	ingress {
		from_port=22
		to_port=22
		protocol="tcp"
		security_groups=["${data.terraform_remote_state.bastion.aws_security_group_bastion_id}"]
	}
	ingress {
		from_port=80
		to_port=80
		protocol="tcp"
		security_groups=["${data.terraform_remote_state.bastion.aws_security_group_bastion_id}"]
	}
}

resource "aws_launch_configuration" "web-servers" {
	name_prefix="webserver_launch_config-"
	image_id="${var.ami_id}"
	instance_type="t2.micro"
	key_name="${var.aws_ssh_key_name}"
	security_groups=["${aws_security_group.webservers-sg.id}","${data.terraform_remote_state.rds.aws_security_group_rds_id}"]
	user_data=<<EOF
#!/bin/bash
yum clean all && yum makecache
yum install -y httpd php php-mysql
sed -i 's/Listen 80/Listen 0.0.0.0:80/' /etc/httpd/conf/httpd.conf
cat << 'END' > /var/www/html/index.php
<html>
<head>
<title>2 KaRS and 2 LV!</title>
</head>
<body>
<?php
$servername = "${data.terraform_remote_state.rds.aws_db_instance_db1_address}";
$username = "whosthat";
$password = "donttellanyonethis";
$dbname = "${data.terraform_remote_state.rds.aws_db_instance_db1_name}";

// Create connection
$conn = new mysqli($servername, $username, $password, $dbname);

// Check connection
if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}
//echo "<br />";
//echo "Connected successfully";

// Select 1 from table_name will return false if the table does not exist.
$val = 'SELECT 1 from SQL_BASE LIMIT 1';

if($conn->query($val) === FALSE)
{
    $sql_table = 'CREATE TABLE SQL_BASE (
    id INT NOT NULL AUTO_INCREMENT,
    colour VARCHAR(10) NOT NULL,
    image VARCHAR(125) NOT NULL,
    PRIMARY KEY( id ))';

if ($conn->query($sql_table) === TRUE) {
  $insert = "INSERT INTO SQL_BASE (colour, image) VALUES (
  \"purple\", \""),
  (\"orange\", \"\"),
  (\"yellow\", \"\")";

  if ($conn->query($insert) === FALSE) {
    echo "Failed to seed DB.";
  }

} else {
    echo "Error creating table: " . $conn->error;
}
}
$sql = 'SELECT * FROM FeelTheFun WHERE `id`='.rand(1,3).' LIMIT 1';
$result = $conn->query($sql);
//if ($result === TRUE) {
  if ($result->num_rows > 0 ) {
    while($row = $result->fetch_assoc()){
      echo "<h1 style=\"color:". $row["colour"] . "\";> !!</h1>";
      echo "<br/>";
      echo "<img src=\"" . $row["image"] . "\" atl=\"can\">";
      echo "<br />";
    }
  } else {
    echo "0 results.";
  }
//} else {
//  echo "Failed to get data";
//}

$conn->close();
?>
</body>
</html>
END
service httpd restart
chkconfig httpd on
EOF
	lifecycle {
		create_before_destroy = true
	}

}

resource "aws_autoscaling_group" "webservers" {
	min_size=1
	max_size=9
	desired_capacity=2
	health_check_grace_period=300
	launch_configuration="${aws_launch_configuration.web-servers.name}"
	vpc_zone_identifier=["${split(",",data.terraform_remote_state.vpc.private_subnets)}"]
	load_balancers=["${aws_elb.webserver-elb.id}"]
}

resource "aws_autoscaling_notification" "webservers" {
	group_names = ["${aws_autoscaling_group.webservers.name}"]
	notifications  = [
    	"autoscaling:EC2_INSTANCE_LAUNCH", 
    	"autoscaling:EC2_INSTANCE_TERMINATE",
    	"autoscaling:EC2_INSTANCE_LAUNCH_ERROR"
  	]
  	topic_arn = "${data.terraform_remote_state.sns.aws_sns_topic_autoscale_notifications_arn}"
}

output "aws_elb_webserver_elb_dns_name" {
	value = "${aws_elb.webserver-elb.dns_name}"
}