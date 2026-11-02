from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


# ============================================================
# EVENTS
# ============================================================

class EventResponse(BaseModel):
    serial: int

    # Database column is events.id.
    # API exposes the clearer name activity_id.
    activity_id: int = Field(
        validation_alias="id"
    )

    time_updated: datetime
    time_started: datetime
    systimeentered: datetime
    details: str
    operator: str

    model_config = ConfigDict(
        from_attributes=True,
        populate_by_name=True,
    )


class EventCreate(BaseModel):
    time_started: datetime
    details: str
    operator: str


# ============================================================
# ACTIVITIES
# ============================================================

class ActivitySummary(BaseModel):
    id: int
    taskno: int
    est_time: datetime

    title: str

    status: Optional[str] = None
    closed: Optional[str] = None

    environment: str
    subenvironment: str

    resource: Optional[str] = None

    unplannedact: bool
    criticalact: bool
    deleted: bool

    model_config = ConfigDict(
        from_attributes=True
    )


class ActivityResponse(BaseModel):
    id: int
    taskno: int
    est_time: datetime

    title: str
    details: str

    status: Optional[str] = None
    closed: Optional[str] = None

    note: Optional[str] = None

    environment: str
    subenvironment: str

    dependency: Optional[str] = None
    resource: Optional[str] = None
    approved: Optional[str] = None

    unplannedact: bool
    criticalact: bool
    deleted: bool

    events: List[EventResponse] = Field(
    	default_factory=list
    )

    model_config = ConfigDict(
        from_attributes=True
    )


class ActivityCreate(BaseModel):
    taskno: int
    est_time: datetime

    title: str
    details: str

    note: Optional[str] = None

    environment: str
    subenvironment: str = ""

    dependency: Optional[str] = None
    resource: Optional[str] = None

    username: str


# ============================================================
# PAGINATED ACTIVITY LIST
# ============================================================

class ActivityListResponse(BaseModel):
    items: List[ActivitySummary]

    limit: int
    offset: int
    returned: int
