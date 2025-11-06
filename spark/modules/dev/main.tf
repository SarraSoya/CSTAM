module "vpc" {
  source = "../../modules/vpc"
}

module "spark" {
  source    = "../../modules/spark"
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnets[0]
  key_name  = var.key_name
}
