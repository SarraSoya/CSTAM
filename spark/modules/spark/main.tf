# Security group pour l'instance Spark
resource "aws_security_group" "spark_sg" {
  name        = "spark-sg"
  description = "Allow SSH, Spark UI, and Kafka traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4040
    to_port     = 4050
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Instance EC2 unique pour Spark
resource "aws_instance" "spark_node" {
  ami           = "ami-0866a3c8686eaeeba"  # Ubuntu 22.04
  instance_type = "t3.medium"

  subnet_id     = var.subnet_id
  key_name      = var.key_name
  security_groups = [aws_security_group.spark_sg.id]

 user_data_base64 = base64encode(templatefile("${path.module}/user-data.sh", {
  FIREBASE_KEY_PATH = "/home/ubuntu/cstam2-1f2ec-firebase-adminsdk-fbsvc-2ab61a7ed6.json"
}))

  tags = {
    Name = "spark-sandbox-node"
  }
}

# Provisionner pour copier les fichiers et lancer le script
resource "null_resource" "upload_and_run" {
  depends_on = [aws_instance.spark_node]

  triggers = {
    instance_id = aws_instance.spark_node.id
  }

  connection {
    type        = "ssh"
    host        = aws_instance.spark_node.public_ip
    user        = "ubuntu"
    private_key = file("C:/Users/rouda/.ssh/my-keypair.pem")
  }

  provisioner "file" {
  source      = "../../spark-job.py" 
  destination = "/home/ubuntu/spark-job.py"   
}

provisioner "file" {
  source      = "../cstam2-1f2ec-firebase-adminsdk-fbsvc-2ab61a7ed6.json"
  destination = "/home/ubuntu/cstam2-1f2ec-firebase-adminsdk-fbsvc-2ab61a7ed6.json"
}

  provisioner "remote-exec" {
    inline = [
      "sleep 60",  # Attendre que l'instance termine l'initialisation
      "nohup python3 /home/ubuntu/spark-job.py > /home/ubuntu/spark-output.log 2>&1 &"
    ]
  }
}