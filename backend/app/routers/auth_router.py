"""Auth Router — Register, Login, Profile"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.database import get_session, User
from app.schemas.auth import (
    RegisterRequest, LoginRequest, TokenResponse, UserResponse
)
from app.services.auth import (
    create_user, get_user_by_username, get_user_by_email,
    verify_password, create_access_token, decode_access_token,
)
from app.services.quota import get_quota_usage

from fastapi import Header

router = APIRouter(prefix="/auth", tags=["Authentication"])


async def require_user(
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_session),
) -> User:
    """Extract and validate JWT from Authorization: Bearer <token>."""
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Invalid auth header")

    payload = decode_access_token(token)
    if payload is None:
        raise HTTPException(status_code=401, detail="Token expired or invalid")

    user_id = payload.get("sub")
    if user_id is None:
        raise HTTPException(status_code=401, detail="Invalid token payload")

    from app.services.auth import get_user_by_id
    user = await get_user_by_id(db, int(user_id))
    if user is None or not user.is_active:
        raise HTTPException(status_code=401, detail="User not found or inactive")

    return user


@router.post("/register", response_model=TokenResponse, status_code=201)
async def register(req: RegisterRequest, db: AsyncSession = Depends(get_session)):
    """Register a new user account."""
    # Check duplicates
    if await get_user_by_username(db, req.username):
        raise HTTPException(status_code=400, detail="Username already taken")
    if await get_user_by_email(db, req.email):
        raise HTTPException(status_code=400, detail="Email already registered")

    user = await create_user(db, req.username, req.email, req.password)
    token = create_access_token({"sub": str(user.id), "username": user.username})

    return TokenResponse(
        access_token=token,
        user_id=user.id,
        username=user.username,
    )


@router.post("/login", response_model=TokenResponse)
async def login(req: LoginRequest, db: AsyncSession = Depends(get_session)):
    """Login with username + password."""
    user = await get_user_by_username(db, req.username)
    if not user or not verify_password(req.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is disabled")

    token = create_access_token({"sub": str(user.id), "username": user.username})
    return TokenResponse(
        access_token=token,
        user_id=user.id,
        username=user.username,
    )


@router.get("/me", response_model=UserResponse)
async def get_profile(user: User = Depends(require_user)):
    """Get current user profile."""
    return UserResponse.model_validate(user)


@router.get("/quota")
async def get_quota(
    user: User = Depends(require_user),
    db: AsyncSession = Depends(get_session),
):
    """Get current quota usage for today."""
    return await get_quota_usage(db, user)