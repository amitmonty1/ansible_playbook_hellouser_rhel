data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "vpc" {
  vpc_id = "${data.aws_vpc.default.id}"
}

data "aws_subnet" "list" {
  count = "${length(data.aws_subnet_ids.vpc.ids)}"
  id    = "${data.aws_subnet_ids.vpc.ids[count.index]}"
}

provider "aws" {
  region = "${var.region}"
}

resource "aws_security_group" "elb" {
  vpc_id = "${data.aws_vpc.default.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "app" {
  internal        = false
  security_groups = ["${aws_security_group.elb.id}"]
  subnets         = ["${data.aws_subnet_ids.vpc.ids}"]

  enable_deletion_protection = false

  tags {
    Project = "Image Factory Demo"
  }
}

resource "aws_lb_target_group" "frontend" {
  port     = 8080
  protocol = "HTTP"
  vpc_id   = "${ data.aws_vpc.default.id }"

  health_check {
    protocol          = "HTTP"
    port              = "8080"
    interval          = "${var.HealthCheckInterval}"
    timeout           = 5
    healthy_threshold = 2
    matcher           = "200"
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = "${aws_lb.app.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_lb_target_group.frontend.arn}"
    type             = "forward"
  }
}

resource "aws_autoscaling_group" "app" {
  lifecycle {
    create_before_destroy = true
  }

  name                      = "Hello User Service - ${aws_launch_configuration.app.name}"
  vpc_zone_identifier       = ["${data.aws_subnet_ids.vpc.ids}"]
  max_size                  = "${length(data.aws_subnet_ids.vpc.ids)}"
  min_size                  = "${length(data.aws_subnet_ids.vpc.ids)}"
  desired_capacity          = "${length(data.aws_subnet_ids.vpc.ids)}"
  health_check_grace_period = 300
  health_check_type         = "ELB"
  target_group_arns         = ["${aws_lb_target_group.frontend.arn}"]
  launch_configuration      = "${aws_launch_configuration.app.name}"

  tag {
    key                 = "Name"
    value               = "HelloUser - RHEL7.5"
    propagate_at_launch = true
  }
}

data "aws_caller_identity" "default" {}

data "aws_ami" "app" {
  owners      = ["${data.aws_caller_identity.default.account_id}"]
  most_recent = true

  name_regex = "^hellouser.*"
}

resource "aws_launch_configuration" "app" {
  lifecycle {
    create_before_destroy = true
  }

  image_id      = "${data.aws_ami.app.id}"
  instance_type = "t2.small"

  # Our Security group to allow HTTP and SSH access
  security_groups = ["${aws_security_group.instances.id}"]
}

resource "aws_security_group" "instances" {
  vpc_id = "${data.aws_vpc.default.id}"

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//Outputs
// Output LoadBalancer Cname/DnsName

