#!/usr/bin/env bun
/**
 * VoiceStudio On-Demand Lazy Gateway
 * 
 * Listens on port 3900 (where Cloudflare Tunnel points).
 * Keeps the heavy VoiceStudio backend / ML models unloaded (0% GPU, ~15MB RAM).
 * When a mobile app or web client connects, it starts the backend on-demand,
 * buffers/fulfills the request, and automatically shuts down the engine after
 * a configurable idle timeout (default: 15 minutes) to free GPU VRAM and RAM.
 */

import { spawn, spawnSync } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const GATEWAY_PORT = Number(process.env.GATEWAY_PORT || 3900);
const BACKEND_PORT = Number(process.env.BACKEND_INTERNAL_PORT || 3905);
const IDLE_TIMEOUT_MS = Number(process.env.VOICESTUDIO_IDLE_MINUTES || 15) * 60 * 1000;
const STARTUP_TIMEOUT_MS = 60 * 1000;

let backendProcess = null;
let backendState = "SLEEPING"; // "SLEEPING" | "STARTING" | "RUNNING" | "STOPPING"
let startupPromise = null;
let lastActivityTime = 0;
let idleCheckInterval = null;

function log(msg) {
  const ts = new Date().toLocaleTimeString();
  console.log(`[${ts}] [VoiceStudio Gateway] ${msg}`);
}

function killProcessTree(pid) {
  if (!pid) return;
  if (process.platform === "win32") {
    spawnSync("taskkill", ["/pid", String(pid), "/T", "/F"], { stdio: "ignore" });
  } else {
    try {
      process.kill(-pid, "SIGKILL");
    } catch {
      try {
        process.kill(pid, "SIGKILL");
      } catch {}
    }
  }
}

async function checkBackendReady() {
  try {
    const res = await fetch(`http://127.0.0.1:${BACKEND_PORT}/system/info`, {
      headers: { "Accept": "application/json" },
      signal: AbortSignal.timeout(1500),
    });
    if (res.status === 200) {
      const data = await res.json().catch(() => null);
      if (data && data.app_version) {
        return true;
      }
    }
  } catch {}
  return false;
}

async function startBackend() {
  if (backendState === "RUNNING") return true;
  if (backendState === "STARTING" && startupPromise) return startupPromise;

  backendState = "STARTING";
  log("Pokrecem VoiceStudio backend (on-demand start)...");
  const startTime = Date.now();

  startupPromise = (async () => {
    // Spawn backend with uv
    const env = {
      ...process.env,
      OMNIVOICE_DATA_DIR: process.env.OMNIVOICE_DATA_DIR || `${process.env.APPDATA || ""}\\OmniVoice`,
      TORCH_COMPILE_DISABLE: "1",
      TORCHDYNAMO_DISABLE: "1",
      TORCHINDUCTOR_DISABLE: "1",
    };

    backendProcess = spawn(
      "uv",
      [
        "run",
        "uvicorn",
        "main:app",
        "--app-dir",
        "backend",
        "--host",
        "127.0.0.1",
        "--port",
        String(BACKEND_PORT),
      ],
      {
        cwd: ROOT_DIR,
        env,
        stdio: ["ignore", "pipe", "pipe"],
        detached: process.platform !== "win32",
      }
    );

    backendProcess.stdout?.on("data", (chunk) => {
      const line = chunk.toString().trim();
      if (line && (line.includes("ERROR") || line.includes("Deferred startup complete") || line.includes("Uvicorn running"))) {
        log(`[backend] ${line.split("\n")[0]}`);
      }
    });

    backendProcess.stderr?.on("data", (chunk) => {
      const line = chunk.toString().trim();
      if (line && (line.includes("ERROR") || line.includes("Traceback"))) {
        log(`[backend err] ${line.split("\n")[0]}`);
      }
    });

    backendProcess.on("exit", (code, signal) => {
      log(`Backend proces zavrsio (kod: ${code}, signal: ${signal})`);
      backendProcess = null;
      backendState = "SLEEPING";
      startupPromise = null;
    });

    // Poll until ready
    while (Date.now() - startTime < STARTUP_TIMEOUT_MS) {
      if (backendState === "STOPPING" || !backendProcess) {
        throw new Error("Backend pokretanje prekinuto.");
      }
      const ready = await checkBackendReady();
      if (ready) {
        const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
        backendState = "RUNNING";
        lastActivityTime = Date.now();
        log(`VoiceStudio backend je SPREMAN za rad (${elapsed}s)! Svi zahtjevi se proslijedjuju.`);
        startupPromise = null;
        return true;
      }
      await new Promise((r) => setTimeout(r, 600));
    }

    // Timeout exceeded
    log("UPOZORENJE: Backend nije odgovorio u zadanom roku (60s).");
    stopBackend();
    throw new Error("Backend startup timeout.");
  })();

  return startupPromise;
}

