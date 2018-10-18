variable "nat_ami_map" {
  type = "map"

  default = {
    ap-northeast-1 = "ami-10dfc877"
    ap-northeast-2 = "ami-1a1bc474"
    ap-south-1     = "ami-74c1861b"
    ap-southeast-1 = "ami-36af2055"
    ap-southeast-2 = "ami-1e91817d"
    ca-central-1   = "ami-12d36a76"
    eu-central-1   = "ami-9ebe18f1"
    eu-west-1      = "ami-3a849f5c"
    eu-west-2      = "ami-21120445"
    us-east-1      = "ami-d4c5efc2"
    us-east-2      = "ami-f27b5a97"
    us-gov-west-1  = "ami-c39610a2"
    us-west-1      = "ami-b87f53d8"
    us-west-2      = "ami-8bfce8f2"
  }
}

variable "access_key" {
  type = "string"
}

variable "secret_key" {
  type = "string"
}

variable "region" {
  type = "string"
}

variable "bosh_inbound_cidr" {
  default = "0.0.0.0/0"
}

variable "availability_zones" {
  type = "list"
}

variable "env_id" {
  type = "string"
}

variable "short_env_id" {
  type = "string"
}

variable "vpc_cidr" {
  type    = "string"
  default = "10.0.0.0/16"
}

resource "aws_eip" "jumpbox_eip" {
  depends_on = ["aws_internet_gateway.ig"]
  vpc        = true
}

resource "tls_private_key" "bosh_vms" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bosh_vms" {
  key_name   = "${var.env_id}_bosh_vms"
  public_key = "${tls_private_key.bosh_vms.public_key_openssh}"
}

resource "aws_security_group" "nat_security_group" {
  name        = "${var.env_id}-nat-security-group"
  description = "NAT"
  vpc_id      = "${local.vpc_id}"

  tags {
    Name = "${var.env_id}-nat-security-group"
  }

  lifecycle {
    ignore_changes = ["name"]
  }
}

