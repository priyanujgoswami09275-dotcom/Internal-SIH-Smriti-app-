"""Auth routes — register, login, refresh, logout, me."""
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from app.database import get_db
from app.deps import _parse_sub
from app.models.user import RoleEnum, User
from app.schemas import RegisterRequest, LoginRequest, TokenResponse, UserOut
from app.services.auth_service import AuthService
from app.deps import get_current_user

router = APIRouter(prefix="/auth", tags=["auth"])


class RefreshRequest(BaseModel):
    refresh_token: str


def is_public_registration_role(role: str | None) -> bool:
    return role in (RoleEnum.PATIENT, RoleEnum.FAMILY_CAREGIVER)


@router.post("/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def register(body: RegisterRequest, db: AsyncSession = Depends(get_db)):
    if not is_public_registration_role(body.role):
        raise HTTPException(status_code=403, detail="Role is not available for public registration")
    existing = await db.execute(select(User).where(User.phone == body.phone))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Phone already registered")
    user = User(
        phone=body.phone,
        email=body.email,
        password_hash=AuthService.hash_password(body.password),
        role=body.role,
        preferred_language=body.preferred_language,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.phone == body.phone))
    user = result.scalar_one_or_none()
    if not user or not AuthService.verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")
    refresh, jti = AuthService.create_refresh_token({"sub": str(user.id)})
    user.refresh_jti = jti  # any previous token dies on this login
    await db.commit()
    return TokenResponse(
        access_token=AuthService.create_access_token({"sub": str(user.id), "role": user.role.value}),
        refresh_token=refresh,
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    """Single-use rotation: only the current jti is accepted; a new pair
    revokes the presented token."""
    payload = AuthService.verify_token(body.refresh_token)
    if payload is None or payload.get("typ") != "refresh" or not payload.get("sub"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired refresh token")

    result = await db.execute(select(User).where(User.id == _parse_sub(payload["sub"])))
    user = result.scalar_one_or_none()
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")
    if user.refresh_jti is None or payload.get("jti") != user.refresh_jti:
        # Reused or superseded token: revoke the whole chain.
        user.refresh_jti = None
        await db.commit()
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token already used or revoked")

    refresh, jti = AuthService.create_refresh_token({"sub": str(user.id)})
    claim = await db.execute(
        update(User)
        .where(
            User.id == user.id,
            User.refresh_jti == payload["jti"],
            User.is_active.is_(True),
        )
        .values(refresh_jti=jti)
    )
    if claim.rowcount != 1:
        user.refresh_jti = None
        await db.commit()
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token already used or revoked")
    await db.commit()
    return TokenResponse(
        access_token=AuthService.create_access_token({"sub": str(user.id), "role": user.role.value}),
        refresh_token=refresh,
    )


@router.post("/logout")
async def logout(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Revoke the current refresh token (JWT access stays stateless)."""
    current_user.refresh_jti = None
    await db.commit()
    return {"status": "logged_out"}


@router.get("/me", response_model=UserOut)
async def me(current_user: User = Depends(get_current_user)):
    return current_user
