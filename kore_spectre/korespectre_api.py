#!/usr/bin/env python3
"""
KoreSpectre API Bridge
Conecta ao Uptime Kuma via Socket.IO e expõe REST API para o app Flutter.
Envia notificações push via FCM quando monitores mudam de status.

Dependências:
  pip3 install python-socketio[asyncio] aiohttp google-auth --break-system-packages

Arquivo de credenciais Firebase:
  /home/lucas/firebase-service-account.json
"""

import asyncio
import hashlib
import json
import logging
import os
import secrets
import time
from datetime import datetime

import aiohttp
from aiohttp import web
import socketio

# ─── Configuração ────────────────────────────────────────────────────────────
UPTIME_KUMA_URL  = "http://127.0.0.1:3001"
KUMA_USERNAME    = "KoreCloud"
KUMA_PASSWORD    = "Crss170900"
API_PORT         = 8765
API_KEY          = "korespectre2024"
FCM_CREDS_FILE   = "/home/lucas/firebase-service-account.json"
FCM_TOKENS_FILE  = "/home/lucas/fcm-tokens.json"
USERS_FILE       = "/home/lucas/korespectre-users.json"
SESSIONS_FILE    = "/home/lucas/korespectre-sessions.json"
SESSION_TTL      = 7 * 24 * 3600   # 7 dias
# ─────────────────────────────────────────────────────────────────────────────

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("korespectre")

# ─── Firebase FCM (HTTP v1 API) ───────────────────────────────────────────────
FCM_URL   = "https://fcm.googleapis.com/v1/projects/korespectre/messages:send"
FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

fcm_enabled = False
_fcm_creds  = None

if os.path.exists(FCM_CREDS_FILE):
    try:
        import google.oauth2.service_account as _sa
        _fcm_creds = _sa.Credentials.from_service_account_file(FCM_CREDS_FILE, scopes=[FCM_SCOPE])
        fcm_enabled = True
        log.info("FCM habilitado com sucesso")
    except Exception as _e:
        log.warning(f"FCM não disponível: {_e}")
else:
    log.warning(f"FCM desabilitado — arquivo não encontrado: {FCM_CREDS_FILE}")


# ─── Persistência de tokens FCM ───────────────────────────────────────────────
def _load_tokens() -> set[str]:
    try:
        with open(FCM_TOKENS_FILE) as f:
            data = json.load(f)
            return set(data) if isinstance(data, list) else set()
    except Exception:
        return set()


def _save_tokens(tokens: set[str]) -> None:
    try:
        with open(FCM_TOKENS_FILE, "w") as f:
            json.dump(list(tokens), f, indent=2)
    except Exception as e:
        log.error(f"Erro ao salvar tokens FCM: {e}")


fcm_tokens: set[str] = _load_tokens()
log.info(f"Tokens FCM carregados: {len(fcm_tokens)}")


def _refresh_fcm_token():
    import google.auth.transport.requests as _gtr
    _fcm_creds.refresh(_gtr.Request())
    return _fcm_creds.token


async def send_fcm(title: str, body: str) -> None:
    if not fcm_enabled or not fcm_tokens or not _fcm_creds:
        return
    loop = asyncio.get_event_loop()
    try:
        access_token = await loop.run_in_executor(None, _refresh_fcm_token)
    except Exception as e:
        log.error(f"Erro ao obter token OAuth FCM: {e}")
        return
    headers = {"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"}
    invalid: set[str] = set()
    for token in list(fcm_tokens):
        payload = {
            "message": {
                "notification": {"title": title, "body": body},
                "android": {
                    "priority": "high",
                    "notification": {"channel_id": "korespectre_alerts", "sound": "default"},
                },
                "token": token,
            }
        }
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(FCM_URL, json=payload, headers=headers) as resp:
                    if resp.status == 200:
                        log.info(f"FCM enviado: {title}")
                    else:
                        body_txt = await resp.text()
                        log.error(f"FCM erro {resp.status} ({token[-8:]}): {body_txt[:120]}")
                        if resp.status in (400, 404):
                            invalid.add(token)
        except Exception as e:
            log.error(f"Erro FCM ({token[-8:]}): {e}")
    if invalid:
        fcm_tokens.difference_update(invalid)
        _save_tokens(fcm_tokens)
        log.info(f"Tokens inválidos removidos: {len(invalid)}")