resource "aws_security_group_rule" "nat_to_internet_rule" {
  security_group_id = "${aws_security_group.nat_security_group.id}"

  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "nat_icmp_rule" {
  security_group_id = "${aws_security_group.nat_security_group.id}"

  type        = "ingress"
  protocol    = "icmp"
  from_port   = -1
  to_port     = -1
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "nat_tcp_rule" {
  security_group_id = "${aws_security_group.nat_security_group.id}"

  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 0
  to_port                  = 65535
  source_security_group_id = "${aws_security_group.internal_security_group.id}"
}

resource "aws_security_group_rule" "nat_udp_rule" {
  security_group_id = "${aws_security_group.nat_security_group.id}"

  type                     = "ingress"
  protocol                 = "udp"
  from_port                = 0
  to_port                  = 65535
  source_security_group_id = "${aws_security_group.internal_security_group.id}"
}

resource "aws_instance" "nat" {
  private_ip             = "${cidrhost(aws_subnet.bosh_subnet.cidr_block, 7)}"
  instance_type          = "t2.medium"
  subnet_id              = "${aws_subnet.bosh_subnet.id}"
  source_dest_check      = false
  ami                    = "${lookup(var.nat_ami_map, var.region)}"
  vpc_security_group_ids = ["${aws_security_group.nat_security_group.id}"]

  tags {
    Name  = "${var.env_id}-nat"
    EnvID = "${var.env_id}"
  }
}

resource "aws_eip" "nat_eip" {
  depends_on = ["aws_internet_gateway.ig"]
  instance   = "${aws_instance.nat.id}"
  vpc        = true
}

provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"

  version = ">= 1.17.0"
}

resource "aws_default_security_group" "default_security_group" {
  vpc_id = "${local.vpc_id}"
}

resource "aws_security_group" "internal_security_group" {
  name        = "${var.env_id}-internal-security-group"
  description = "Internal"
  vpc_id      = "${local.vpc_id}"

  tags {
    Name = "${var.env_id}-internal-security-group"
  }

  lifecycle {
    ignore_changes = ["name"]
  }
}

resource "aws_security_group_rule" "internal_security_group_rule_tcp" {
  security_group_id = "${aws_security_group.internal_security_group.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 0
  to_port           = 65535
  self              = true
}

resource "aws_security_group_rule" "internal_security_group_rule_udp" {
  security_group_id = "${aws_security_group.internal_security_group.id}"
  type              = "ingress"
  protocol          = "udp"
  from_port         = 0
  to_port           = 65535
  self              = true
}

resource "aws_security_group_rule" "internal_security_group_rule_icmp" {
  security_group_id = "${aws_security_group.internal_security_group.id}"
  type              = "ingress"
  protocol          = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "internal_security_group_rule_allow_internet" {
  security_group_id = "${aws_security_group.internal_security_group.id}"
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "internal_security_group_rule_ssh" {
  security_group_id        = "${aws_security_group.internal_security_group.id}"
  type                     = "ingress"
  protocol                 = "TCP"
  from_port                = 22
  to_port                  = 22
  source_security_group_id = "${aws_security_group.jumpbox.id}"
}

resource "aws_security_group" "bosh_security_group" {
  name        = "${var.env_id}-bosh-security-group"
  description = "BOSH Director"
  vpc_id      = "${local.vpc_id}"

  tags {
    Name = "${var.env_id}-bosh-security-group"
  }

  lifecycle {
    ignore_changes = ["name", "description"]
  }
}

resource "aws_security_group_rule" "bosh_security_group_rule_tcp_ssh" {
  security_group_id = "${aws_security_group.bosh_security_group.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = ["${var.bosh_inbound_cidr}"]
}

resource "aws_security_group_rule" "bosh_security_group_rule_tcp_bosh_agent" {
  security_group_id        = "${aws_security_group.bosh_security_group.id}"
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 6868
  to_port                  = 6868
  source_security_group_id = "${aws_security_group.jumpbox.id}"
}

resource "aws_security_group_rule" "bosh_security_group_rule_uaa" {
  security_group_id        = "${aws_security_group.bosh_security_group.id}"
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 8443
  to_port                  = 8443
  source_security_group_id = "${aws_security_group.jumpbox.id}"
}

resource "aws_security_group_rule" "bosh_security_group_rule_credhub" {
  security_group_id        = "${aws_security_group.bosh_security_group.id}"
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 8844
  to_port                  = 8844
  source_security_group_id = "${aws_security_group.jumpbox.id}"
}

resource "aws_security_group_rule" "bosh_security_group_rule_tcp_director_api" {
  security_group_id        = "${aws_security_group.bosh_security_group.id}"
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 25555
  to_port                  = 25555
  source_security_group_id = "${aws_security_group.jumpbox.id}"
}

resource "aws_security_group_rule" "bosh_security_group_rule_tcp" {
  security_group_id        = "${aws_security_group.bosh_security_group.id}"
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 0
  to_port                  = 65535
  source_security_group_id = "${aws_security_group.internal_security_group.id}"
}

resource "aws_security_group_rule" "bosh_security_group_rule_udp" {
  security_group_id        = "${aws_security_group.bosh_security_group.id}"
  type                     = "ingress"
  protocol                 = "udp"
  from_port                = 0
  to_port                  = 65535
  source_security_group_id = "${aws_security_group.internal_security_group.id}"
}

resource "aws_security_group_rule" "bosh_security_group_rule_allow_internet" {
  security_group_id = "${aws_security_group.bosh_security_group.id}"
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "jumpbox" {
  name        = "${var.env_id}-jumpbox-security-group"
  description = "Jumpbox"
  vpc_id      = "${local.vpc_id}"

  tags {
    Name = "${var.env_id}-jumpbox-security-group"
  }

  lifecycle {
    ignore_changes = ["name", "description"]
  }
}

resource "aws_security_group_rule" "jumpbox_ssh" {
  security_group_id = "${aws_security_group.jumpbox.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = ["${var.bosh_inbound_cidr}"]
}

resource "aws_security_group_rule" "jumpbox_rdp" {
  security_group_id = "${aws_security_group.jumpbox.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 3389
  to_port           = 3389
  cidr_blocks       = ["${var.bosh_inbound_cidr}"]
}

resource "aws_security_group_rule" "jumpbox_agent" {
  security_group_id = "${aws_security_group.jumpbox.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 6868
  to_port           = 6868
  cidr_blocks       = ["${var.bosh_inbound_cidr}"]
}

resource "aws_security_group_rule" "jumpbox_director" {
  security_group_id = "${aws_security_group.jumpbox.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 25555
  to_port           = 25555
  cidr_blocks       = ["${var.bosh_inbound_cidr}"]
}

resource "aws_security_group_rule" "jumpbox_egress" {
  security_group_id = "${aws_security_group.jumpbox.id}"
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "bosh_internal_security_rule_tcp" {
  security_group_id        = "${aws_security_group.internal_security_group.id}"
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 0
  to_port                  = 65535
  source_security_group_id = "${aws_security_group.bosh_security_group.id}"
}

resource "aws_security_group_rule" "bosh_internal_security_rule_udp" {
  security_group_id        = "${aws_security_group.internal_security_group.id}"
  type                     = "ingress"
  protocol                 = "udp"
  from_port                = 0
  to_port                  = 65535
  source_security_group_id = "${aws_security_group.bosh_security_group.id}"
}

resource "aws_subnet" "bosh_subnet" {
  vpc_id     = "${local.vpc_id}"
  cidr_block = "${cidrsubnet(var.vpc_cidr, 8, 0)}"

  tags {
    Name = "${var.env_id}-bosh-subnet"
  }
}

resource "aws_route_table" "bosh_route_table" {
  vpc_id = "${local.vpc_id}"
}

resource "aws_route" "bosh_route_table" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.ig.id}"
  route_table_id         = "${aws_route_table.bosh_route_table.id}"
}

resource "aws_route_table_association" "route_bosh_subnets" {
  subnet_id      = "${aws_subnet.bosh_subnet.id}"
  route_table_id = "${aws_route_table.bosh_route_table.id}"
}

resource "aws_subnet" "internal_subnets" {
  count             = "${length(var.availability_zones)}"
  vpc_id            = "${local.vpc_id}"
  cidr_block        = "${cidrsubnet(var.vpc_cidr, 4, count.index+1)}"
  availability_zone = "${element(var.availability_zones, count.index)}"

  tags {
    Name = "${var.env_id}-internal-subnet${count.index}"
  }

  lifecycle {
    ignore_changes = ["cidr_block", "availability_zone"]
  }
}

resource "aws_route_table" "internal_route_table" {
  vpc_id = "${local.vpc_id}"
}

resource "aws_route" "internal_route_table" {
  destination_cidr_block = "0.0.0.0/0"
  instance_id            = "${aws_instance.nat.id}"
  route_table_id         = "${aws_route_table.internal_route_table.id}"
}

resource "aws_route_table_association" "route_internal_subnets" {
  count          = "${length(var.availability_zones)}"
  subnet_id      = "${element(aws_subnet.internal_subnets.*.id, count.index)}"
  route_table_id = "${aws_route_table.internal_route_table.id}"
}

resource "aws_internet_gateway" "ig" {
  vpc_id = "${local.vpc_id}"
}

locals {
  director_name        = "bosh-${var.env_id}"
  internal_cidr        = "${aws_subnet.bosh_subnet.cidr_block}"
  internal_gw          = "${cidrhost(local.internal_cidr, 1)}"
  jumpbox_internal_ip  = "${cidrhost(local.internal_cidr, 5)}"
  director_internal_ip = "${cidrhost(local.internal_cidr, 6)}"
}

resource "aws_kms_key" "kms_key" {
  enable_key_rotation = true
}

output "default_key_name" {
  value = "${aws_key_pair.bosh_vms.key_name}"
}

output "private_key" {
  value     = "${tls_private_key.bosh_vms.private_key_pem}"
  sensitive = true
}

output "external_ip" {
  value = "${aws_eip.jumpbox_eip.public_ip}"
}

output "jumpbox_url" {
  value = "${aws_eip.jumpbox_eip.public_ip}:22"
}

output "director_address" {
  value = "https://${aws_eip.jumpbox_eip.public_ip}:25555"
}

output "nat_eip" {
  value = "${aws_eip.nat_eip.public_ip}"
}

output "internal_security_group" {
  value = "${aws_security_group.internal_security_group.id}"
}

output "bosh_security_group" {
  value = "${aws_security_group.bosh_security_group.id}"
}

output "jumpbox_security_group" {
  value = "${aws_security_group.jumpbox.id}"
}

output "jumpbox__default_security_groups" {
  value = ["${aws_security_group.jumpbox.id}"]
}

output "director__default_security_groups" {
  value = ["${aws_security_group.bosh_security_group.id}"]
}

output "subnet_id" {
  value = "${aws_subnet.bosh_subnet.id}"
}

output "az" {
  value = "${aws_subnet.bosh_subnet.availability_zone}"
}

output "vpc_id" {
  value = "${local.vpc_id}"
}

output "region" {
  value = "${var.region}"
}

output "kms_key_arn" {
  value = "${aws_kms_key.kms_key.arn}"
}

output "internal_az_subnet_id_mapping" {
  value = "${
	  zipmap("${aws_subnet.internal_subnets.*.availability_zone}", "${aws_subnet.internal_subnets.*.id}")
	}"
}

output "internal_az_subnet_cidr_mapping" {
  value = "${
	  zipmap("${aws_subnet.internal_subnets.*.availability_zone}", "${aws_subnet.internal_subnets.*.cidr_block}")
	}"
}

output "director_name" {
  value = "${local.director_name}"
}

output "internal_cidr" {
  value = "${local.internal_cidr}"
}

output "internal_gw" {
  value = "${local.internal_gw}"
}

output "jumpbox__internal_ip" {
  value = "${local.jumpbox_internal_ip}"
}

output "director__internal_ip" {
  value = "${local.director_internal_ip}"
}

variable "bosh_iam_instance_profile" {
  default = ""
}

locals {
  iamProfileProvided = "${var.bosh_iam_instance_profile == "" ? 0 : 1 }"
}

data "aws_iam_instance_profile" "bosh" {
  name = "${var.bosh_iam_instance_profile}"

  count = "${local.iamProfileProvided}"
}

resource "aws_iam_role" "bosh" {
  name = "${var.env_id}_bosh_role"
  path = "/"

  count = "${1 - local.iamProfileProvided}"

  lifecycle {
    create_before_destroy = true
  }

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "bosh" {
  name = "${var.env_id}_bosh_policy"
  path = "/"

  count = "${1 - local.iamProfileProvided}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:AssociateAddress",
        "ec2:AttachVolume",
        "ec2:CopyImage",
        "ec2:CreateVolume",
        "ec2:DeleteSnapshot",
        "ec2:DeleteVolume",
        "ec2:DescribeAddresses",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSnapshots",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:DetachVolume",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:ModifyInstanceAttribute",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:RegisterImage",
        "ec2:DeregisterImage",
        "ec2:CancelSpotInstanceRequests",
        "ec2:DescribeSpotInstanceRequests",
        "ec2:RequestSpotInstances",
        "ec2:CreateRoute",
        "ec2:DescribeRouteTables",
        "ec2:ReplaceRoute"
	  ],
	  "Effect": "Allow",
	  "Resource": "*"
    },
	{
	  "Action": [
	    "iam:PassRole"
	  ],
	  "Effect": "Allow",
	  "Resource": "*"
	},
	{
	  "Action": [
	    "elasticloadbalancing:*"
	  ],
	  "Effect": "Allow",
	  "Resource": "*"
	},
        {
            "Effect": "Allow",
            "Action": [
                "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:CreateGrant",
                "kms:DescribeKey*"
            ],
            "Resource": [
                "*"
            ]
        }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "bosh" {
  role       = "${var.env_id}_bosh_role"
  policy_arn = "${aws_iam_policy.bosh.arn}"

  count = "${1 - local.iamProfileProvided}"
}

resource "aws_iam_instance_profile" "bosh" {
  name = "${var.env_id}-bosh"
  role = "${aws_iam_role.bosh.name}"

  count = "${1 - local.iamProfileProvided}"

  lifecycle {
    ignore_changes = ["name"]
  }
}

resource "aws_flow_log" "bbl" {
  log_group_name = "${aws_cloudwatch_log_group.bbl.name}"
  iam_role_arn   = "${aws_iam_role.flow_logs.arn}"
  vpc_id         = "${local.vpc_id}"
  traffic_type   = "REJECT"
}

resource "aws_cloudwatch_log_group" "bbl" {
  name_prefix = "${var.short_env_id}-log-group"
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.env_id}-flow-logs-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.env_id}-flow-logs-policy"
  role = "${aws_iam_role.flow_logs.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

