output "spark_master_ip" {
  value = aws_instance.spark_master.public_ip
}

output "spark_worker_ip" {
  value = aws_instance.spark_worker.public_ip
}