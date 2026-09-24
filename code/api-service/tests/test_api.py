import pandas as pd
from fastapi.testclient import TestClient

from app.main import app
from app.db import _records_from_df

client = TestClient(app)


def test_health():
    assert client.get("/health").status_code == 200


def test_sem_api_key_401():
    assert client.get("/api/v1/movies").status_code == 401


def test_api_key_errada_401():
    resp = client.get("/api/v1/movies", headers={"X-API-Key": "errada"})
    assert resp.status_code == 401


def test_nan_vira_null():
    df = pd.DataFrame({"a": [1, 2], "b": [1.5, float("nan")]})
    records = _records_from_df(df)
    assert records[1]["b"] is None