function stopBackend() {
  if (!backendProcess && backendState === "SLEEPING") return;
  log("Zaustavljam VoiceStudio backend radi oslobadjanja GPU VRAM-a i memorije...");
  backendState = "STOPPING";

  if (backendProcess && backendProcess.pid) {
    killProcessTree(backendProcess.pid);
  }
  backendProcess = null;
  backendState = "SLEEPING";
  startupPromise = null;
  log("VoiceStudio backend je uspjesno ugasen. Gateway je u tihom stand-by rezimu (0% GPU).");
}

function touchActivity() {
  lastActivityTime = Date.now();
}

function setupIdleWatcher() {
  if (idleCheckInterval) clearInterval(idleCheckInterval);
  idleCheckInterval = setInterval(() => {
    if (backendState === "RUNNING") {
      const idleTime = Date.now() - lastActivityTime;
      if (idleTime >= IDLE_TIMEOUT_MS) {
        const mins = (IDLE_TIMEOUT_MS / 60000).toFixed(0);
        log(`Proslo je ${mins} min neaktivnosti bez zahtjeva.`);
        stopBackend();
      }
    }
  }, 10000);
}

// HTTP Server using Bun.serve
const server = Bun.serve({
  port: GATEWAY_PORT,
  hostname: "0.0.0.0",
  async fetch(req) {
    const url = new URL(req.url);

    // Gateway management endpoints
    if (url.pathname === "/gateway/status") {
      const remainingMs = Math.max(0, IDLE_TIMEOUT_MS - (Date.now() - lastActivityTime));
      return Response.json({
        service: "VoiceStudio On-Demand Gateway",
        gateway_port: GATEWAY_PORT,
        backend_internal_port: BACKEND_PORT,
        status: backendState,
        idle_timeout_minutes: IDLE_TIMEOUT_MS / 60000,
        idle_seconds_remaining: backendState === "RUNNING" ? Math.floor(remainingMs / 1000) : 0,
        pid: backendProcess?.pid ?? null,
      });
    }

    if (url.pathname === "/gateway/wake" && req.method === "POST") {
      touchActivity();
      try {
        await startBackend();
        return Response.json({ success: true, status: "ready" });
      } catch (err) {
        return Response.json({ success: false, error: String(err) }, { status: 500 });
      }
    }

    if (url.pathname === "/gateway/sleep" && req.method === "POST") {
      stopBackend();
      return Response.json({ success: true, status: "sleeping" });
    }

    // Normal application requests (from mobile app, Cloudflare Tunnel, or web UI)
    touchActivity();

    // If backend is sleeping or starting, wake it up and wait for readiness
    if (backendState === "SLEEPING") {
      log(`Prispio zahtjev [${req.method} ${url.pathname}] dok je engine spavao. Budim VoiceStudio...`);
      try {
        await startBackend();
      } catch (err) {
        return Response.json(
          {
            error: "VoiceStudio startup failed",
            detail: String(err),
            suggestion: "Provjerite terminal ili logove za greske pri pokretanju.",
          },
          { status: 503 }
        );
      }
    } else if (backendState === "STARTING") {
      try {
        await (startupPromise || startBackend());
      } catch (err) {
        return Response.json(
          { error: "VoiceStudio warming up timeout", detail: String(err) },
          { status: 503 }
        );
      }
    }

    // Proxy request to the backend
    const targetUrl = `http://127.0.0.1:${BACKEND_PORT}${url.pathname}${url.search}`;
    const headers = new Headers(req.headers);
    headers.set("host", `127.0.0.1:${BACKEND_PORT}`);

    try {
      const isBodyAllowed = req.method !== "GET" && req.method !== "HEAD";
      const resp = await fetch(targetUrl, {
        method: req.method,
        headers,
        body: isBodyAllowed ? req.body : undefined,
        // @ts-ignore
        duplex: "half",
      });

      return new Response(resp.body, {
        status: resp.status,
        statusText: resp.statusText,
        headers: resp.headers,
      });
    } catch (err) {
      log(`Greska pri prosljedjivanju na backend: ${err.message}`);
      return Response.json(
        { error: "Backend proxy error", detail: err.message },
        { status: 502 }
      );
    }
  },
});

log("===================================================================");
log("       VoiceStudio Tihi Pozadinski Servis (On-Demand Gateway)");
log("===================================================================");
log(`Slušam na: http://0.0.0.0:${GATEWAY_PORT} (Cloudflare Tunnel port)`);
log(`Interni backend port: ${BACKEND_PORT}`);
log(`Automatsko gasenje nakon: ${IDLE_TIMEOUT_MS / 60000} minuta neaktivnosti`);
log(`Trenutno stanje: SLEEPING (Potrosnja: 0% GPU VRAM, ~15MB RAM)`);
log(`Cekam poziv sa mobilne aplikacije...`);
log("===================================================================");

setupIdleWatcher();

function shutdown() {
  log("Gasim gateway...");
  if (idleCheckInterval) clearInterval(idleCheckInterval);
  stopBackend();
  server.stop();
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
