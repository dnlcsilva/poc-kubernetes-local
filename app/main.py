import hmac
import logging
import os
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import FileResponse, Response

app = FastAPI(
    title="POC Kubernetes Local",
    version=os.getenv("APP_VERSION", "1.0.0"),
)
REQUESTS = Counter("poc_http_requests_total", "Total HTTP requests", ["endpoint"])
ALERT_NOTIFICATIONS = Counter(
    "poc_alert_notifications_total",
    "Total Alertmanager webhook notifications",
    ["status"],
)
LOGGER = logging.getLogger("uvicorn.error")
STATIC_DIR = Path(__file__).resolve().parent / "static"


class Alert(BaseModel):
    status: str
    labels: dict[str, str] = Field(default_factory=dict)


class AlertNotification(BaseModel):
    status: str
    alerts: list[Alert] = Field(default_factory=list)

@app.get("/", include_in_schema=False)
def root():
    REQUESTS.labels(endpoint="/").inc()
    return FileResponse(STATIC_DIR / "index.html", media_type="text/html")

@app.get("/healthz")
def healthz():
    REQUESTS.labels(endpoint="/healthz").inc()
    return {"status": "ok"}

@app.get("/info")
def info():
    REQUESTS.labels(endpoint="/info").inc()
    return {
        "environment": os.getenv("APP_ENV", "unknown"),
        "version": app.version,
        "api_key_configured": bool(os.getenv("API_KEY")),
    }

@app.get("/secure", responses={401: {"description": "Invalid API key"}})
def secure(x_api_key: Annotated[str | None, Header()] = None):
    REQUESTS.labels(endpoint="/secure").inc()
    expected_api_key = os.getenv("API_KEY")
    if not expected_api_key or not x_api_key or not hmac.compare_digest(x_api_key, expected_api_key):
        raise HTTPException(status_code=401, detail="Invalid API key")
    return {"status": "authorized"}


@app.post("/alerts", responses={401: {"description": "Invalid bearer token"}})
def alerts(
    notification: AlertNotification,
    authorization: Annotated[str | None, Header()] = None,
):
    expected_api_key = os.getenv("API_KEY")
    expected_token = f"Bearer {expected_api_key}" if expected_api_key else ""
    if not authorization or not hmac.compare_digest(authorization, expected_token):
        raise HTTPException(status_code=401, detail="Invalid bearer token")

    ALERT_NOTIFICATIONS.labels(status=notification.status).inc()
    LOGGER.info(
        "Alertmanager notification received: status=%s alerts=%d",
        notification.status,
        len(notification.alerts),
    )
    return {"status": "accepted", "alerts": len(notification.alerts)}

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
