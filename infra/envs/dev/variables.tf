variable "aws_region" { default = "eu-west-1" }
variable "environment" { default = "dev" }
variable "vpc_cidr" { default = "10.0.0.0/16" }
variable "ec2_ami" { default = "ami-0c7217cdde317cfec" } # Amazon Linux 2 eu-west-1
variable "ec2_instance_type" { default = "t3.micro" }
variable "key_name" { default = "my-keypair" }
