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
API_TOKEN_FILE    = "/home/lucas/korespectre-api-token.txt"
MASTER_KEY_FILE   = "/home/lucas/korespectre-master-key.txt"
FCM_CREDS_FILE    = "/home/lucas/firebase-service-account.json"
FCM_TOKENS_FILE   = "/home/lucas/fcm-tokens.json"
MAINTENANCE_FILE      = "/home/lucas/korespectre-maintenance.json"
MAINTENANCE_MAP_FILE  = "/home/lucas/korespectre-maintenance-map.json"
# ─────────────────────────────────────────────────────────────────────────────

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("korespectre")


# ─── Token de API ─────────────────────────────────────────────────────────────

def _load_api_token() -> str:
    try:
        return open(API_TOKEN_FILE).read().strip()
    except Exception:
        token = secrets.token_hex(32)
        _save_api_token(token)
        log.info(f"Token de API gerado automaticamente: {token}")
        return token


def _save_api_token(token: str) -> None:
    with open(API_TOKEN_FILE, "w") as f:
        f.write(token)


def _load_master_key() -> str:
    try:
        return open(MASTER_KEY_FILE).read().strip()
    except Exception:
        key = secrets.token_hex(16)
        with open(MASTER_KEY_FILE, "w") as f:
            f.write(key)
        log.info(f"Master key gerada: {key}")
        return key


api_token  = _load_api_token()
master_key = _load_master_key()
log.info(f"Token de API ativo: {api_token[:8]}...{api_token[-8:]}")
log.info(f"Master key ativa:   {master_key[:4]}...")


def check_api_key(request) -> bool:
    return request.headers.get("X-Api-Key") == api_token


# ─── Helper Socket.IO com callback ────────────────────────────────────────────

_kuma_authenticated = False


async def sio_call(event: str, data, timeout: int = 15) -> dict:
    """Emite evento para o Kuma e aguarda callback (alternativa ao sio.call())."""
    if not sio.connected:
        raise Exception("Kuma não conectado")
    if not _kuma_authenticated:
        raise Exception("Kuma não autenticado — aguarde o login")

    loop = asyncio.get_running_loop()
    future: asyncio.Future = loop.create_future()

    def on_result(*args):
        result = args[0] if args else {}
        if not future.done():
            future.set_result(result)

    await sio.emit(event, data, callback=on_result)
    try:
        return await asyncio.wait_for(future, timeout=timeout)
    except asyncio.TimeoutError:
        raise Exception(f"Timeout ({timeout}s) aguardando resposta do Kuma para '{event}'")


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


# ─── Persistência de IDs em manutenção ────────────────────────────────────────

def _load_maintenance() -> set[int]:
    try:
        with open(MAINTENANCE_FILE) as f:
            data = json.load(f)
            return set(int(x) for x in data) if isinstance(data, list) else set()
    except Exception:
        return set()


def _save_maintenance(ids: set[int]) -> None:
    try:
        with open(MAINTENANCE_FILE, "w") as f:
            json.dump(list(ids), f, indent=2)
    except Exception as e:
        log.error(f"Erro ao salvar manutenção: {e}")


maintenance_ids: set[int] = _load_maintenance()
log.info(f"Monitores em manutenção: {len(maintenance_ids)}")


# ─── Mapa monitor_id → Kuma maintenance_id ────────────────────────────────────

