output "bucket_name" { value = module.s3.bucket_name }
output "vpc_id" { value = module.vpc.vpc_id }
output "public_subnet_id_az1" { value = module.vpc.public_subnet_id_az1 }
output "private_app_subnet_id" { value = module.vpc.private_app_subnet_id }
output "private_msk_subnet_ids" { value = module.vpc.private_msk_subnet_ids }
output "ec2_private_ip" { value = module.ec2.private_ip }
output "msk_bootstrap_brokers_tls" { value = module.msk.bootstrap_brokers_tls }
