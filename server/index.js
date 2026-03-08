const express = require("express");
const http = require("http");
const WebSocket = require("ws");
const path = require("path");

const PORT = process.env.PORT || 10000;
const LOBBY_COUNT = 5;
const MAX_CHAT_HISTORY = 50;

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// ── Lobby State ──────────────────────────────────────────────────────────────

function makeLobbies() {
  const map = {};
  for (let i = 1; i <= LOBBY_COUNT; i++) {
    const id = `lobby_${i}`;
    map[id] = {
      id,
      name: `Arena ${i}`,
      players: [],
      spectators: [],
      status: "empty",
      eventLog: [],
    };
  }
  return map;
}

const lobbies = makeLobbies();
const chatHistory = [];

function updateStatus(lobby) {
  if (lobby.players.length === 0) lobby.status = "empty";
  else if (lobby.players.length === 1) lobby.status = "waiting";
  else lobby.status = "playing";
}

function lobbySnapshot() {
  return Object.values(lobbies).map((l) => ({
    id: l.id,
    name: l.name,
    status: l.status,
    players: l.players.length,
    spectators: l.spectators.length,
    playerNames: l.players.map((p) => p.playerName),
  }));
}

function onlineCount() {
  return wss.clients.size;
}

// ── HTTP ──────────────────────────────────────────────────────────────────────

app.use((_req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
  res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");
  next();
});

app.get("/api/lobbies", (_req, res) => res.json(lobbySnapshot()));
app.get("/health", (_req, res) => res.json({ status: "ok", arenas: LOBBY_COUNT, online: onlineCount() }));

const webDir = path.join(__dirname, "..", "web");

app.get("/", (_req, res) => {
  res.sendFile(path.join(webDir, "lobby.html"));
});

app.use(express.static(webDir, { maxAge: "1h" }));

// ── WebSocket helpers ────────────────────────────────────────────────────────

function send(ws, msg) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(msg));
  }
}

function broadcast(lobby, msg, exclude = null) {
  for (const ws of [...lobby.players, ...lobby.spectators]) {
    if (ws !== exclude) send(ws, msg);
  }
}

function broadcastAll(msg, exclude = null) {
  for (const ws of wss.clients) {
    if (ws !== exclude && ws.readyState === WebSocket.OPEN) {
      send(ws, msg);
    }
  }
}

function systemChat(text) {
  const msg = { type: "chat", name: null, message: text, timestamp: Date.now(), system: true };
  chatHistory.push(msg);
  if (chatHistory.length > MAX_CHAT_HISTORY) chatHistory.shift();
  broadcastAll(msg);
}

// ── WebSocket connection ─────────────────────────────────────────────────────

wss.on("connection", (ws) => {
  ws.lobby = null;
  ws.role = null;
  ws.playerNum = 0;
  ws.playerName = "Anonymous";
  ws.isAlive = true;

  send(ws, { type: "lobby_list", lobbies: lobbySnapshot() });
  send(ws, { type: "chat_history", messages: chatHistory });
  broadcastAll({ type: "online_count", count: onlineCount() });

  ws.on("message", (data) => {
    try {
      handleMessage(ws, JSON.parse(data));
    } catch (e) {
      console.error("Parse error:", e.message);
    }
  });

  ws.on("close", () => {
    handleDisconnect(ws);
    broadcastAll({ type: "online_count", count: onlineCount() });
  });

  ws.on("error", (err) => console.error("WS error:", err.message));
  ws.on("pong", () => { ws.isAlive = true; });
});

// ── Message routing ──────────────────────────────────────────────────────────

function handleMessage(ws, msg) {
  switch (msg.type) {
    case "set_name": {
      const name = (msg.name || "").trim().slice(0, 20);
      if (name) ws.playerName = name;
      break;
    }
    case "chat":
      handleChat(ws, msg.message);
      break;
    case "join":
      handleJoin(ws, msg.lobby_id, msg.role);
      break;
    case "get_lobbies":
      send(ws, { type: "lobby_list", lobbies: lobbySnapshot() });
      break;
    case "spawn":
    case "special":
    case "age_advance":
    case "turret_action":
    case "game_over":
      handleGameEvent(ws, msg);
      break;
    default:
      console.warn("Unknown msg type:", msg.type);
  }
}

// ── Chat ─────────────────────────────────────────────────────────────────────

