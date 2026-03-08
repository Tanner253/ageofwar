const express = require("express");
const http = require("http");
const WebSocket = require("ws");
const path = require("path");

const PORT = process.env.PORT || 10000;
const LOBBY_COUNT = 5;

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
      players: [],    // max 2 WebSocket objects
      spectators: [], // unlimited
      status: "empty",
      eventLog: [],   // last 50 events replayed to new spectators
    };
  }
  return map;
}

const lobbies = makeLobbies();

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
  }));
}

// ── HTTP ──────────────────────────────────────────────────────────────────────

// Required headers for Godot WASM (SharedArrayBuffer)
app.use((_req, res, next) => {
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
  next();
});

app.get("/api/lobbies", (_req, res) => res.json(lobbySnapshot()));

const webDir = path.join(__dirname, "..", "web");

// Root serves the lobby selection page
app.get("/", (_req, res) => {
  res.sendFile(path.join(webDir, "lobby.html"));
});

// All other static files (Godot export, assets, etc.)
app.use(express.static(webDir));

// ── WebSocket ─────────────────────────────────────────────────────────────────

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

wss.on("connection", (ws) => {
  ws.lobby = null;
  ws.role = null;
  ws.playerNum = 0;

  // Send lobby list immediately on connect
  send(ws, { type: "lobby_list", lobbies: lobbySnapshot() });

  ws.on("message", (data) => {
    try {
      handleMessage(ws, JSON.parse(data));
    } catch (e) {
      console.error("Parse error:", e.message);
    }
  });

  ws.on("close", () => handleDisconnect(ws));
  ws.on("error", (err) => console.error("WS error:", err.message));
});

function handleMessage(ws, msg) {
  switch (msg.type) {
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

function handleJoin(ws, lobbyId, preferredRole) {
  const lobby = lobbies[lobbyId];
  if (!lobby) {
    send(ws, { type: "error", message: "Lobby not found." });
    return;
  }

  // Clean up if already in another lobby
  if (ws.lobby) removeFromLobby(ws);

  const forceSpectator =
    preferredRole === "spectator" || lobby.players.length >= 2;

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

    // Replay recent events so spectator has context
    for (const evt of lobby.eventLog) send(ws, evt);
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

    if (lobby.players.length === 2) {
      // Both players ready — start the game
      send(lobby.players[0], { type: "game_start", player_num: 1 });
      send(lobby.players[1], { type: "game_start", player_num: 2 });
      // Spectators receive game_start with player_num 0
      for (const s of lobby.spectators) {
        send(s, { type: "game_start", player_num: 0 });
      }
      console.log(`${lobby.name}: game started`);
    }
    updateStatus(lobby);
  }
}

function handleGameEvent(ws, msg) {
  if (!ws.lobby || ws.role === "spectator") return;

  const lobby = ws.lobby;
  // Enrich with player_num so spectators know who sent it
  const enriched = { ...msg, player_num: ws.playerNum };

  // Append to event log (keep last 50 for new spectators)
  lobby.eventLog.push(enriched);
  if (lobby.eventLog.length > 50) lobby.eventLog.shift();

  // Relay to everyone else (opponent + all spectators)
  broadcast(lobby, enriched, ws);
}

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
    lobby.eventLog = []; // reset log when a player leaves mid-game
    updateStatus(lobby);
    // Notify everyone remaining
    broadcast(lobby, { type: "opponent_disconnected" });
    // Re-number remaining player to player1
    if (lobby.players.length === 1) {
      lobby.players[0].playerNum = 1;
      lobby.players[0].role = "player1";
    }
    console.log(`${lobby.name}: player${ws.playerNum} disconnected → status: ${lobby.status}`);
  }

  ws.lobby = null;
  ws.role = null;
  ws.playerNum = 0;
}

// ── Start ─────────────────────────────────────────────────────────────────────

server.listen(PORT, () => {
  console.log(`Age of War server on http://localhost:${PORT}`);
  console.log(`5 arenas ready | Lobbies: ${Object.keys(lobbies).join(", ")}`);
});
