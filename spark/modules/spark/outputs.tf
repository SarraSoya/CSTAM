output "spark_node_ip" {
  value = aws_instance.spark_node.public_ip
}

output "spark_ui_url" {
  value = "${aws_instance.spark_node.public_ip}:4040"
}