output "iam_instance_profile" {
  value = "${local.iamProfileProvided ? join("", data.aws_iam_instance_profile.bosh.*.name) : join("", aws_iam_instance_profile.bosh.*.name)}"
}

variable "existing_vpc_id" {
  type        = "string"
  default     = ""
  description = "Optionally use an existing vpc"
}

locals {
  vpc_count = "${length(var.existing_vpc_id) > 0 ? 0 : 1}"
  vpc_id    = "${length(var.existing_vpc_id) > 0 ? var.existing_vpc_id : join(" ", aws_vpc.vpc.*.id)}"
}

resource "aws_vpc" "vpc" {
  count                = "${local.vpc_count}"
  cidr_block           = "${var.vpc_cidr}"
  instance_tenancy     = "default"
  enable_dns_hostnames = true

  tags {
    Name = "${var.env_id}-vpc"
  }
}

resource "aws_subnet" "lb_subnets" {
  count             = "${length(var.availability_zones)}"
  vpc_id            = "${local.vpc_id}"
  cidr_block        = "${cidrsubnet(var.vpc_cidr, 8, count.index+2)}"
  availability_zone = "${element(var.availability_zones, count.index)}"

  tags {
    Name = "${var.env_id}-lb-subnet${count.index}"
  }

  lifecycle {
    ignore_changes = ["cidr_block", "availability_zone"]
  }
}

