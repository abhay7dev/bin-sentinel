from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel

MAX_IMAGE_BYTES = 10 * 1024 * 1024  # 10 MB


class Scan(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    item: str
    action: str
    reason: str
    confidence: str
    city: str
    model: str = Field(default="")
    latency_ms: Optional[int] = Field(default=None)
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
