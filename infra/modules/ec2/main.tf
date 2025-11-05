resource "aws_security_group" "ec2_sg" {
  vpc_id = var.vpc_id
  name   = "${var.environment}-ec2-sg"

  # keep private: no ingress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.environment}-ec2-sg" }
}

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile_name

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    mkdir -p /opt/ingestion_api /opt/realtime_simulator /data
    chown -R ec2-user:ec2-user /opt /data

    yum update -y
    yum install -y python3 python3-pip gcc make openssl-devel awscli librdkafka-devel

    BUCKET="${var.s3_bucket_name}"
    aws s3 cp s3://$BUCKET/realtime_simulator/ /opt/realtime_simulator/ --recursive || true
    aws s3 cp s3://$BUCKET/ingestion_api/      /opt/ingestion_api/      --recursive || true

    pip3 install --upgrade pip
    pip3 install confluent-kafka pandas

    cat >/opt/realtime_simulator/producer.py <<'PY'
    import csv, os
    from confluent_kafka import Producer

    BOOTSTRAP=os.environ.get("BOOTSTRAP","")
    TOPIC=os.environ.get("TOPIC","fitness-metrics")
    CSV=os.environ.get("CSV","/opt/realtime_simulator/heartrate_seconds_merged.csv")

    p=Producer({"bootstrap.servers": BOOTSTRAP, "security.protocol":"ssl"})
    with open(CSV, newline='') as f:
        r=csv.DictReader(f)
        for i,row in enumerate(r):
            p.produce(TOPIC, key=row.get("Id",""), value=str(row))
            if i % 1000 == 0:
                p.flush()
    p.flush()
    print("Done.")
    PY

    export BOOTSTRAP="${var.bootstrap_brokers_tls}"
    export TOPIC="fitness-metrics"
    export CSV="/opt/realtime_simulator/heartrate_seconds_merged.csv"
    python3 /opt/realtime_simulator/producer.py || true

    echo "Setup complete" > /opt/SETUP_OK
  EOF

  tags = { Name = "${var.environment}-private-ec2" }
}
