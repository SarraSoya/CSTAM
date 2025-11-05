output "vpc_id" { value = aws_vpc.main.id }
output "public_subnet_id_az1" { value = aws_subnet.public_az1.id }
output "private_app_subnet_id" { value = aws_subnet.private_app_az1.id }
output "private_msk_subnet_ids" { value = [aws_subnet.private_msk_az1.id, aws_subnet.private_msk_az2.id] }
output "private_rt_id_az1" { value = aws_route_table.private_rt_az1.id }
output "private_rt_id_az2" { value = aws_route_table.private_rt_az2.id }
