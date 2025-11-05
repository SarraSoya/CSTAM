import os
import json
import logging
import asyncio
from typing import Dict
from datetime import datetime, timedelta
from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel, Field
from jose import JWTError, jwt
from passlib.context import CryptContext

# Confluent Kafka imports
from confluent_kafka import Producer, KafkaException
from confluent_kafka.admin import AdminClient, NewTopic

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)


# --- Configuration (using environment variables for security) ---
class Settings:
    """
    Application settings loaded from environment variables.
    """

    KAFKA_BOOTSTRAP_SERVERS: str = os.getenv(
        "KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"
    )
    SECRET_KEY: str = os.getenv("SECRET_KEY", "your_super_secret_key")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    KAFKA_TOPIC_HEARTRATE: str = os.getenv("KAFKA_TOPIC_HEARTRATE", "heartrate")
    KAFKA_TOPIC_CALORIES: str = os.getenv("KAFKA_TOPIC_CALORIES", "calories")
    KAFKA_TOPIC_STEPS: str = os.getenv("KAFKA_TOPIC_STEPS", "steps")


settings = Settings()

# --- FastAPI App Initialization ---
app = FastAPI(
    title="Secure Fitness Data Ingestion API",
    description="A secure API to ingest fitness data streams into Kafka topics.",
    version="1.0.0",
)

# --- Security and Authentication ---
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# Mock user DB (for example only)
users_db = {
    "user123": {
        "username": "user123",
        "hashed_password": pwd_context.hash("securepassword"),
    }
}


def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)


def get_user(username: str):
    if username in users_db:
        return users_db[username]
    return None


