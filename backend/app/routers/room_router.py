"""Room Router — HTTP + WebSocket for synced playback"""

import uuid

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.services.room_manager import room_manager

router = APIRouter(prefix="/room", tags=["Room"])


def _generate_user_id() -> str:
    return str(uuid.uuid4())[:8]


@router.post("/create")
async def create_room():
    """Create a new room. Returns room code (must connect WS separately)."""
    # Room is actually created on WS connect, this just reserves a code preview
    code = room_manager._generate_code()
    return {"room_code": code, "user_id": _generate_user_id()}


@router.get("/{room_code}")
async def get_room_info(room_code: str):
    room = room_manager.get_room(room_code)
    if not room:
        return {"exists": False, "member_count": 0}
    return {
        "exists": True,
        "member_count": room.get_member_count(),
        "master_id": room.master_id,
    }


@router.websocket("/ws/{room_code}")
async def room_websocket(ws: WebSocket, room_code: str):
    """WebSocket endpoint for room sync.
    
    Query params:
    - user_id: unique user identifier
    - action: 'create' | 'join'
    """
    query = dict(ws.query_params)
    user_id = query.get("user_id") or _generate_user_id()
    action = query.get("action", "join")

    if action == "create":
        room = room_manager.create_room(ws, user_id)
        room_code = room.code
    else:
        room = room_manager.join_room(room_code, ws, user_id)
        if not room:
            await ws.accept()
            await ws.send_json({"type": "error", "message": "Room not found"})
            await ws.close()
            return

    await room_manager.handle_ws(ws, room_code, user_id)
