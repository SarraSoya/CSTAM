#!/bin/bash
set -e

# Variables
FIREBASE_KEY_PATH = "${FIREBASE_KEY_PATH}"

# Mettre à jour le système
apt update
apt install -y openjdk-11-jdk python3-pip wget unzip

# Télécharger et installer Spark
cd /tmp
wget https://dlcdn.apache.org/spark/spark-3.5.1/spark-3.5.1-bin-hadoop3.tgz
tar -xzf spark-3.5.1-bin-hadoop3.tgz
mv spark-3.5.1-bin-hadoop3 /opt/spark
chown -R ubuntu:ubuntu /opt/spark

# Variables d'environnement
echo 'export SPARK_HOME=/opt/spark' >> /home/ubuntu/.bashrc
echo 'export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin' >> /home/ubuntu/.bashrc
echo 'export PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9.7-src.zip:$PYTHONPATH' >> /home/ubuntu/.bashrc
echo 'export PYSPARK_PYTHON=/usr/bin/python3' >> /home/ubuntu/.bashrc

# Charger les variables
export SPARK_HOME=/opt/spark
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
export PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9.7-src.zip:$PYTHONPATH
export PYSPARK_PYTHON=/usr/bin/python3

# Installer les dépendances Python
pip3 install pyspark==3.5.1 kafka-python firebase-admin google-cloud-firestore