def create_access_token(data: dict, expires_delta: timedelta | None = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(
            minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
        )
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(
        to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM
    )
    return encoded_jwt


async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    user = get_user(username=username)
    if user is None:
        raise credentials_exception
    return user


# --- Kafka Globals ---
kafka_producer: Producer | None = None
_kafka_poll_task: asyncio.Task | None = None
_kafka_stop_event: asyncio.Event | None = None
admin_client: AdminClient | None = None


def delivery_report(err, msg):
    """Delivery callback — called (by poll) when a message is delivered or delivery failed."""
    if err is not None:
        logging.error(f"Message delivery failed: {err} (topic={msg.topic()})")
    else:
        logging.info(
            f"Message delivered to {msg.topic()} [{msg.partition()}] @ offset {msg.offset()}"
        )


async def _kafka_poll_loop(
    producer: Producer, stop_event: asyncio.Event, interval: float = 0.1
):
    """Background task to call producer.poll() so callbacks are triggered."""
    logging.info("Kafka poll loop started.")
    try:
        while not stop_event.is_set():
            # poll(0) processes queued callbacks, but does not block
            producer.poll(0)
            await asyncio.sleep(interval)
    except asyncio.CancelledError:
        logging.info("Kafka poll loop cancelled.")
    except Exception as e:
        logging.exception("Unexpected error inside kafka poll loop: %s", e)
    finally:
        logging.info("Kafka poll loop stopped.")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Initialize Kafka Producer and AdminClient on app startup, create topics if needed,
    and start the poll loop. On shutdown, stop poll loop and flush producer.
    """
    global kafka_producer, _kafka_poll_task, _kafka_stop_event, admin_client

    # Create producer
    try:
        conf = {
            "bootstrap.servers": settings.KAFKA_BOOTSTRAP_SERVERS,
            # You can add other conf options here (security, acks, linger.ms, etc.)
            # e.g. "acks": "all" or SSL/SASL settings when needed.
        }
        kafka_producer = Producer(conf)
        logging.info(
            "Configured confluent-kafka Producer with bootstrap.servers=%s",
            settings.KAFKA_BOOTSTRAP_SERVERS,
        )
    except Exception as e:
        kafka_producer = None
        logging.exception("Failed to create Kafka Producer: %s", e)

    # Create AdminClient (for topic creation)
    try:
        admin_client = AdminClient(
            {"bootstrap.servers": settings.KAFKA_BOOTSTRAP_SERVERS}
        )
        logging.info("Configured AdminClient.")
    except Exception as e:
        admin_client = None
        logging.exception("Failed to create AdminClient: %s", e)

    # Try create topics (idempotent)
    topics_to_ensure = {
        settings.KAFKA_TOPIC_HEARTRATE: {"num_partitions": 1, "replication_factor": 1},
        settings.KAFKA_TOPIC_CALORIES: {"num_partitions": 1, "replication_factor": 1},
        settings.KAFKA_TOPIC_STEPS: {"num_partitions": 1, "replication_factor": 1},
    }

    if admin_client:
        new_topics = []
        for t, cfg in topics_to_ensure.items():
            new_topics.append(
                NewTopic(
                    t,
                    num_partitions=cfg["num_partitions"],
                    replication_factor=cfg["replication_factor"],
                )
            )

        try:
            fs = admin_client.create_topics(new_topics, request_timeout=10)
            # Wait for results (short timeout)
            for topic, future in fs.items():
                try:
                    future.result(timeout=5)
                    logging.info("Topic created or already existed: %s", topic)
                except Exception as e:
                    # If topic exists, creation will raise TopicAlreadyExistsError — that's fine
                    logging.debug("create_topics result for %s: %s", topic, e)
        except Exception as e:
            logging.exception("Failed to create topics via AdminClient: %s", e)

    # Start poll background task
    if kafka_producer:
        _kafka_stop_event = asyncio.Event()
        _kafka_poll_task = asyncio.create_task(
            _kafka_poll_loop(kafka_producer, _kafka_stop_event, interval=0.1)
        )

    yield

    # Shutdown: stop poll task, flush producer
    if _kafka_stop_event:
        _kafka_stop_event.set()

    if _kafka_poll_task:
        try:
            await asyncio.wait_for(_kafka_poll_task, timeout=5)
        except asyncio.TimeoutError:
            _kafka_poll_task.cancel()
            logging.warning("Kafka poll task did not stop in time; cancelled.")

    if kafka_producer:
        try:
            kafka_producer.flush(timeout=10)
            logging.info("Kafka producer flushed on shutdown.")
        except Exception as e:
            logging.exception("Error flushing Kafka producer on shutdown: %s", e)


app.router.lifespan_context = lifespan


def _safe_produce(
    topic: str, key: str | None, value: bytes, max_retries: int = 3
) -> bool:
    """
    Try to produce with a small retry loop to recover from transient BufferError (local producer queue full).
    Returns True if message was enqueued, False otherwise.
    """
    if kafka_producer is None:
        logging.error("Kafka producer is not initialized.")
        return False

    attempt = 0
    while attempt < max_retries:
        attempt += 1
        try:
            # key can be None; Confluent accepts str for key (it will be encoded)
            kafka_producer.produce(
                topic, key=key, value=value, callback=delivery_report
            )
            # Note: produce() enqueues the message; poll() must be called to trigger callback.
            return True
        except BufferError as be:
            # Local queue is full. Poll to make space and retry.
            logging.warning(
                "Local producer queue is full (attempt %d/%d). Polling and retrying...",
                attempt,
                max_retries,
            )
            kafka_producer.poll(1)  # give it a second to clear callbacks
            continue
        except KafkaException as ke:
            logging.exception(
                "KafkaException while producing (attempt %d/%d): %s",
                attempt,
                max_retries,
                ke,
            )
            return False
        except Exception as e:
            logging.exception("Unexpected exception while producing: %s", e)
            return False

    logging.error("Failed to enqueue message after %d attempts", max_retries)
    return False


def publish_to_kafka(topic: str, data: Dict) -> bool:
    """
    Publish a dict to Kafka (JSON-encoded). Return True if message was enqueued successfully.
    Delivery will be confirmed in the delivery_report callback (logged).
    """
    try:
        json_data = json.dumps(data, default=str)
        byte_data = json_data.encode("utf-8")
        key = data.get("user_id") if isinstance(data, dict) else None
        return _safe_produce(
            topic, key=str(key) if key is not None else None, value=byte_data
        )
    except Exception as e:
        logging.exception("Failed to publish message to Kafka: %s", e)
        return False


# --- Pydantic Data Models for Ingestion ---
class HeartRate(BaseModel):
    user_id: str
    time: datetime
    heart_rate: int = Field(..., ge=0, le=250)


class Calories(BaseModel):
    user_id: str
    time: datetime
    calories: float = Field(..., ge=0)


class Steps(BaseModel):
    user_id: str
    time: datetime
    steps: int = Field(..., ge=0)


# --- API Endpoints ---
@app.post("/token", tags=["Authentication"])
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
    user = get_user(form_data.username)
    if not user or not verify_password(form_data.password, user["hashed_password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user["username"]}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}


@app.post("/ingest/heartrate", tags=["Data Ingestion"])
async def ingest_heartrate(
    data: HeartRate, current_user: dict = Depends(get_current_user)
):
    if publish_to_kafka(settings.KAFKA_TOPIC_HEARTRATE, data.dict()):
        return {
            "status": "success",
            "message": "Heart rate data ingested successfully.",
        }
    else:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to ingest data into Kafka.",
        )


@app.post("/ingest/calories", tags=["Data Ingestion"])
async def ingest_calories(
    data: Calories, current_user: dict = Depends(get_current_user)
):
    if publish_to_kafka(settings.KAFKA_TOPIC_CALORIES, data.dict()):
        return {"status": "success", "message": "Calories data ingested successfully."}
    else:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to ingest data into Kafka.",
        )


@app.post("/ingest/steps", tags=["Data Ingestion"])
async def ingest_steps(data: Steps, current_user: dict = Depends(get_current_user)):
    if publish_to_kafka(settings.KAFKA_TOPIC_STEPS, data.dict()):
        return {"status": "success", "message": "Steps data ingested successfully."}
    else:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to ingest data into Kafka.",
        )


@app.get("/health", tags=["Health"])
async def health():
    """Simple health check for Kafka connectivity and topics."""
    if kafka_producer is None:
        raise HTTPException(status_code=503, detail="Kafka producer not initialized")

    try:
        md = kafka_producer.list_topics(timeout=5)
        # metadata returns a Metadata object; list available topic names
        topic_names = list(md.topics.keys()) if md and hasattr(md, "topics") else []
        return {
            "status": "ok",
            "bootstrap_servers": settings.KAFKA_BOOTSTRAP_SERVERS,
            "topics": topic_names,
        }
    except Exception as e:
        logging.exception("Health check failed while fetching metadata: %s", e)
        raise HTTPException(status_code=503, detail=f"Kafka metadata fetch failed: {e}")


# --- Main execution block for local development ---
if __name__ == "__main__":
    import uvicorn

    # Requirements:
    # pip install fastapi uvicorn confluent-kafka python-jose[cryptography] passlib[bcrypt] pydantic
    # Example environment variables:
    # export KAFKA_BOOTSTRAP_SERVERS="localhost:9092"
    # export SECRET_KEY="your_super_secret_key"
    uvicorn.run(app, host="0.0.0.0", port=8001)
