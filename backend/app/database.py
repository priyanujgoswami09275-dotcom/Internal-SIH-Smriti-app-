from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.pool import NullPool
from app.config import settings
from app.models.base import Base

# DateTime columns are timezone-naive. Pin the Postgres session to UTC so
# aware datetimes are stored as UTC wall-time (not the server's local zone);
# adaptive feature extraction treats naive values as UTC.
_connect_args = {}
if settings.DATABASE_URL.startswith("postgresql"):
    _connect_args = {"options": "-c timezone=UTC"}

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,
    poolclass=NullPool,
    future=True,
    connect_args=_connect_args,
)

async_session_maker = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

async def get_db() -> AsyncSession:
    """Dependency for FastAPI routes: provides async DB session."""
    async with async_session_maker() as session:
        try:
            yield session
        finally:
            await session.close()