resource "aws_route_table" "lb_route_table" {
  vpc_id = "${local.vpc_id}"
}

resource "aws_route" "lb_route_table" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.ig.id}"
  route_table_id         = "${aws_route_table.lb_route_table.id}"
}

resource "aws_route_table_association" "route_lb_subnets" {
  count          = "${length(var.availability_zones)}"
  subnet_id      = "${element(aws_subnet.lb_subnets.*.id, count.index)}"
  route_table_id = "${aws_route_table.lb_route_table.id}"
}

output "lb_subnet_ids" {
  value = ["${aws_subnet.lb_subnets.*.id}"]
}

output "lb_subnet_availability_zones" {
  value = ["${aws_subnet.lb_subnets.*.availability_zone}"]
}

output "lb_subnet_cidrs" {
  value = ["${aws_subnet.lb_subnets.*.cidr_block}"]
}

resource "aws_security_group" "concourse_lb_internal_security_group" {
  name        = "${var.env_id}-concourse-lb-internal-security-group"
  description = "Concourse Internal"
  vpc_id      = "${local.vpc_id}"

  tags {
    Name = "${var.env_id}-concourse-lb-internal-security-group"
  }

  lifecycle {
    ignore_changes = ["name"]
  }
}

resource "aws_security_group_rule" "concourse_lb_internal_80" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.concourse_lb_internal_security_group.id}"
}

