resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.environment}-vpc" }
}

# IGW (required because we have a public subnet; enables NAT/bastion later)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-igw" }
}

# --- Subnets ---
# AZ-1: Public
resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.azs[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.environment}-public-az1" }
}

# AZ-1: Private (App/EC2)
resource "aws_subnet" "private_app_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = var.azs[0]
  tags              = { Name = "${var.environment}-private-app-az1" }
}

# AZ-1: Private (MSK broker 1)
resource "aws_subnet" "private_msk_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = var.azs[0]
  tags              = { Name = "${var.environment}-private-msk-az1" }
}

# AZ-2: Private (MSK broker 2)
resource "aws_subnet" "private_msk_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = var.azs[1]
  tags              = { Name = "${var.environment}-private-msk-az2" }
}

# --- Route tables ---
# Public RT → IGW
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.environment}-public-rt" }
}

resource "aws_route_table_association" "public_assoc_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public_rt.id
}

# Private RTs (one per AZ)
resource "aws_route_table" "private_rt_az1" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-private-rt-az1" }
}
resource "aws_route_table_association" "private_app_az1_assoc" {
  subnet_id      = aws_subnet.private_app_az1.id
  route_table_id = aws_route_table.private_rt_az1.id
}
resource "aws_route_table_association" "private_msk_az1_assoc" {
  subnet_id      = aws_subnet.private_msk_az1.id
  route_table_id = aws_route_table.private_rt_az1.id
}

resource "aws_route_table" "private_rt_az2" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-private-rt-az2" }
}
resource "aws_route_table_association" "private_msk_az2_assoc" {
  subnet_id      = aws_subnet.private_msk_az2.id
  route_table_id = aws_route_table.private_rt_az2.id
}
