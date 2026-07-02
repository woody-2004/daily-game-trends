const express = require('express');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server);

app.use(express.static(path.join(__dirname, 'public')));
app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'public', 'player.html')));
app.get('/host', (req, res) => res.sendFile(path.join(__dirname, 'public', 'host.html')));

const ROUND_SECONDS = 90;
const TICK_MS = 250;
const DECAY_PER_SEC = 6;        // station health lost per second
const TAP_BOOST = 7;            // health gained per tap
const SABOTAGE_DAMAGE = 35;
const SABOTAGE_CHARGES = 3;
const SABOTAGE_COOLDOWN_MS = 12000;
const REBOOT_MS = 4000;         // downtime after a station breaks
const REBOOT_HEALTH = 60;
const WRONG_ACCUSE_DAMAGE = 25;
const GROUP_WIN_MAX_BREAKS = 3; // group survives if total breaks <= this

const rooms = new Map(); // code -> room

function makeCode() {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  let code;
  do {
    code = Array.from({ length: 4 }, () => letters[Math.floor(Math.random() * letters.length)]).join('');
  } while (rooms.has(code));
  return code;
}

function publicState(room) {
  return {
    code: room.code,
    state: room.state,
    timeLeft: room.timeLeft,
    totalBreaks: room.totalBreaks,
    maxBreaks: GROUP_WIN_MAX_BREAKS,
    players: [...room.players.values()].map(p => ({
      id: p.id,
      name: p.name,
      station: Math.round(p.station),
      broken: p.brokenUntil > Date.now(),
      exposed: p.exposed,
      connected: p.connected,
    })),
  };
}

function privateState(room, p) {
  const target = room.players.get(p.targetId);
  return {
    targetName: target ? target.name : null,
    charges: p.charges,
    cooldownMsLeft: Math.max(0, p.cooldownUntil - Date.now()),
    accusationUsed: p.accusationUsed,
    exposed: p.exposed,
    personalWin: p.personalWin,
  };
}

function broadcast(room) {
  io.to(room.code).emit('state', publicState(room));
}

function feed(room, text) {
  io.to(room.code).emit('feed', { text, t: Date.now() });
}

function sendPrivate(room, p) {
  io.to(p.id).emit('private', privateState(room, p));
}

function startGame(room) {
  const players = [...room.players.values()].filter(p => p.connected);
  if (players.length < 3) return;

  // Single random cycle: everyone targets someone, everyone is targeted by exactly one.
  const shuffled = [...players].sort(() => Math.random() - 0.5);
  shuffled.forEach((p, i) => { p.targetId = shuffled[(i + 1) % shuffled.length].id; });

  for (const p of room.players.values()) {
    p.station = 100;
    p.brokenUntil = 0;
    p.breakCount = 0;
    p.charges = SABOTAGE_CHARGES;
    p.cooldownUntil = 0;
    p.accusationUsed = false;
    p.exposed = false;
    p.personalWin = false;
  }

  room.state = 'playing';
  room.timeLeft = ROUND_SECONDS;
  room.totalBreaks = 0;
  feed(room, 'The machine is live. Keep your station green… and watch your friends. 👀');
  for (const p of room.players.values()) sendPrivate(room, p);

  room.interval = setInterval(() => tick(room), TICK_MS);
}

function tick(room) {
  const dt = TICK_MS / 1000;
  room.timeLeft = Math.max(0, room.timeLeft - dt);
  const now = Date.now();

  for (const p of room.players.values()) {
    if (p.brokenUntil > now) continue; // rebooting
    if (p.brokenUntil !== 0 && p.brokenUntil <= now) {
      p.brokenUntil = 0;
      p.station = REBOOT_HEALTH;
      feed(room, `🔧 ${p.name}'s station rebooted.`);
    }
    p.station -= DECAY_PER_SEC * dt;
    if (p.station <= 0) breakStation(room, p, 'wore down');
  }

  if (room.timeLeft <= 0) return endGame(room);
  broadcast(room);
}

function breakStation(room, p, cause) {
  p.station = 0;
  p.brokenUntil = Date.now() + REBOOT_MS;
  p.breakCount++;
  room.totalBreaks++;
  feed(room, `💥 ${p.name}'s station BROKE (${cause})!`);

  // Anyone whose target just broke completes their secret objective.
  for (const q of room.players.values()) {
    if (q.targetId === p.id && !q.personalWin) {
      q.personalWin = true;
      sendPrivate(room, q);
      io.to(q.id).emit('toast', '🎯 Your target broke. Secret objective complete!');
    }
  }
}

function endGame(room) {
  clearInterval(room.interval);
  room.interval = null;
  room.state = 'reveal';

  const players = [...room.players.values()];
  const groupWin = room.totalBreaks <= GROUP_WIN_MAX_BREAKS;
  const reveal = {
    groupWin,
    totalBreaks: room.totalBreaks,
    maxBreaks: GROUP_WIN_MAX_BREAKS,
    edges: players
      .filter(p => p.targetId)
      .map(p => ({
        from: p.name,
        to: room.players.get(p.targetId)?.name ?? '?',
        succeeded: p.personalWin,
        exposed: p.exposed,
      })),
  };
  io.to(room.code).emit('reveal', reveal);
  broadcast(room);
}

