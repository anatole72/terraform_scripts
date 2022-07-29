variable "vpc_region" {}
variable "tfstate_bucket" {}

provider "aws" {
    region = "${var.vpc_region}"
}

resource "aws_sns_topic" "autoscale_notifications" {
	name = "autoscale_notifications"
	display_name = "autoscale_notifications"
}

resource "aws_sqs_queue" "autoscale_watcher" {
	name = "autoscale_watcher"
	visibility_timeout_seconds = 120
}

resource "aws_sqs_queue_policy" "autoscale_watcher_policy" {
    queue_url = "${aws_sqs_queue.autoscale_watcher.id}"
    policy = <<POLICY
    {
    "Version": "2012-10-17",
    "Id": "${aws_sqs_queue.autoscale_watcher.arn}/SQSPolicy",
    "Statement": [
        {
            "Sid": "123456789",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": "SQS:SendMessage",
            "Resource": "${aws_sqs_queue.autoscale_watcher.arn}",
            "Condition": {
                "ArnEquals": {
                    "aws:SourceArn": "${aws_sns_topic.autoscale_notifications.arn}"
                }
            }
        }
    ]
}
POLICY
}

output "autoscale_watcher_queue_arn" {
	value = "${aws_sqs_queue.autoscale_watcher.arn}"
}

resource "aws_sns_topic_subscription" "autoscale_notifications_sqs" {
	topic_arn = "${aws_sns_topic.autoscale_notifications.arn}"
	protocol = "sqs"
	endpoint = "${aws_sqs_queue.autoscale_watcher.arn}"
	
}

output "aws_sns_topic_autoscale_notifications_arn" {
	value = "${aws_sns_topic.autoscale_notifications.arn}"
}

output "aws_sqs_queue_autoscale_watcher_arn" {
	value = "${aws_sqs_queue.autoscale_watcher.arn}"
}