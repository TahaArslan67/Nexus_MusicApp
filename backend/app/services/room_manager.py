"""Room Manager — Synced Playback via WebSocket

In-memory room state. No DB needed for ephemeral sessions.
"""

import asyncio
import random
import string
from dataclasses import dataclass, field
from typing import Dict, List

from fastapi import WebSocket, WebSocketDisconnect


@dataclass
class RoomMember:
    ws: WebSocket
    user_id: str
    is_master: bool = False


@dataclass
class Room:
    code: str
    master_id: str
    members: Dict[str, RoomMember] = field(default_factory=dict)
    current_song: dict | None = None
    current_position_ms: int = 0
    is_playing: bool = False
    created_at: float = field(default_factory=lambda: asyncio.get_event_loop().time())

    async def broadcast(self, message: dict, exclude: str | None = None):
        """Broadcast JSON message to all members except excluded user."""
        dead = []
        for uid, member in self.members.items():
            if exclude and uid == exclude:
                continue
            try:
                await member.ws.send_json(message)
            except Exception:
                dead.append(uid)
        for uid in dead:
            self.members.pop(uid, None)

    def get_member_count(self) -> int:
        return len(self.members)


class RoomManager:
    def __init__(self):
        self._rooms: Dict[str, Room] = {}
        self._cleanup_task = None

    def _generate_code(self, length: int = 6) -> str:
        return "".join(random.choices(string.ascii_uppercase + string.digits, k=length))

    def create_room(self, master_ws: WebSocket, master_id: str) -> Room:
        code = self._generate_code()
        while code in self._rooms:
            code = self._generate_code()
        room = Room(code=code, master_id=master_id)
        room.members[master_id] = RoomMember(ws=master_ws, user_id=master_id, is_master=True)
        self._rooms[code] = room
        return room

    def get_room(self, code: str) -> Room | None:
        return self._rooms.get(code.upper())

    def join_room(self, code: str, ws: WebSocket, user_id: str) -> Room | None:
        room = self._rooms.get(code.upper())
        if not room:
            return None
        room.members[user_id] = RoomMember(ws=ws, user_id=user_id, is_master=False)
        return room

    def leave_room(self, code: str, user_id: str):
        room = self._rooms.get(code.upper())
        if not room:
            return
        room.members.pop(user_id, None)
        if room.get_member_count() == 0:
            self._rooms.pop(code.upper(), None)
        elif user_id == room.master_id and room.members:
            # Transfer master to oldest remaining member
            new_master = next(iter(room.members.values()))
            new_master.is_master = True
            room.master_id = new_master.user_id

    async def handle_ws(self, ws: WebSocket, room_code: str, user_id: str):
        await ws.accept()
        room = self._rooms.get(room_code.upper())
        if not room:
            await ws.send_json({"type": "error", "message": "Room not found"})
            await ws.close()
            return

        member = room.members.get(user_id)
        if not member:
            await ws.send_json({"type": "error", "message": "Not joined"})
            await ws.close()
            return

        # Send current state to new member
        await ws.send_json({
            "type": "sync",
            "room_code": room.code,
            "is_master": member.is_master,
            "current_song": room.current_song,
            "current_position_ms": room.current_position_ms,
            "is_playing": room.is_playing,
            "member_count": room.get_member_count(),
        })

        # Notify others
        await room.broadcast({
            "type": "member_joined",
            "user_id": user_id,
            "member_count": room.get_member_count(),
        }, exclude=user_id)

        try:
            while True:
                data = await ws.receive_json()
                msg_type = data.get("type")

                if msg_type == "play" and member.is_master:
                    room.is_playing = True
                    room.current_position_ms = data.get("position_ms", 0)
                    await room.broadcast({
                        "type": "play",
                        "position_ms": room.current_position_ms,
                    }, exclude=user_id)

                elif msg_type == "pause" and member.is_master:
                    room.is_playing = False
                    room.current_position_ms = data.get("position_ms", 0)
                    await room.broadcast({
                        "type": "pause",
                        "position_ms": room.current_position_ms,
                    }, exclude=user_id)

                elif msg_type == "seek" and member.is_master:
                    room.current_position_ms = data.get("position_ms", 0)
                    await room.broadcast({
                        "type": "seek",
                        "position_ms": room.current_position_ms,
                    }, exclude=user_id)

                elif msg_type == "song_change" and member.is_master:
                    room.current_song = data.get("song")
                    room.current_position_ms = 0
                    room.is_playing = True
                    await room.broadcast({
                        "type": "song_change",
                        "song": room.current_song,
                    }, exclude=user_id)

                elif msg_type == "ping":
                    await ws.send_json({"type": "pong"})

        except WebSocketDisconnect:
            pass
        finally:
            self.leave_room(room_code, user_id)
            await room.broadcast({
                "type": "member_left",
                "user_id": user_id,
                "member_count": room.get_member_count(),
            })


room_manager = RoomManager()