function handleChat(ws, message) {
  if (!message || typeof message !== "string") return;
  const chatMsg = {
    type: "chat",
    name: ws.playerName,
    message: message.trim().slice(0, 300),
    timestamp: Date.now(),
    system: false,
  };
  chatHistory.push(chatMsg);
  if (chatHistory.length > MAX_CHAT_HISTORY) chatHistory.shift();
  broadcastAll(chatMsg);
}

// ── Lobby join ───────────────────────────────────────────────────────────────

function handleJoin(ws, lobbyId, preferredRole) {
  const lobby = lobbies[lobbyId];
  if (!lobby) {
    send(ws, { type: "error", message: "Lobby not found." });
    return;
  }

  if (ws.lobby) removeFromLobby(ws);

  const forceSpectator = preferredRole === "spectator" || lobby.players.length >= 2;

  if (forceSpectator) {
    lobby.spectators.push(ws);
    ws.lobby = lobby;
    ws.role = "spectator";
    ws.playerNum = 0;

    send(ws, {
      type: "joined",
      role: "spectator",
      lobby_id: lobbyId,
      lobby_name: lobby.name,
      player_num: 0,
    });

    for (const evt of lobby.eventLog) send(ws, evt);
    systemChat(`${ws.playerName} is spectating ${lobby.name}`);
    console.log(`${lobby.name}: spectator joined (${lobby.spectators.length} watching)`);
  } else {
    const num = lobby.players.length + 1;
    lobby.players.push(ws);
    ws.lobby = lobby;
    ws.role = `player${num}`;
    ws.playerNum = num;

    updateStatus(lobby);
    send(ws, {
      type: "joined",
      role: ws.role,
      lobby_id: lobbyId,
      lobby_name: lobby.name,
      player_num: num,
    });

    systemChat(`${ws.playerName} joined ${lobby.name} (${lobby.players.length}/2)`);

    if (lobby.players.length === 2) {
      send(lobby.players[0], { type: "game_start", player_num: 1 });
      send(lobby.players[1], { type: "game_start", player_num: 2 });
      for (const s of lobby.spectators) {
        send(s, { type: "game_start", player_num: 0 });
      }
      systemChat(`Battle started in ${lobby.name}!`);
      console.log(`${lobby.name}: game started`);
    }
    updateStatus(lobby);
  }

  broadcastAll({ type: "lobby_list", lobbies: lobbySnapshot() });
}

// ── Game events ──────────────────────────────────────────────────────────────

function handleGameEvent(ws, msg) {
  if (!ws.lobby || ws.role === "spectator") return;

  const lobby = ws.lobby;
  const enriched = { ...msg, player_num: ws.playerNum };

  lobby.eventLog.push(enriched);
  if (lobby.eventLog.length > 50) lobby.eventLog.shift();

  broadcast(lobby, enriched, ws);
}

// ── Disconnect ───────────────────────────────────────────────────────────────

function handleDisconnect(ws) {
  if (!ws.lobby) return;
  removeFromLobby(ws);
}

function removeFromLobby(ws) {
  const lobby = ws.lobby;
  if (!lobby) return;

  if (ws.role === "spectator") {
    lobby.spectators = lobby.spectators.filter((s) => s !== ws);
    console.log(`${lobby.name}: spectator left`);
  } else {
    lobby.players = lobby.players.filter((p) => p !== ws);
    lobby.eventLog = [];
    updateStatus(lobby);
    broadcast(lobby, { type: "opponent_disconnected" });
    if (lobby.players.length === 1) {
      lobby.players[0].playerNum = 1;
      lobby.players[0].role = "player1";
    }
    systemChat(`${ws.playerName} left ${lobby.name}`);
    console.log(`${lobby.name}: player${ws.playerNum} disconnected → status: ${lobby.status}`);
  }

  ws.lobby = null;
  ws.role = null;
  ws.playerNum = 0;

  broadcastAll({ type: "lobby_list", lobbies: lobbySnapshot() });
}

// ── Keep-alive pings ─────────────────────────────────────────────────────────

const PING_INTERVAL_MS = 25_000;
const pingTimer = setInterval(() => {
  for (const ws of wss.clients) {
    if (ws.isAlive === false) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, PING_INTERVAL_MS);

wss.on("close", () => clearInterval(pingTimer));

// ── Start ────────────────────────────────────────────────────────────────────

server.listen(PORT, () => {
  console.log(`Age of War server on http://localhost:${PORT}`);
  console.log(`${LOBBY_COUNT} arenas ready | Lobbies: ${Object.keys(lobbies).join(", ")}`);
});
