from pyspark.sql import SparkSession
from pyspark.sql.functions import col, when, lit, to_timestamp, from_unixtime
from pyspark.sql.types import StructType, StructField, StringType, TimestampType, IntegerType, DoubleType
import time
import logging

# ---------- CONFIG ----------
KAFKA_BOOTSTRAP = "10.0.1.10:29092"  # Remplace par IP privée de ton Kafka
CHECKPOINT_BASE = "/tmp/checkpoints"  # Local temporaire pour sandbox

# ---------- SIMULATION MODE ----------
FIRESTORE_SIMULATION = True  # Mets à True pour simuler, False pour activer Firebase

if FIRESTORE_SIMULATION:
    # Simule les fonctions Firebase
    class MockFirestoreClient:
        def collection(self, name):
            return MockCollection(name)

    class MockCollection:
        def __init__(self, name):
            self.name = name

        def add(self, data):
            print(f"[SIMULATION] Données envoyées à Firestore: {self.name} -> {data}")

        def document(self, doc_id=None):
            return MockDocument(doc_id)

    class MockDocument:
        def __init__(self, doc_id):
            self.doc_id = doc_id

        def collection(self, name):
            return MockSubCollection(name)

    class MockSubCollection:
        def __init__(self, name):
            self.name = name

        def document(self):
            return MockDoc()

        def set(self, data):
            print(f"[SIMULATION] Écriture dans sous-collection: {self.name} -> {data}")

    class MockDoc:
        def set(self, data):
            print(f"[SIMULATION] Écriture Firestore: {data}")

    # Remplace db par une instance simulée
    db = MockFirestoreClient()
    print("⚠️ Mode simulation : Aucune donnée ne sera envoyée à Firebase")
else:
    # Code original pour connexion réelle
    import firebase_admin
    from firebase_admin import credentials, firestore
    import os

    SERVICE_ACCOUNT_KEY_PATH = os.environ.get("FIREBASE_SERVICE_ACCOUNT_KEY_PATH", "./cstam2-1f2ec-firebase-adminsdk-fbsvc-2ab61a7ed6.json")

    try:
        app = firebase_admin.get_app()
        print("Firebase Admin SDK already initialized. Reusing existing app instance.")
    except ValueError:
        try:
            cred = credentials.Certificate(SERVICE_ACCOUNT_KEY_PATH)
            app = firebase_admin.initialize_app(cred)
            print("Firebase Admin SDK initialized successfully.")
        except Exception as e:
            print(f"Error during Firebase Admin SDK initialization: {e}")
            raise

    db = firestore.client(app=app)

# ---------- Spark session (local mode) ----------
spark = (
    SparkSession.builder
    .appName("health-streams-to-firebase")
    .master("local[*]")  # Mode local avec tous les cœurs
    .config("spark.jars.packages", "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.1")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("ERROR")

# ... Le reste de ton script Spark ici ...