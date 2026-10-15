<div align="center">

# CSTAM — Real-Time Health & Fitness Data Platform

**Streams wearable data (heart rate, calories, steps) through Kafka and Spark, detects health anomalies in real time and builds personalized daily plans.**

![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-JWT-009688?logo=fastapi&logoColor=white)
![Kafka](https://img.shields.io/badge/Apache_Kafka-KRaft-231F20?logo=apachekafka&logoColor=white)
![Spark](https://img.shields.io/badge/Spark-3.5_Structured_Streaming-E25A1C?logo=apachespark&logoColor=white)
![Firestore](https://img.shields.io/badge/Cloud_Firestore-Firebase-FFCA28?logo=firebase&logoColor=black)
![MongoDB](https://img.shields.io/badge/MongoDB-6.0-47A248?logo=mongodb&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)

</div>

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [API Reference](#api-reference)
- [Data Model](#data-model)
- [Roadmap](#roadmap)
- [Author](#author)

---

## Overview

CSTAM is an end-to-end **data engineering platform** for health and fitness data:

1. **Ingest**: a simulator replays real Fitbit records (heart rate every second, calories and steps every minute) into a JWT-secured **FastAPI** API, which publishes them to **Apache Kafka**.
2. **Process in real time**: **Spark Structured Streaming** consumes the topics, cleans and normalizes the events, detects anomalies and writes metrics and alerts to **Cloud Firestore**. In parallel, a **notification engine** applies threshold rules and pushes alerts over **WebSocket**.
3. **Plan**: a **FastAPI + MongoDB** service assigns each user a goal and generates monthly calorie targets. A **Spark batch job** then computes a daily **fatigue score** and builds an adaptive, explainable **daily plan** (calories, water, sleep, meals, activities).

---

## Architecture

![CSTAM architecture](architecture.gif)

---

## Components

### ① Ingestion

| Component | File | Role |
|---|---|---|
| Real-time simulator | `realtime_simulator.py` | Replays Fitbit CSVs: heart rate every 1 s, calories and steps every 60 s; authenticates and calls the API |
| Ingestion API | `ingestion_api.py` | FastAPI on `:8000`: OAuth2 password flow → JWT (HS256, 30 min), Pydantic validation, publishes to Kafka |

### ② Streaming backbone

- **Apache Kafka** in KRaft mode (no ZooKeeper), broker on `:9092`
- Topics: `heartrate`, `calories`, `steps`, `alerts`
- **AKHQ** web UI on `:8090` to browse topics and messages

### ③ Real-time processing

**Spark Structured Streaming** (`spark/data-cleaning.ipynb`):
- `readStream` on the 3 topics, then JSON parsing against explicit schemas
- timestamp normalization (seconds, milliseconds or ISO), filtering of invalid values (heart rate kept in 0–300)
- anomaly rules:

  | Signal | Rule | Alert type |
  |---|---|---|
  | Heart rate | `> 180` or `< 45` bpm | `heart_rate` |
  | Calories | `< 0.5` | `low_calories` |
  | Steps | `= 0` | `inactivity` |

- `foreachBatch` writer to Firestore, with batching, retries and one checkpoint per stream

**Notification engine** (`notification_engine.py`, FastAPI on `:8001`):
- Kafka consumer group on `heartrate` and `steps`
- rules: heart rate `< 50` or `> 120` bpm, steps `< 500` or `> 10 000`
- publishes alert events to the `alerts` topic and broadcasts them to clients on `ws://localhost:8001/ws/alerts`

### ④ Batch analytics & personalized planning

**Monthly plan service** (`monthly_plan/pipeline_main.py`, FastAPI + MongoDB `fitness_db`):

| Stage | Endpoint | Collection |
|---|---|---|
| 1. Load user profiles | `POST /load-users` | `users_raw` |
| 2. Assign goal, target weight and pace (automatic or manual) | `POST /targets/users` · `POST /targets/users/{user_id}` | `users_with_targets` |
| 3. Generate monthly plans: calories/day and burn targets (7 700 kcal per kg) | `POST /generate-plans` | `users_monthly_plan` |

**Daily planner** (`spark/daily planner.ipynb`, Spark batch):
1. Loads each user's last-24 h metrics, daily meals and monthly plan from Firestore.
2. Computes a **fatigue score** from sleep, steps, energy balance and hydration, giving the states **Exhausted** (< 0.4), **Tired** (< 0.65) and **Normal** (< 0.85).
3. Adjusts the daily targets, with a human-readable reasoning for each change.
4. Builds meals from a food nutrition dataset (breakfast, lunch, snack, dinner) and picks activities that match the fatigue state.
5. Writes the result to `users/{uid}/daily_plan`, rate-limited to stay within the Firestore free tier.

**Data generation** (`spark/data generation.ipynb`) creates synthetic daily meals and monthly plans in Firestore for testing.

---

## Tech Stack

| Layer | Technologies |
|---|---|
| APIs | FastAPI, Uvicorn, Pydantic, python-jose (JWT), passlib (bcrypt), WebSocket |
| Messaging | Apache Kafka (KRaft), kafka-python, AKHQ |
| Processing | Apache Spark 3.5 (Structured Streaming + batch), PySpark, Jupyter Lab, pandas |
| Storage | Cloud Firestore (Firebase Admin SDK), MongoDB 6 (pymongo), Mongo Express |
| Infrastructure | Docker Compose; custom Spark image with Kafka and MongoDB connectors |

---

## Project Structure

```text
CSTAM/
├── docker-compose.yml          # Kafka, AKHQ, Spark notebook, MongoDB, Mongo Express, Redis, TimescaleDB, Grafana
├── spark-notebook.dockerfile   # Spark 3.5 + Jupyter + Kafka/Mongo connector JARs
├── requirements.txt            # API dependencies
├── ingestion_api.py            # FastAPI → Kafka producer (JWT-secured)
├── realtime_simulator.py       # Replays Fitbit CSVs as a live stream
├── notification_engine.py      # Kafka consumer → alerts topic + WebSocket
├── mongo-setup.sh              # MongoDB time-series collections
├── monthly_plan/
│   ├── pipeline_main.py        # Goals, targets and monthly plans (FastAPI + MongoDB)
│   └── users.json              # Synthetic user profiles
└── spark/
    ├── data-cleaning.ipynb     # Streaming: clean, detect anomalies, write to Firestore
    ├── data generation.ipynb   # Synthetic meals & monthly plans → Firestore
    ├── daily planner.ipynb     # Batch: fatigue score → adaptive daily plan
    ├── food_nutrition_dataset.csv   # (Git LFS)
    └── FOOD-DATA-MERGED.csv         # (Git LFS)
```

---

## Getting Started

### Prerequisites

- Docker and Docker Compose
- Python 3.10+
- [Git LFS](https://git-lfs.com/), for the nutrition datasets
- A Firebase project with a **service account key** (JSON)
- The Fitbit CSVs from the Fitbit Fitness Tracker dataset: `heartrate_seconds_merged.csv`, `minuteCaloriesNarrow_merged.csv`, `minuteStepsNarrow_merged.csv`

### 1. Start the infrastructure

```bash
git lfs pull
docker compose up -d
```

| Service | URL |
|---|---|
| Kafka (external) | `localhost:9092` |
| AKHQ (Kafka UI) | <http://localhost:8090> |
| Jupyter Lab + Spark | <http://localhost:8888> |
| MongoDB | `mongodb://root:example@localhost:27017` |
| Mongo Express | <http://localhost:8081> |

### 2. Run the APIs

```bash
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt pandas requests pymongo

export KAFKA_BOOTSTRAP_SERVERS=localhost:9092
export SECRET_KEY=<long-random-secret>

python ingestion_api.py                          # http://localhost:8000/docs
python notification_engine.py                    # ws://localhost:8001/ws/alerts
cd monthly_plan && uvicorn pipeline_main:app --port 8002   # Swagger UI at /
```

### 3. Start the streaming jobs

In Jupyter (`:8888`), put the Firebase key in `spark/` (or set `FIREBASE_SERVICE_ACCOUNT_KEY_PATH`), then run `data-cleaning.ipynb`.

### 4. Stream data

```bash
python realtime_simulator.py      # needs the Fitbit CSVs in the working directory
```

Watch the messages in AKHQ, the alerts on the WebSocket and the documents in Firestore.

### 5. Generate plans

1. Call `POST /load-users`, `POST /targets/users` and `POST /generate-plans` on the monthly plan API.
2. In Jupyter, run `data generation.ipynb`, then `daily planner.ipynb`.

> Never commit the Firebase service account key: it is listed in `.gitignore`.

---

## API Reference

**Ingestion API** (`:8000`)

| Method | Endpoint | Auth | Body |
|---|---|---|---|
| POST | `/token` | — | form: `username`, `password` → `access_token` |
| POST | `/ingest/heartrate` | Bearer | `{ user_id, time, heart_rate }` (0–250) |
| POST | `/ingest/calories` | Bearer | `{ user_id, time, calories }` (≥ 0) |
| POST | `/ingest/steps` | Bearer | `{ user_id, time, steps }` (≥ 0) |

**Notification engine** (`:8001`): `WS /ws/alerts` sends `{ user_id, time, alert }` events.

**Monthly plan API**:

| Method | Endpoint | Description |
|---|---|---|
| POST | `/load-users` | Load `users.json` into `users_raw` |
| POST | `/targets/users` | Auto-assign goals and targets to all users |
| GET | `/targets/users` | List users with targets |
| POST | `/targets/users/{user_id}` | Set a user's target manually |
| POST | `/generate-plans` | Generate monthly plans |
| GET | `/plans/users` | List all plans |
| GET | `/plans/user/{user_id}` | Plan for one user |

---

## Data Model

**Cloud Firestore**

| Path | Written by | Content |
|---|---|---|
| `users/{uid}/heart_rate` · `calories` · `steps` | Spark streaming | Cleaned time-stamped metrics |
| `alerts` | Spark streaming | `user_id`, `type`, `value`, `detected_at`, `status: waiting` |
| `users/{uid}/daily_meals` · `monthly_plan` | Data generation | Synthetic meals and monthly targets |
| `users/{uid}/daily_plan` | Daily planner | Fatigue state, adjusted targets, meals, activities, reasoning |

**MongoDB** (`fitness_db`): `users_raw` → `users_with_targets` → `users_monthly_plan`

---

## Roadmap

- [ ] Containerize the APIs and the simulator, and add them to `docker-compose.yml`
- [ ] Move all credentials (Kafka, MongoDB, Redis, JWT secret) to a `.env` file
- [ ] Refresh the JWT in the simulator during long runs
- [ ] Share one set of anomaly thresholds between Spark and the notification engine
- [ ] Feed the MongoDB monthly plans directly into the Spark daily planner
- [ ] Export the notebooks as scheduled Spark jobs (`spark-submit`)
- [ ] Wire the provisioned services: Redis (latest metrics cache), TimescaleDB and Grafana (time-series dashboards)
- [ ] Add tests and a CI pipeline

---

## Author

**Roudayna Kouka**: Software Engineering student (FST), Cloud · DevOps · Data
GitHub: [@roudayn-kouka](https://github.com/roudayn-kouka)