def _load_maintenance_map() -> dict:
    try:
        with open(MAINTENANCE_MAP_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _save_maintenance_map(mmap: dict) -> None:
    try:
        with open(MAINTENANCE_MAP_FILE, "w") as f:
            json.dump(mmap, f, indent=2)
    except Exception as e:
        log.error(f"Erro ao salvar mapa de manutenção: {e}")


# chave = str(monitor_id), valor = kuma_maintenance_id (int)
maintenance_map: dict = _load_maintenance_map()


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


# ─── Estado ───────────────────────────────────────────────────────────────────
MAX_HISTORY       = 100
monitors          = {}
heartbeat_history = {}   # monitor_id -> list of {status, time, ping, msg}
last_event        = []
event_counter     = 0


# ─── Socket.IO ────────────────────────────────────────────────────────────────
sio = socketio.AsyncClient(reconnection=True, reconnection_delay=5)


@sio.event
async def connect():
    log.info("Conectado ao Uptime Kuma, autenticando...")
    await sio.emit("login",
                   {"username": KUMA_USERNAME, "password": KUMA_PASSWORD, "token": ""},
                   callback=on_login)


def on_login(data):
    global _kuma_authenticated
    if data.get("ok"):
        _kuma_authenticated = True
        log.info("Autenticado com sucesso no Kuma!")
    else:
        _kuma_authenticated = False
        log.error(f"Falha no login: {data.get('msg')}")


@sio.event
async def disconnect():
    global _kuma_authenticated
    _kuma_authenticated = False
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
    # Armazena histórico para tela de detalhe
    heartbeat_history[mid] = [
        {
            "status": _status_name(b.get("status")),
            "time":   b.get("time"),
            "ping":   b.get("ping"),
            "msg":    b.get("msg", ""),
        }
        for b in beats[-MAX_HISTORY:]
    ]


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

    # Append ao histórico independente de mudança de status
    if mid not in heartbeat_history:
        heartbeat_history[mid] = []
    heartbeat_history[mid].append({
        "status": new_status,
        "time":   data.get("time"),
        "ping":   data.get("ping"),
        "msg":    data.get("msg", ""),
    })
    if len(heartbeat_history[mid]) > MAX_HISTORY:
        heartbeat_history[mid] = heartbeat_history[mid][-MAX_HISTORY:]

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
        if len(last_event) > 100:
            last_event.pop()
        log.info(f"Status: {name} → {new_status}")

        if mid not in maintenance_ids:
            if new_status == "down":
                asyncio.create_task(send_fcm(f"{name} OFFLINE", "Monitor caiu — verifique seu datacenter"))
            elif new_status == "up":
                asyncio.create_task(send_fcm(f"{name} ONLINE", "Monitor recuperado com sucesso"))
        else:
            log.info(f"FCM suprimido — {name} está em manutenção")


def _status_name(code):
    return {1: "up", 0: "down", 2: "pending", 3: "maintenance"}.get(code, "unknown")


# ─── REST API ─────────────────────────────────────────────────────────────────

async def handle_health(request):
    """Verifica saúde da API. Aceita X-Api-Key ou sem autenticação."""
    return web.json_response({
        "ok":        True,
        "connected": sio.connected,
        "fcm":       fcm_enabled,
        "tokens":    len(fcm_tokens),
    })


async def handle_monitors(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
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
    try:
        since = int(request.rel_url.query.get("since", 0))
    except ValueError:
        since = 0
    events = [e for e in last_event if e.get("id", 0) > since]
    return web.json_response(events)


async def handle_register(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
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


# ─── Manutenção (integrada com Uptime Kuma) ───────────────────────────────────

async def handle_get_maintenance(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    return web.json_response(list(maintenance_ids))


async def handle_add_maintenance(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    try:
        monitor_id = int(request.match_info["monitor_id"])
    except (KeyError, ValueError):
        return web.Response(status=400, text="ID inválido")

    # Já pausado
    if monitor_id in maintenance_ids:
        return web.json_response({"ok": True, "id": monitor_id})

    monitor_name = monitors.get(monitor_id, {}).get("name", f"Monitor {monitor_id}")

    try:
        log.info(f"Pausando monitor {monitor_id} ({monitor_name}) no Kuma...")
        result = await sio_call("pauseMonitor", monitor_id)
        log.info(f"Resposta do Kuma (pauseMonitor): {result}")

        if not result or not result.get("ok"):
            log.error(f"Kuma rejeitou pausa: {result}")
            return web.Response(status=500, text=f"Kuma erro: {result}")

        maintenance_ids.add(monitor_id)
        _save_maintenance(maintenance_ids)
        if monitor_id in monitors:
            monitors[monitor_id]["active"] = False
        log.info(f"✓ Monitor {monitor_id} ({monitor_name}) pausado no Kuma")
        return web.json_response({"ok": True, "id": monitor_id})

    except Exception as e:
        log.error(f"✗ Erro ao pausar monitor {monitor_id}: {e}")
        return web.Response(status=500, text=str(e))


async def handle_remove_maintenance(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    try:
        monitor_id = int(request.match_info["monitor_id"])
    except (KeyError, ValueError):
        return web.Response(status=400, text="ID inválido")

    monitor_name = monitors.get(monitor_id, {}).get("name", f"Monitor {monitor_id}")
    try:
        log.info(f"Retomando monitor {monitor_id} ({monitor_name}) no Kuma...")
        result = await sio_call("resumeMonitor", monitor_id)
        log.info(f"Resposta do Kuma (resumeMonitor): {result}")
        if result and result.get("ok"):
            log.info(f"✓ Monitor {monitor_id} retomado no Kuma")
            if monitor_id in monitors:
                monitors[monitor_id]["active"] = True
        else:
            log.error(f"Kuma rejeitou retomada: {result}")
    except Exception as e:
        log.error(f"✗ Erro ao retomar monitor {monitor_id}: {e}")

    maintenance_ids.discard(monitor_id)
    _save_maintenance(maintenance_ids)
    return web.json_response({"ok": True, "id": monitor_id})


# ─── Detalhe de monitor ───────────────────────────────────────────────────────

async def handle_monitor_detail(request):
    if not check_api_key(request):
        return web.Response(status=401, text="Unauthorized")
    try:
        monitor_id = int(request.match_info["monitor_id"])
    except (KeyError, ValueError):
        return web.Response(status=400, text="ID inválido")

    monitor = monitors.get(monitor_id)
    if monitor is None:
        return web.Response(status=404, text="Monitor não encontrado")

    beats = heartbeat_history.get(monitor_id, [])

    pings = [b["ping"] for b in beats
             if b.get("ping") is not None
             and isinstance(b["ping"], (int, float))
             and b["ping"] > 0]
    avg_ping = round(sum(pings) / len(pings)) if pings else None

    uptime_pct = None
    if beats:
        up_count = sum(1 for b in beats if b["status"] == "up")
        uptime_pct = round(up_count / len(beats) * 100, 2)

    return web.json_response({
        "monitor":   monitor,
        "heartbeats": beats[-90:],
        "avgPing":   avg_ping,
        "uptimePct": uptime_pct,
        "paused":    monitor_id in maintenance_ids,
    })


# ─── Admin: gerenciamento de token ───────────────────────────────────────────

async def handle_get_token(request):
    """Retorna o token de API atual. Requer X-Master-Key."""
    if request.headers.get("X-Master-Key") != master_key:
        return web.Response(status=401, text="Unauthorized")
    return web.json_response({"ok": True, "token": api_token})


async def handle_regenerate_token(request):
    """Gera um novo token de API. Requer X-Master-Key."""
    if request.headers.get("X-Master-Key") != master_key:
        return web.Response(status=401, text="Unauthorized")
    global api_token
    api_token = secrets.token_hex(32)
    _save_api_token(api_token)
    log.info(f"Token de API regenerado: {api_token[:8]}...{api_token[-8:]}")
    return web.json_response({"ok": True, "token": api_token})


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

    app.router.add_get("/health",                    handle_health)
    app.router.add_get("/monitors",                  handle_monitors)
    app.router.add_get("/events",                    handle_events)
    app.router.add_post("/register",                 handle_register)
    app.router.add_post("/unregister",               handle_unregister)
    app.router.add_get("/maintenance",                 handle_get_maintenance)
    app.router.add_post("/maintenance/{monitor_id}",   handle_add_maintenance)
    app.router.add_delete("/maintenance/{monitor_id}", handle_remove_maintenance)
    app.router.add_get("/monitors/{monitor_id}",       handle_monitor_detail)
    app.router.add_get("/admin/token",               handle_get_token)
    app.router.add_post("/admin/token/regenerate",   handle_regenerate_token)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", API_PORT)
    await site.start()
    log.info(f"API rodando em http://0.0.0.0:{API_PORT}")
    log.info(f"FCM: {'ativado' if fcm_enabled else 'desativado'} | Tokens FCM: {len(fcm_tokens)}")

    await connect_loop()


if __name__ == "__main__":
    asyncio.run(main())
