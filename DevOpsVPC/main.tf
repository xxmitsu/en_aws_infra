#
# Project Name:: en_aws_infra
# File:: main.tf
#
# Copyright (C) 2017 - Present
# Author: 'Mihai Vultur <mihai.vultur@endava.com>'
#
# All rights reserved
#
# Description:
#   Module import definitions with variables overrides.


provider "aws" {
  region                    = "${var.aws_region}"
  #-- must be fullpath, ~ is not evaluated
  shared_credentials_file   = "/home/vagrant/.aws/credentials"
}

resource "aws_key_pair" "xanto" {
  key_name = "${var.ssh_key_name}"
  public_key = "${var.ssh_public_key}"
}

resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_support   = "${var.enable_dns_support}"
  enable_dns_hostnames = "${var.enable_dns_hostnames}"
  lifecycle { 
    create_before_destroy = true
  }
  tags      {
    Name = "${var.vpc_name}"
  }
}

################# PUBLIC SUBNET

resource "aws_internet_gateway" "public" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = "${merge(var.default_tags, map("VPC", var.vpc_name), map("Name", format("%s_IGW.%s", var.vpc_name, element(var.aws_azs, count.index))))}"

}

resource "aws_subnet" "public" {
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${element(var.vpc_public_subnets, count.index)}"
  availability_zone = "${element(var.aws_azs, count.index)}"
  count             = "${length(var.vpc_public_subnets)}"

  tags = "${merge(var.default_tags, map("VPC", var.vpc_name), map("Name", format("%s_PubSubnet.%s", var.vpc_name, element(var.aws_azs, count.index))))}"

  lifecycle { create_before_destroy = true }

  map_public_ip_on_launch = true
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = "${aws_internet_gateway.public.id}"
  }

  tags = "${merge(var.default_tags, map("VPC", var.vpc_name), map("Name", format("%s_PubSubnet.%s", var.vpc_name, element(var.aws_azs, count.index))))}"
}

resource "aws_route_table_association" "public" {
  count          = "${length(var.vpc_public_subnets)}"
  subnet_id      = "${element(aws_subnet.public.*.id, count.index)}"
  route_table_id = "${aws_route_table.public.id}"
}


################## NAT INSTANCE

resource "aws_instance" "NatInstance" {
  ami                         = "${var.ec2_ami}"
  availability_zone           = "${var.aws_azs[0]}"
  instance_type               = "t2.micro"
  key_name                    = "${aws_key_pair.xanto.key_name}"
  security_groups             = ["${aws_security_group.Allow_ICMP.id}", "${aws_security_group.default.id}"]
  subnet_id                   = "${element(aws_subnet.public.*.id, count.index)}"

  source_dest_check           = false

  root_block_device {
    volume_type = "gp2"
    volume_size = 8
    delete_on_termination = true
  }
  tags = "${merge(var.default_tags, map("VPC", var.vpc_name), map("Name", format("%s-%s", var.vpc_name, "NAT_Instance")))}"
}

################ PRIVATE SUBNET

resource "aws_subnet" "private" {
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${element(var.vpc_private_subnets, count.index)}"
  availability_zone = "${element(var.aws_azs, count.index)}"
  count             = "${length(var.vpc_private_subnets)}"

  tags = "${merge(var.default_tags, map("VPC", var.vpc_name), map("Name", format("%s_PrvSubnet.%s", var.vpc_name, element(var.aws_azs, count.index))))}"
  lifecycle { create_before_destroy = true }
}

resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.vpc.id}"
  count  = "${length(var.vpc_private_subnets)}"

  route {
    cidr_block     = "0.0.0.0/0"
    instance_id    = "${aws_instance.NatInstance.id}"
#    nat_gateway_id = "${element(split(",", var.nat_gateway_ids), count.index)}"
  }

  tags = "${merge(var.default_tags, map("VPC", var.vpc_name), map("Name", format("%s_PrvSubnet.%s", var.vpc_name, element(var.aws_azs, count.index))))}"
  lifecycle { create_before_destroy = true }
}

resource "aws_route_table_association" "private" {
  count          = "${length(var.vpc_private_subnets)}"
  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"

  lifecycle { create_before_destroy = true }
}


# Security Group #
resource "aws_security_group" "Allow_ICMP" {
  vpc_id      = "${aws_vpc.vpc.id}"
  description = "Allow all ICMP traffic"

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${merge(var.default_tags, map("VPC", var.vpc_name), map("Name", format("%s_SG.%s", var.vpc_name, "Allow_ICMP")))}"
}

resource "aws_security_group" "default" {
  vpc_id      = "${aws_vpc.vpc.id}"
  description = "default VPC security group"

  # TCP access
  ingress {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    cidr_blocks = ["194.126.146.0/24"]
  }

  # HTTP access from anywhere
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  }

  tags = "${merge(var.default_tags, map("VPC", var.vpc_name), map("Name", format("%s_SG.%s", var.vpc_name, "default")))}"
}
