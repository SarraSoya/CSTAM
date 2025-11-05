output "instance_id" { value = aws_instance.this.id }
output "private_ip" { value = aws_instance.this.private_ip }
output "ec2_security_group_id" { value = aws_security_group.ec2_sg.id }
