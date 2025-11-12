# ========== PROVIDER ==========
provider "aws" {
  region = "us-east-1"
}

# ========== VPC & NETWORKING ==========
resource "aws_vpc" "emr_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "cstam-emr-vpc" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.emr_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = element(["us-east-1a", "us-east-1b"], count.index)
  tags = { Name = "cstam-public-subnet-${count.index + 1}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.emr_vpc.id
  tags   = { Name = "cstam-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.emr_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "cstam-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ========== SECURITY GROUP ==========
resource "aws_security_group" "emr_sg" {
  vpc_id      = aws_vpc.emr_vpc.id
  description = "Security group for EMR"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "cstam-emr-sg" }
}

# ========== EMR CLUSTER ==========
resource "aws_emr_cluster" "cstam_cluster" {
  name          = "CSTAM-Health-EMR-Cluster"
  release_label = "emr-6.13.0"
  applications  = ["Spark", "Hadoop"]

  service_role = "EMR_DefaultRole"          # rôle service par défaut
  ec2_attributes {
    subnet_id                         = aws_subnet.public[0].id
    emr_managed_master_security_group = aws_security_group.emr_sg.id
    emr_managed_slave_security_group  = aws_security_group.emr_sg.id
    instance_profile                  = "EMR_EC2_DefaultRole"  # rôle EC2 par défaut
  }

  master_instance_group {
    instance_type  = "m5.large"
    instance_count = 1
  }

  core_instance_group {
    instance_type  = "m5.large"
    instance_count = 1
  }

  keep_job_flow_alive_when_no_steps = false

  tags = {
    Project = "CSTAM2.0"
    Team    = "YourTeamName"
  }
}

# ========== OUTPUTS ==========
output "cluster_id" {
  value = aws_emr_cluster.cstam_cluster.id
}

output "master_public_dns" {
  value     = aws_emr_cluster.cstam_cluster.master_public_dns
  sensitive = true
}
