# Use two available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# ---------------- VPC (2 AZs) ----------------
module "vpc" {
  source      = "../../modules/vpc"
  vpc_cidr    = var.vpc_cidr
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
  environment = var.environment
}

# ---------------- S3 (module) ----------------
module "s3" {
  source      = "../../modules/S3" # matches your folder name
  environment = var.environment
  aws_region  = var.aws_region
}

# Gateway VPC Endpoint for S3 (private EC2 -> S3 without NAT)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    module.vpc.private_rt_id_az1,
    module.vpc.private_rt_id_az2
  ]
  tags = { Name = "${var.environment}-s3-endpoint" }
}

# ---------------- IAM for EC2 ----------------
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

# Optional: SSM (useful if you later add SSM VPC Endpoints or NAT)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow EC2 to List/Get only from the S3 bucket created by the S3 module
resource "aws_iam_policy" "s3_read_bucket" {
  name = "${var.environment}-s3-read-bucket"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = module.s3.bucket_arn },
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${module.s3.bucket_arn}/*" }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_read_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_read_bucket.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# ---------------- MSK (2 brokers: 1 per AZ) ----------------
module "msk" {
  source                = "../../modules/msk"
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_msk_subnet_ids
  environment           = var.environment
  ec2_security_group_id = null # ingress rule added below after EC2 SG exists
}

# ---------------- EC2 (private app subnet in AZ-1) ----------------
module "ec2" {
  source                    = "../../modules/ec2"
  vpc_id                    = module.vpc.vpc_id
  private_subnet_id         = module.vpc.private_app_subnet_id
  ami_id                    = var.ec2_ami
  instance_type             = var.ec2_instance_type
  key_name                  = var.key_name
  environment               = var.environment
  iam_instance_profile_name = aws_iam_instance_profile.ec2_profile.name

  # pass S3 bucket + MSK bootstrap to EC2 user_data
  s3_bucket_name        = module.s3.bucket_name
  bootstrap_brokers_tls = module.msk.bootstrap_brokers_tls
}

# Allow EC2 to talk to MSK on TLS 9094
resource "aws_security_group_rule" "msk_ingress_from_ec2" {
  type                     = "ingress"
  from_port                = 9094
  to_port                  = 9094
  protocol                 = "tcp"
  security_group_id        = module.msk.security_group_id
  source_security_group_id = module.ec2.ec2_security_group_id
  description              = "TLS from EC2 to MSK"
}
