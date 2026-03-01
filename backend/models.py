from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


class Scan(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    item: str
    action: str
    reason: str
    confidence: str
    city: str
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
