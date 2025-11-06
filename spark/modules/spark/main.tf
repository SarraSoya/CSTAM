resource "aws_security_group" "spark_sg" {
  name        = "spark-sg"
  description = "Allow SSH and Spark traffic"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "spark_master" {
  ami           = "ami-0c55b159cbfafe1f0" # Ubuntu 22.04 (example)
  instance_type = "t2.micro"
  subnet_id     = var.subnet_id
  key_name      = var.key_name
  security_groups = [aws_security_group.spark_sg.id]

  tags = {
    Name = "spark-master"
  }
}

resource "aws_instance" "spark_worker" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  subnet_id     = var.subnet_id
  key_name      = var.key_name
  security_groups = [aws_security_group.spark_sg.id]

  tags = {
    Name = "spark-worker"
  }
}
