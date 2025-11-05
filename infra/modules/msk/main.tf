resource "aws_security_group" "msk_sg" {
  vpc_id = var.vpc_id
  name   = "${var.environment}-msk-sg"

  # Ingress from EC2 added later in env
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.environment}-msk-sg" }
}

resource "aws_msk_cluster" "this" {
  cluster_name           = "${var.environment}-msk-cluster"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = 2

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = var.private_subnet_ids
    security_groups = [aws_security_group.msk_sg.id]
  }

  client_authentication {
    sasl {
      iam   = false
      scram = false
    }
    # Remove the invalid "tls { enabled = true }" block.
    # TLS is already handled below via encryption_in_transit.
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"   # This enables TLS for clients (port 9094)
      in_cluster    = true
    }
  }

  tags = { Name = "${var.environment}-msk" }
}
