### Module Main

provider "aws" {
  region = var.aws_region
}


#step 1

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "${var.vpc_name}-vpc"
    Terraform = "true"
  }
}

resource "aws_subnet" "public" {
  for_each = toset(var.vpc_azs)

  vpc_id     = aws_vpc.vpc.id
  availability_zone = "us-east-1${each.value}"
  cidr_block = cidrsubnet(var.vpc_cidr, 4, index(var.vpc_azs, each.value))
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.vpc_name}-public-${var.aws_region}${each.value}"
  }
}

resource "aws_subnet" "private" {
  for_each = toset(var.vpc_azs)

  vpc_id     = aws_vpc.vpc.id
  availability_zone = "us-east-1${each.value}"
  cidr_block = cidrsubnet(var.vpc_cidr, 4,15 - index(var.vpc_azs, each.value))

  tags = {
    Name = "${var.vpc_name}-private-${var.aws_region}${each.value}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

data "aws_ami" "nat_ami" {
  most_recent      = true
  owners           = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-vpc-nat-2018.03.0.2021*"]
  }
}

resource "aws_security_group" "allow_nat" {
  name        = "allow_nat"
  description = "Allow nat inbound traffic"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    Name = "${var.vpc_name}-allow_nat"
  }
}

resource "aws_security_group_rule" "nat_egress" {
  type        = "egress"
  description = "Traffic for nat"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.allow_nat.id
}

resource "aws_security_group_rule" "nat_ingress" {
  type        = "ingress"
  description = "Trafic for nat"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = [for subnet in aws_subnet.private : subnet.cidr_block]
  security_group_id = aws_security_group.allow_nat.id
}

resource "aws_security_group_rule" "nat_ingress_ssh" {
  type        = "ingress"
  description = "Trafic for ssh nat"
  from_port   = 22
  to_port     = 22
  protocol    = "TCP"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.allow_nat.id
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCgb4KJX+Rtdm4rfAllGeviFxt1ONlj8zwbHaaoCIbpBr52re3xT1LND/tiQyool0qL9iZQIjd89//EPXNzlvNPXM+XJhN5A2zgTmHanAoJt+6N6LDJRCUYfRI9ooJzkWsraB7IqAPe1/lxb8OH0LZjS+OYoGn/0zVzlEeKZlSJSSf+GF98AHKcWxvUVpU/E++Q7fmsHdCCYDzxf6SGpUzgVC+WiIJN/u+c2uAIF0ZJ/mdgBZhOi85ISuVfnXeYKvxVfZry7jsLjVCJrLOBBdWCY5twHgsCdjKWDqkfVRVNoam/2e+QKsJnyxg8ajlYLVrQCiIXgf9S6KjMc4VtvOqP"
}

resource "aws_instance" "public" {
  for_each = toset(var.vpc_azs)

  ami = data.aws_ami.nat_ami.id
  instance_type = "t2.micro"
  source_dest_check = false
  vpc_security_group_ids = [aws_security_group.allow_nat.id]
  subnet_id = aws_subnet.public[each.value].id
  key_name = aws_key_pair.deployer.key_name

  tags = {
    Name = "${var.vpc_name}-public-${var.aws_region}${each.value}"
  }
}

resource "aws_instance" "private" {
  for_each = toset(var.vpc_azs)

  ami = data.aws_ami.nat_ami.id
  instance_type = "t2.micro"
  source_dest_check = false
  vpc_security_group_ids = [aws_security_group.allow_nat.id]
  subnet_id = aws_subnet.private[each.value].id
  key_name = aws_key_pair.deployer.key_name

  tags = {
    Name = "${var.vpc_name}-private-${var.aws_region}${each.value}"
  }
}

resource "aws_eip" "eip" {
  for_each = toset(var.vpc_azs)
  vpc = true
  instance                  = aws_instance.public[each.value].id
  depends_on                = [aws_internet_gateway.gw]
}

resource "aws_eip_association" "eip_assoc" {
  for_each = toset(var.vpc_azs)
  instance_id   = aws_instance.public[each.value].id
  allocation_id = aws_eip.eip[each.value].id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.vpc_name}-public"
  }
}

resource "aws_route_table" "private" {
  for_each = toset(var.vpc_azs)
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.vpc_name}-private-${var.aws_region}${each.value}"
  }
}

resource "aws_route" "r-public" {
  route_table_id            = aws_route_table.public.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id
}

resource "aws_route" "r-private" {
  for_each = toset(var.vpc_azs)
  route_table_id            = aws_route_table.private[each.value].id
  destination_cidr_block    = "0.0.0.0/0"
  instance_id = aws_instance.public[each.value].id
}

resource "aws_route_table_association" "private" {
  for_each = toset(var.vpc_azs)
  subnet_id      = aws_subnet.private[each.value].id
  route_table_id = aws_route_table.private[each.value].id
}

resource "aws_route_table_association" "public" {
  for_each = toset(var.vpc_azs)
  subnet_id    = aws_subnet.public[each.value].id
  route_table_id = aws_route_table.public.id
}

output "vpc_id" {
  value = aws_vpc.vpc.id
}