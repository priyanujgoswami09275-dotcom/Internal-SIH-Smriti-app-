import asyncio
import uuid

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.database import Base, get_db
from app.main import app
from app.models.user import User
from app.services.auth_service import AuthService

AUTH = "/api/v1/auth"
PASSWORD = "TestPass123"


async def _register_and_login(client):
    phone = f"+91{uuid.uuid4().int % 10**9:09d}"
    registered = await client.post(
        f"{AUTH}/register",
        json={
            "phone": phone,
            "password": PASSWORD,
            "role": "patient",
            "preferred_language": "english",
        },
    )
    assert registered.status_code == 201, registered.text
    logged_in = await client.post(
        f"{AUTH}/login",
        json={"phone": phone, "password": PASSWORD},
    )
    assert logged_in.status_code == 200, logged_in.text
    return logged_in.json()


@pytest.mark.asyncio
async def test_refresh_token_is_rejected_as_access_token(client):
    tokens = await _register_and_login(client)

    response = await client.get(
        f"{AUTH}/me",
        headers={"Authorization": f"Bearer {tokens['refresh_token']}"},
    )

    assert response.status_code == 401


@pytest.mark.asyncio
async def test_access_token_is_rejected_by_refresh(client):
    tokens = await _register_and_login(client)

    response = await client.post(
        f"{AUTH}/refresh",
        json={"refresh_token": tokens["access_token"]},
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid or expired refresh token"


@pytest.mark.asyncio
async def test_concurrent_refresh_rotation_has_one_winner():
    database_name = f"file:refresh_rotation_{uuid.uuid4().hex}?mode=memory&cache=shared&uri=true"
    engine = create_async_engine(
        f"sqlite+aiosqlite:///{database_name}",
        poolclass=NullPool,
    )
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    both_requests_ready = asyncio.Event()
    rotation_write_lock = asyncio.Lock()
    ready_count = 0
    ready_lock = asyncio.Lock()
    coordinate_refreshes = False
    original_get_db = app.dependency_overrides.get(get_db)

    async def concurrent_get_db():
        session = session_factory()
        execute = session.execute
        commit = session.commit
        owns_rotation_write_lock = False

        async def synchronized_execute(statement, *args, **kwargs):
            nonlocal owns_rotation_write_lock, ready_count
            result = await execute(statement, *args, **kwargs)
            if coordinate_refreshes and any(
                item.get("entity") is User
                for item in getattr(statement, "column_descriptions", [])
            ):
                await commit()
                async with ready_lock:
                    ready_count += 1
                    if ready_count == 2:
                        both_requests_ready.set()
                await asyncio.wait_for(both_requests_ready.wait(), timeout=1)
                await rotation_write_lock.acquire()
                owns_rotation_write_lock = True
            return result

        async def synchronized_commit():
            nonlocal owns_rotation_write_lock
            try:
                return await commit()
            finally:
                if owns_rotation_write_lock:
                    owns_rotation_write_lock = False
                    rotation_write_lock.release()

        session.execute = synchronized_execute
        session.commit = synchronized_commit
        try:
            yield session
        finally:
            if owns_rotation_write_lock:
                rotation_write_lock.release()
            await session.close()

    try:
        async with engine.connect() as anchor:
            await anchor.run_sync(Base.metadata.create_all)
            await anchor.commit()
            app.dependency_overrides[get_db] = concurrent_get_db
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                tokens = await _register_and_login(client)
                body = {"refresh_token": tokens["refresh_token"]}
                coordinate_refreshes = True
                responses = await asyncio.wait_for(
                    asyncio.gather(
                        client.post(f"{AUTH}/refresh", json=body),
                        client.post(f"{AUTH}/refresh", json=body),
                    ),
                    timeout=5,
                )
                async with session_factory() as session:
                    stored_user = await session.get(
                        User,
                        uuid.UUID(AuthService.verify_token(tokens["refresh_token"])["sub"]),
                    )
                    assert stored_user.refresh_jti is None
    finally:
        if original_get_db is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = original_get_db
        await engine.dispose()

    assert sorted(response.status_code for response in responses) == [200, 401]
    rejected = next(response for response in responses if response.status_code == 401)
    assert rejected.json()["detail"] == "Refresh token already used or revoked"
    successful = next(response for response in responses if response.status_code == 200)
    issued_jtis = [
        AuthService.verify_token(response.json()["refresh_token"])["jti"]
        for response in responses
        if response.status_code == 200
    ]
    assert len(issued_jtis) == len(set(issued_jtis)) == 1
    assert issued_jtis[0] != AuthService.verify_token(tokens["refresh_token"])["jti"]
    assert AuthService.verify_token(successful.json()["access_token"])["typ"] == "access"
