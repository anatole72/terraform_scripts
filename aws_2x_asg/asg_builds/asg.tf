variable "vpc_region" {}
variable "tfstate_bucket" {}
variable "ami_id1" {}
variable "ami_id2" {}
variable "aws_ssh_key_name" {}

# Variables for AutoScaling Group 1
variable "asg1_lb" {
	default=0
}
variable "asg1_min_size"{
	default=1
}
variable "asg1_max_size"{
	default=3
}
variable "asg1_desired_capacity"{
	default=2
}

# Variables for AutoScaling Group 2
variable "asg2_lb" {
	default=1
}
variable "asg2_min_size"{
	default=1
}
variable "asg2_max_size"{
	default=3
}
variable "asg2_desired_capacity"{
	default=2
}

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
}

resource "aws_launch_configuration" "lc1" {
	name_prefix="webserver_launch_config-"
	image_id="${var.ami_id1}"
	instance_type="t2.micro"
	key_name="${var.aws_ssh_key_name}"
	security_groups=["${aws_security_group.webservers-sg.id}"]
	user_data=<<EOF
#!/bin/bash
yum clean all && yum makecache
yum install -y httpd
sed -i 's/Listen 80/Listen 0.0.0.0:80/' /etc/httpd/conf/httpd.conf
cat << 'END' > /var/www/html/index.html
<html>
<head>
<title>ASG 1</title>
</head>
<body>
<h1>ASG 1</h1>
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

resource "aws_launch_configuration" "lc2" {
	name_prefix="webserver_launch_config-"
	image_id="${var.ami_id2}"
	instance_type="t2.micro"
	key_name="${var.aws_ssh_key_name}"
	security_groups=["${aws_security_group.webservers-sg.id}"]
	user_data=<<EOF
#!/bin/bash
yum clean all && yum makecache
yum install -y httpd
sed -i 's/Listen 80/Listen 0.0.0.0:80/' /etc/httpd/conf/httpd.conf
cat << 'END' > /var/www/html/index.html
<html>
<head>
<title>ASG 2</title>
</head>
<body>
<h1>ASG 2</h1>
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

resource "aws_elb" "webserver-elb1" {
	name="webserver-elb1"
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
		target="HTTP:80/index.html"
		interval=10
	}
	tags {
		Name="webserver_elb"
		Owner="Randy"
	}
}

resource "aws_elb" "webserver-elb2" {
	name="webserver-elb2"
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
		target="HTTP:80/index.html"
		interval=10
	}
	tags {
		Name="webserver_elb"
		Owner="Randy"
	}
}

resource "aws_autoscaling_group" "web1" {
	min_size="${var.asg1_min_size}"
	max_size="${var.asg1_max_size}"
	desired_capacity="${var.asg1_desired_capacity}"
	health_check_grace_period=300
	launch_configuration="${aws_launch_configuration.lc1.id}"
	vpc_zone_identifier=["${split(",",data.terraform_remote_state.vpc.private_subnets)}"]
	load_balancers=["${element(split(",", format("%s,%s",aws_elb.webserver-elb1.id,aws_elb.webserver-elb2.id)), var.asg1_lb)}"]
}

resource "aws_autoscaling_group" "web2" {
	min_size="${var.asg2_min_size}"
	max_size="${var.asg2_max_size}"
	desired_capacity="${var.asg2_desired_capacity}"
	health_check_grace_period=300
	launch_configuration="${aws_launch_configuration.lc2.id}"
	vpc_zone_identifier=["${split(",",data.terraform_remote_state.vpc.private_subnets)}"]
	load_balancers=["${element(split(",", format("%s,%s",aws_elb.webserver-elb1.id,aws_elb.webserver-elb2.id)), var.asg2_lb)}"]
}

##################
## AutoScaling policies.
##################
resource "aws_autoscaling_policy" "scaleup-1" {
  name = "scaleup-1"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 60
  autoscaling_group_name = "${aws_autoscaling_group.web1.name}"
}
resource "aws_autoscaling_policy" "scaleup-2" {
  name = "scaleup-2"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 60
  autoscaling_group_name = "${aws_autoscaling_group.web2.name}"
}
resource "aws_autoscaling_policy" "scaledown-1" {
  name = "scaledown-1"
  scaling_adjustment = "-1"
  adjustment_type = "ChangeInCapacity"
  cooldown = 60
  autoscaling_group_name = "${aws_autoscaling_group.web1.name}"
}
resource "aws_autoscaling_policy" "scaledown-2" {
  name = "scaledown-2"
  scaling_adjustment = "-1"
  adjustment_type = "ChangeInCapacity"
  cooldown = 60
  autoscaling_group_name = "${aws_autoscaling_group.web2.name}"
}
##################
## Scale up alarms.
##################
resource "aws_cloudwatch_metric_alarm" "1-high-cpu" {
    alarm_name = "WEB1-CPU-HIGH-Alarm"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "300"
    statistic = "Average"
    threshold = "80"
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.web1.name}"
    }
    alarm_description = "Scale up if CPU > 80%"
    alarm_actions = ["${aws_autoscaling_policy.scaleup-1.arn}"]
}

resource "aws_cloudwatch_metric_alarm" "2-high-cpu" {
    alarm_name = "WEB2-CPU-HIGH-Alarm"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "300"
    statistic = "Average"
    threshold = "80"
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.web2.name}"
    }
    alarm_description = "Scale up if CPU > 80%"
    alarm_actions = ["${aws_autoscaling_policy.scaleup-2.arn}"]
}

##################
## Scale down alarms.
##################
resource "aws_cloudwatch_metric_alarm" "1-down-cpu" {
    alarm_name = "WEB1-CPU-LOW-Alarm"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "300"
    statistic = "Average"
    threshold = "30"
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.web1.name}"
    }
    alarm_description = "Scale down if CPU < 30%"
    alarm_actions = ["${aws_autoscaling_policy.scaleup-2.arn}"]
}
resource "aws_cloudwatch_metric_alarm" "2-down-cpu" {
    alarm_name = "WEB2-CPU-LOW-Alarm"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "300"
    statistic = "Average"
    threshold = "30"
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.web2.name}"
    }
    alarm_description = "Scale down if CPU < 30%"
    alarm_actions = ["${aws_autoscaling_policy.scaleup-2.arn}"]
}


resource "aws_autoscaling_notification" "webservers" {
	group_names = ["${aws_autoscaling_group.web1.name}"]
	notifications  = [
    	"autoscaling:EC2_INSTANCE_LAUNCH",
    	"autoscaling:EC2_INSTANCE_TERMINATE",
    	"autoscaling:EC2_INSTANCE_LAUNCH_ERROR"
  	]
  	topic_arn = "${data.terraform_remote_state.sns.aws_sns_topic_autoscale_notifications_arn}"
}

##################
## Outputs
##################
output "aws_elb_webserver_elb1_dns_name" {
	value = "${aws_elb.webserver-elb1.dns_name}"
}

output "aws_elb_webserver_elb2_dns_name" {
	value = "${aws_elb.webserver-elb2.dns_name}"
}
