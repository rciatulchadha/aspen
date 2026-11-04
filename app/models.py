from datetime import date, datetime
from typing import List, Optional

from sqlalchemy import (
    Boolean,
    Date,
    ForeignKey,
    Integer,
    SmallInteger,
    String,
    Text,
)
from sqlalchemy.orm import (
    Mapped,
    mapped_column,
    relationship,
)

from app.database import Base


# ============================================================
# ACTIVITIES
# ============================================================

class Activity(Base):
    __tablename__ = "activities"

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
    )

    taskno: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
    )

    est_time: Mapped[datetime] = mapped_column(
        nullable=False,
    )

    title: Mapped[str] = mapped_column(
        String(500),
        nullable=False,
    )

    details: Mapped[str] = mapped_column(
        Text,
        nullable=False,
    )

    status: Mapped[str] = mapped_column(
    String(15),
    nullable=False,
    default="None",
    server_default="None",
    )
    closed: Mapped[Optional[str]] = mapped_column(
        String(3),
        nullable=True,
    )

    note: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
    )

    environment: Mapped[str] = mapped_column(
        String(10),
        nullable=False,
    )

    subenvironment: Mapped[str] = mapped_column(
        String(25),
        nullable=False,
    )

    dependency: Mapped[Optional[str]] = mapped_column(
        String(50),
        nullable=True,
    )

    resource: Mapped[Optional[str]] = mapped_column(
        String(50),
        nullable=True,
    )

    approved: Mapped[Optional[str]] = mapped_column(
        String(50),
        nullable=True,
    )

    unplannedact: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
    )

    criticalact: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
    )

    deleted: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
    )

    events: Mapped[List["Event"]] = relationship(
        "Event",
        back_populates="activity",
        order_by="Event.time_started",
    )


# ============================================================
# EVENTS
# ============================================================

class Event(Base):
    __tablename__ = "events"

    serial: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
    )

    # Legacy VSR:
    # events.id -> activities.id
    id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("activities.id"),
        nullable=False,
    )

    time_updated: Mapped[datetime] = mapped_column(
        nullable=False,
    )

    time_started: Mapped[datetime] = mapped_column(
        nullable=False,
    )

    systimeentered: Mapped[datetime] = mapped_column(
        nullable=False,
    )

    details: Mapped[str] = mapped_column(
        Text,
        nullable=False,
    )

    operator: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
    )

    activity: Mapped["Activity"] = relationship(
        "Activity",
        back_populates="events",
    )


# ============================================================
# DAILY TASKS
# ============================================================

class DailyTask(Base):
    __tablename__ = "dailytasks"

    serial: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
    )

    taskno: Mapped[int] = mapped_column(
        SmallInteger,
        nullable=False,
    )

    title: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )

    details: Mapped[str] = mapped_column(
        Text,
        nullable=False,
    )

    note: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
    )

    dependency: Mapped[Optional[str]] = mapped_column(
        String(100),
        nullable=True,
    )

    environment: Mapped[str] = mapped_column(
        String(10),
        nullable=False,
    )

    subenvironment: Mapped[str] = mapped_column(
        String(25),
        nullable=False,
    )

    resource: Mapped[Optional[str]] = mapped_column(
        String(20),
        nullable=True,
    )

    time: Mapped[str] = mapped_column(
        "time",
        String(5),
        nullable=False,
    )

    criticalact: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
    )

    deleted: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
    )

    # --------------------------------------------------------
    # Scheduling validity window
    #
    # First date this Daily Task can generate an Activity.
    # --------------------------------------------------------

    effective_from: Mapped[date] = mapped_column(
        Date,
        nullable=False,
    )

    # --------------------------------------------------------
    # Last date this Daily Task can generate an Activity.
    #
    # NULL means the task remains active indefinitely.
    # --------------------------------------------------------

    effective_to: Mapped[Optional[date]] = mapped_column(
        Date,
        nullable=True,
    )