io.on('connection', (socket) => {
  socket.on('createRoom', (cb) => {
    const code = makeCode();
    const room = {
      code,
      hostId: socket.id,
      state: 'lobby',
      players: new Map(),
      timeLeft: ROUND_SECONDS,
      totalBreaks: 0,
      interval: null,
    };
    rooms.set(code, room);
    socket.join(code);
    socket.data.roomCode = code;
    socket.data.isHost = true;
    cb({ code });
    broadcast(room);
  });

  socket.on('join', ({ code, name }, cb) => {
    code = String(code || '').trim().toUpperCase();
    name = String(name || '').trim().slice(0, 14);
    const room = rooms.get(code);
    if (!room) return cb({ error: 'Room not found.' });
    if (room.state !== 'lobby') return cb({ error: 'Game already in progress.' });
    if (!name) return cb({ error: 'Pick a name.' });
    if ([...room.players.values()].some(p => p.name.toLowerCase() === name.toLowerCase()))
      return cb({ error: 'Name taken.' });
    if (room.players.size >= 8) return cb({ error: 'Room is full (8 max).' });

    room.players.set(socket.id, {
      id: socket.id, name, connected: true,
      station: 100, brokenUntil: 0, breakCount: 0,
      targetId: null, charges: 0, cooldownUntil: 0,
      accusationUsed: false, exposed: false, personalWin: false,
    });
    socket.join(code);
    socket.data.roomCode = code;
    cb({ ok: true, code, name });
    feed(room, `${name} joined.`);
    broadcast(room);
  });

  socket.on('startGame', () => {
    const room = rooms.get(socket.data.roomCode);
    if (room && socket.id === room.hostId && room.state === 'lobby') startGame(room);
  });

  socket.on('playAgain', () => {
    const room = rooms.get(socket.data.roomCode);
    if (room && socket.id === room.hostId && room.state === 'reveal') {
      room.state = 'lobby';
      broadcast(room);
    }
  });

  socket.on('tap', () => {
    const room = rooms.get(socket.data.roomCode);
    const p = room?.players.get(socket.id);
    if (!room || !p || room.state !== 'playing') return;
    if (p.brokenUntil > Date.now()) return;
    p.station = Math.min(100, p.station + TAP_BOOST);
  });

  socket.on('sabotage', () => {
    const room = rooms.get(socket.data.roomCode);
    const p = room?.players.get(socket.id);
    if (!room || !p || room.state !== 'playing') return;
    if (p.exposed || p.charges <= 0 || p.cooldownUntil > Date.now()) return;
    const target = room.players.get(p.targetId);
    if (!target || target.brokenUntil > Date.now()) return;

    p.charges--;
    p.cooldownUntil = Date.now() + SABOTAGE_COOLDOWN_MS;
    target.station -= SABOTAGE_DAMAGE;
    feed(room, `⚡ A power surge hit ${target.name}'s station!`);
    if (target.station <= 0) breakStation(room, target, 'power surge');
    sendPrivate(room, p);
  });

  socket.on('accuse', ({ accusedId }) => {
    const room = rooms.get(socket.data.roomCode);
    const p = room?.players.get(socket.id);
    const accused = room?.players.get(accusedId);
    if (!room || !p || !accused || room.state !== 'playing') return;
    if (p.accusationUsed || accused.id === p.id) return;

    p.accusationUsed = true;
    if (accused.targetId === p.id) {
      accused.exposed = true;
      p.station = 100;
      feed(room, `🚨 ${p.name} EXPOSED ${accused.name} as their saboteur! Sabotage disabled.`);
      sendPrivate(room, accused);
      io.to(accused.id).emit('toast', '🚨 You were exposed! No more sabotage for you.');
    } else {
      p.station -= WRONG_ACCUSE_DAMAGE;
      feed(room, `🤡 ${p.name} accused ${accused.name}… wildly wrong. Paranoia damage!`);
      if (p.station <= 0) breakStation(room, p, 'paranoia meltdown');
    }
    sendPrivate(room, p);
  });

  socket.on('disconnect', () => {
    const room = rooms.get(socket.data.roomCode);
    if (!room) return;
    if (socket.id === room.hostId) {
      // Host left: close the room.
      if (room.interval) clearInterval(room.interval);
      io.to(room.code).emit('roomClosed');
      rooms.delete(room.code);
      return;
    }
    const p = room.players.get(socket.id);
    if (!p) return;
    if (room.state === 'lobby') {
      room.players.delete(socket.id);
      feed(room, `${p.name} left.`);
    } else {
      p.connected = false;
      feed(room, `${p.name} disconnected — their station is unmanned!`);
    }
    broadcast(room);
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`Best Friends running on http://localhost:${PORT}  (host screen: /host)`));