# ─── Autenticação de usuários ─────────────────────────────────────────────────
def _load_users() -> dict:
    try:
        with open(USERS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _save_users(u: dict) -> None:
    with open(USERS_FILE, "w") as f:
        json.dump(u, f, indent=2)


def _load_sessions() -> dict:
    try:
        with open(SESSIONS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _save_sessions(s: dict) -> None:
    with open(SESSIONS_FILE, "w") as f:
        json.dump(s, f, indent=2)


def _hash_password(password: str, salt: str) -> str:
    return hashlib.sha256(f"{salt}{password}".encode()).hexdigest()


def _clean_expired_sessions(s: dict) -> dict:
    now = time.time()
    return {k: v for k, v in s.items() if v.get("expires", 0) > now}


users: dict    = _load_users()
sessions: dict = _clean_expired_sessions(_load_sessions())
log.info(f"Usuários cadastrados: {len(users)} | Sessões ativas: {len(sessions)}")


# ─── Estado ───────────────────────────────────────────────────────────────────
monitors      = {}
last_event    = []
event_counter = 0


# ─── Socket.IO ────────────────────────────────────────────────────────────────
sio = socketio.AsyncClient(reconnection=True, reconnection_delay=5)


@sio.event
async def connect():
    log.info("Conectado ao Uptime Kuma, autenticando...")
    await sio.emit("login",
                   {"username": KUMA_USERNAME, "password": KUMA_PASSWORD, "token": ""},
                   callback=on_login)


def on_login(data):
    if data.get("ok"):
        log.info("Autenticado com sucesso!")
    else:
        log.error(f"Falha no login: {data.get('msg')}")


@sio.event
async def disconnect():
    log.warning("Desconectado do Uptime Kuma")


@sio.on("monitorList")
async def on_monitor_list(data):
    src = data.get("monitors", data) if isinstance(data, dict) else data
    if isinstance(src, dict):
        for mid, m in src.items():
            mid_int = int(mid)
            existing = monitors.get(mid_int)
            monitors[mid_int] = {
                "id":        mid_int,
                "name":      m.get("name", f"Monitor {mid}"),
                "url":       m.get("url"),
                "type":      m.get("type", "unknown"),
                "active":    m.get("active", True),
                "status":    existing["status"] if existing else "unknown",
                "ping":      existing["ping"] if existing else None,
                "lastCheck": existing["lastCheck"] if existing else None,
            }
        log.info(f"{len(monitors)} monitors carregados")


@sio.on("heartbeatList")
async def on_heartbeat_list(monitor_id, beats, *args):
    if not beats:
        return
    last = beats[-1]
    mid = int(monitor_id)
    if mid in monitors:
        monitors[mid].update({
            "status":    _status_name(last.get("status")),
            "ping":      last.get("ping"),
            "lastCheck": last.get("time"),
        })


@sio.on("heartbeat")
async def on_heartbeat(data):
    global event_counter
    mid        = int(data.get("monitorID", 0))
    new_status = _status_name(data.get("status"))
    old_status = monitors.get(mid, {}).get("status", "unknown")

    if mid in monitors:
        monitors[mid].update({
            "status":    new_status,
            "ping":      data.get("ping"),
            "lastCheck": data.get("time"),
        })

    if old_status != "unknown" and old_status != new_status:
        name = monitors.get(mid, {}).get("name", f"Monitor {mid}")
        event_counter += 1
        event = {
            "id":        event_counter,
            "monitorId": mid,
            "name":      name,
            "status":    new_status,
            "oldStatus": old_status,
            "time":      datetime.utcnow().isoformat(),
        }
        last_event.insert(0, event)
        if len(last_event) > 50:
            last_event.pop()
        log.info(f"Status: {name} → {new_status}")

        if new_status == "down":
            asyncio.create_task(send_fcm(f"{name} OFFLINE", "Monitor caiu — verifique seu datacenter"))
        elif new_status == "up":
            asyncio.create_task(send_fcm(f"{name} ONLINE", "Monitor recuperado com sucesso"))


def _status_name(code):
    return {1: "up", 0: "down", 2: "pending", 3: "maintenance"}.get(code, "unknown")


# ─── REST API — helpers ───────────────────────────────────────────────────────

def check_api_key(request) -> bool:
    return request.headers.get("X-Api-Key") == API_KEY


def get_session_email(request) -> str | None:
    """Valida o X-Session-Token e retorna o email do usuário, ou None se inválido."""
    token = request.headers.get("X-Session-Token", "")
    session = sessions.get(token)
    if not session or session.get("expires", 0) < time.time():
        return None
    return session.get("email")


# ─── REST API — autenticação de usuários ──────────────────────────────────────

async def handle_login(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    try:
        data     = await request.json()
        email    = (data.get("email") or "").strip().lower()
        password = data.get("password") or ""
    except Exception:
        return web.json_response({"ok": False, "error": "Payload inválido"}, status=400)

    user = users.get(email)
    if not user or _hash_password(password, user.get("salt", "")) != user.get("password_hash", ""):
        return web.json_response({"ok": False, "error": "Credenciais inválidas"}, status=401)

    token = secrets.token_hex(32)
    sessions[token] = {"email": email, "expires": time.time() + SESSION_TTL}

    # limpa sessões expiradas
    expired = [k for k, v in list(sessions.items()) if v.get("expires", 0) < time.time()]
    for k in expired:
        del sessions[k]
    _save_sessions(sessions)

    log.info(f"Login: {email}")
    return web.json_response({"ok": True, "token": token, "email": email})


async def handle_validate(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    email = get_session_email(request)
    if not email:
        return web.json_response({"ok": False, "error": "Sessão inválida ou expirada"}, status=401)
    return web.json_response({"ok": True, "email": email})


async def handle_auth_logout(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    token = request.headers.get("X-Session-Token", "")
    if token in sessions:
        email = sessions[token].get("email", "?")
        del sessions[token]
        _save_sessions(sessions)
        log.info(f"Logout: {email}")
    return web.json_response({"ok": True})


# ─── REST API — admin de usuários (requer API key) ────────────────────────────

async def handle_admin_list_users(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    return web.json_response({"users": [{"email": e} for e in sorted(users.keys())]})


async def handle_admin_add_user(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    try:
        data     = await request.json()
        email    = (data.get("email") or "").strip().lower()
        password = data.get("password") or ""
        if not email or not password:
            return web.json_response({"ok": False, "error": "email e password obrigatórios"}, status=400)
        salt = secrets.token_hex(16)
        users[email] = {"email": email, "salt": salt, "password_hash": _hash_password(password, salt)}
        _save_users(users)
        log.info(f"Usuário criado/atualizado: {email}")
        return web.json_response({"ok": True, "email": email})
    except Exception as e:
        return web.Response(status=400, text=str(e))


async def handle_admin_remove_user(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    try:
        data  = await request.json()
        email = (data.get("email") or "").strip().lower()
        if email in users:
            del users[email]
            _save_users(users)
            # invalida sessões desse usuário
            to_remove = [k for k, v in sessions.items() if v.get("email") == email]
            for k in to_remove:
                del sessions[k]
            if to_remove:
                _save_sessions(sessions)
            log.info(f"Usuário removido: {email}")
        return web.json_response({"ok": True})
    except Exception as e:
        return web.Response(status=400, text=str(e))


# ─── REST API — monitores ─────────────────────────────────────────────────────

async def handle_health(request):
    return web.json_response({
        "ok":        True,
        "connected": sio.connected,
        "fcm":       fcm_enabled,
        "tokens":    len(fcm_tokens),
    })


async def handle_monitors(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    if not get_session_email(request):
        return web.json_response({"ok": False, "error": "Sessão inválida"}, status=401)
    return web.json_response({
        "connected": sio.connected,
        "monitors":  list(monitors.values()),
        "total":     len(monitors),
        "up":        sum(1 for m in monitors.values() if m["status"] == "up"),
        "down":      sum(1 for m in monitors.values() if m["status"] == "down"),
    })


async def handle_events(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    if not get_session_email(request):
        return web.json_response({"ok": False, "error": "Sessão inválida"}, status=401)
    try:
        since = int(request.rel_url.query.get("since", 0))
    except ValueError:
        since = 0
    events = [e for e in last_event if e.get("id", 0) > since]
    return web.json_response(events)


async def handle_register(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    if not get_session_email(request):
        return web.json_response({"ok": False, "error": "Sessão inválida"}, status=401)
    try:
        data  = await request.json()
        token = (data.get("token") or "").strip()
        if not token:
            return web.json_response({"ok": False, "error": "token ausente"}, status=400)
        if token not in fcm_tokens:
            fcm_tokens.add(token)
            _save_tokens(fcm_tokens)
            log.info(f"FCM token registrado: ...{token[-12:]} (total: {len(fcm_tokens)})")
        return web.json_response({"ok": True, "fcm_enabled": fcm_enabled})
    except Exception as e:
        return web.Response(status=400, text=str(e))


async def handle_unregister(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    try:
        data  = await request.json()
        token = (data.get("token") or "").strip()
        if token and token in fcm_tokens:
            fcm_tokens.discard(token)
            _save_tokens(fcm_tokens)
            log.info(f"FCM token removido: ...{token[-12:]}")
        return web.json_response({"ok": True})
    except Exception as e:
        return web.Response(status=400, text=str(e))


# ─── Inicialização ────────────────────────────────────────────────────────────

async def connect_loop():
    while True:
        try:
            if not sio.connected:
                log.info(f"Conectando ao Uptime Kuma em {UPTIME_KUMA_URL}...")
                await sio.connect(UPTIME_KUMA_URL, transports=["polling", "websocket"])
                await sio.wait()
        except Exception as e:
            log.error(f"Erro na conexão: {e}")
        await asyncio.sleep(10)


async def main():
    app = web.Application()

    # auth de usuário
    app.router.add_post("/login",               handle_login)
    app.router.add_get("/auth/validate",        handle_validate)
    app.router.add_post("/auth/logout",         handle_auth_logout)

    # admin de usuários
    app.router.add_get("/admin/users",          handle_admin_list_users)
    app.router.add_post("/admin/users",         handle_admin_add_user)
    app.router.add_delete("/admin/users",       handle_admin_remove_user)

    # monitores
    app.router.add_get("/health",               handle_health)
    app.router.add_get("/monitors",             handle_monitors)
    app.router.add_get("/events",               handle_events)
    app.router.add_post("/register",            handle_register)
    app.router.add_post("/unregister",          handle_unregister)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", API_PORT)
    await site.start()
    log.info(f"API rodando em http://0.0.0.0:{API_PORT}")
    log.info(f"FCM: {'ativado' if fcm_enabled else 'desativado'} | Tokens: {len(fcm_tokens)}")

    await connect_loop()


if __name__ == "__main__":
    asyncio.run(main())