resource "aws_security_group_rule" "concourse_lb_internal_2222" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 2222
  to_port     = 2222
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.concourse_lb_internal_security_group.id}"
}

resource "aws_security_group_rule" "concourse_lb_internal_443" {
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.concourse_lb_internal_security_group.id}"
}

resource "aws_security_group_rule" "concourse_lb_internal_egress" {
  type        = "egress"
  protocol    = "-1"
  from_port   = 0
  to_port     = 0
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.concourse_lb_internal_security_group.id}"
}

resource "aws_lb" "concourse_lb" {
  name               = "${var.short_env_id}-concourse-lb"
  load_balancer_type = "network"
  subnets            = ["${aws_subnet.lb_subnets.*.id}"]
}

resource "aws_lb_listener" "concourse_lb_80" {
  load_balancer_arn = "${aws_lb.concourse_lb.arn}"
  protocol          = "TCP"
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.concourse_lb_80.arn}"
  }
}

resource "aws_lb_target_group" "concourse_lb_80" {
  name     = "${var.short_env_id}-concourse80"
  port     = 80
  protocol = "TCP"
  vpc_id   = "${local.vpc_id}"

  health_check {
    healthy_threshold   = 10
    unhealthy_threshold = 10
    interval            = 30
    protocol            = "TCP"
  }
}

resource "aws_lb_listener" "concourse_lb_2222" {
  load_balancer_arn = "${aws_lb.concourse_lb.arn}"
  protocol          = "TCP"
  port              = 2222

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.concourse_lb_2222.arn}"
  }
}

resource "aws_lb_target_group" "concourse_lb_2222" {
  name     = "${var.short_env_id}-concourse2222"
  port     = 2222
  protocol = "TCP"
  vpc_id   = "${local.vpc_id}"
}

resource "aws_lb_listener" "concourse_lb_443" {
  load_balancer_arn = "${aws_lb.concourse_lb.arn}"
  protocol          = "TCP"
  port              = 443

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.concourse_lb_443.arn}"
  }
}

resource "aws_lb_target_group" "concourse_lb_443" {
  name     = "${var.short_env_id}-concourse443"
  port     = 443
  protocol = "TCP"
  vpc_id   = "${local.vpc_id}"
}

output "concourse_lb_internal_security_group" {
  value = "${aws_security_group.concourse_lb_internal_security_group.name}"
}

output "concourse_lb_target_groups" {
  value = ["${aws_lb_target_group.concourse_lb_80.name}", "${aws_lb_target_group.concourse_lb_443.name}", "${aws_lb_target_group.concourse_lb_2222.name}"]
}

output "concourse_lb_name" {
  value = "${aws_lb.concourse_lb.name}"
}

output "concourse_lb_url" {
  value = "${aws_lb.concourse_lb.dns_name}"
}
