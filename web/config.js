/**
 * Game server configuration for Age of War multiplayer.
 *
 * LOCAL DEV:  Leave SERVER_URL as null — connects to same origin.
 * PRODUCTION: After deploying the backend to Render.com, paste your
 *             Render URL below (e.g. "https://age-of-war-abc123.onrender.com").
 *             Then redeploy the Vercel frontend.
 */
window.GAME_CONFIG = {
  SERVER_URL: null,
};

/**
 * Resolves WebSocket + HTTP base URLs from the config above.
 * null → same-origin; string → explicit Render backend URL.
 */
(function () {
  const cfg = window.GAME_CONFIG;
  const base = cfg.SERVER_URL;

  if (base) {
    const url = new URL(base);
    cfg.WS_URL = (url.protocol === "https:" ? "wss://" : "ws://") + url.host;
    cfg.HTTP_URL = base.replace(/\/+$/, "");
  } else {
    const proto = location.protocol === "https:" ? "wss://" : "ws://";
    cfg.WS_URL = proto + location.host;
    cfg.HTTP_URL = location.origin;
  }
})();
