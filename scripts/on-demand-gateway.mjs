#!/usr/bin/env bun
/**
 * VoiceStudio On-Demand Multi-User Lazy Gateway
 *
 * Listens on port 3900 (where Cloudflare Tunnel points).
 * Features:
 * 1. On-Demand GPU Wake & Idle Auto-Sleep (0% GPU VRAM when idle).
 * 2. Sequential FIFO GPU Job Queue (prevents VRAM OOM when 10-100 users synthesize concurrently).
 * 3. 3-Tier Multi-User Hierarchy:
 *    - 'user' (Standard/Demo): sees only the 4 demo models (Pantić, Šojić, dijete, Bata S.) + own cloned voices.
 *    - 'premium' (Premium): sees ALL Administrator voice models + own cloned voices (cannot delete Admin voices).
 *    - 'admin' (Administrator): full access to all models, history, and GPU controls.
 */

import { spawn, spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const MULTIUSER_STATE_FILE = resolve(ROOT_DIR, "omnivoice_multiuser_state.json");

// Default 4 voice models visible to regular (Standard/Demo) approved users:
// 7f0c9f12 = pantić, 615d3946 = Šojić (Ćorka), 044e7ae8 = dijete, 9ebc541f = Bata S.
const DEFAULT_PUBLIC_PROFILE_IDS = ["7f0c9f12", "615d3946", "044e7ae8", "9ebc541f"];
const DEFAULT_PUBLIC_NAME_KEYWORDS = ["pantić", "pantic", "šojić", "sojic", "dijete", "bata s"];

const GATEWAY_PORT = Number(process.env.GATEWAY_PORT || 3900);
const BACKEND_PORT = Number(process.env.BACKEND_INTERNAL_PORT || 3905);
const IDLE_TIMEOUT_MS = Number(process.env.VOICESTUDIO_IDLE_MINUTES || 15) * 60 * 1000;
const STARTUP_TIMEOUT_MS = 60 * 1000;
const MAX_CONCURRENT_GPU_JOBS = Number(process.env.VOICESTUDIO_MAX_CONCURRENT_GPU || 1);
const MAX_GPU_QUEUE_SIZE = 50;

let backendProcess = null;
let backendState = "SLEEPING"; // "SLEEPING" | "STARTING" | "RUNNING" | "STOPPING"
let startupPromise = null;
let lastActivityTime = 0;
let idleCheckInterval = null;

// --- FIFO GPU Job Queue State ---
let activeGpuJobs = 0;
const gpuQueue = [];

function enqueueGpuJob(taskFn) {
  if (gpuQueue.length >= MAX_GPU_QUEUE_SIZE) {
    return Promise.reject(new Error("GPU red cekanja je pun. Pokusajte za nekoliko sekundi."));
  }
  return new Promise((resolveJob, rejectJob) => {
    gpuQueue.push({ taskFn, resolveJob, rejectJob });
    drainGpuQueue();
  });
}

async function drainGpuQueue() {
  if (activeGpuJobs >= MAX_CONCURRENT_GPU_JOBS || gpuQueue.length === 0) return;
  const next = gpuQueue.shift();
  if (!next) return;

  activeGpuJobs++;
  touchActivity();
  try {
    const result = await next.taskFn();
    next.resolveJob(result);
  } catch (err) {
    next.rejectJob(err);
  } finally {
    activeGpuJobs = Math.max(0, activeGpuJobs - 1);
    touchActivity();
    drainGpuQueue();
  }
}

// --- Multi-User Ownership & Public Profile Allowlist ---
let multiUserState = {
  publicProfileIds: [...DEFAULT_PUBLIC_PROFILE_IDS],
  profileOwners: {}, // profileId -> userId (only set for non-admin user-created profiles)
  historyOwners: {}, // filename or id -> userId
};

function loadMultiUserState() {
  try {
    if (existsSync(MULTIUSER_STATE_FILE)) {
      const raw = readFileSync(MULTIUSER_STATE_FILE, "utf8");
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object") {
        if (Array.isArray(parsed.publicProfileIds) && parsed.publicProfileIds.length > 0) {
          multiUserState.publicProfileIds = parsed.publicProfileIds;
        }
        multiUserState.profileOwners = parsed.profileOwners || {};
        multiUserState.historyOwners = parsed.historyOwners || {};
      }
    }
  } catch (err) {
    log(`Upozorenje pri citanju multiuser stanja: ${err.message}`);
  }
}

function saveMultiUserState() {
  try {
    writeFileSync(MULTIUSER_STATE_FILE, JSON.stringify(multiUserState, null, 2), "utf8");
  } catch (err) {
    log(`Upozorenje pri spremanju multiuser stanja: ${err.message}`);
  }
}

function isProfileVisibleToUser(profile, userId, userRole, customAllowedVoiceIds = null) {
  if (!profile) return false;
  if (userRole === "admin") return true;

  const pid = String(profile.id || "");
  const owner = multiUserState.profileOwners[pid];

  // Own created voice is always visible
  if (userId && owner === userId) return true;

  // Another non-admin user's private cloned voice is hidden from other users
  if (owner && owner !== userId) return false;

  // If the user has an explicit per-user or per-group voice selection assigned by Admin:
  if (Array.isArray(customAllowedVoiceIds) && customAllowedVoiceIds.length > 0) {
    return customAllowedVoiceIds.includes(pid);
  }

  // Premium users (without a restricted custom list) see ALL admin/shared voices!
  if (userRole === "premium") return true;

  // Standard ('user' / demo) users see only the allowed public/demo voices
  if (multiUserState.publicProfileIds.includes(pid)) {
    return true;
  }
  const lowerName = String(profile.name || "").toLowerCase();
  return DEFAULT_PUBLIC_NAME_KEYWORDS.some((kw) => lowerName.includes(kw));
}

loadMultiUserState();

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
      headers: { Accept: "application/json" },
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

  // Ako je backend vec aktivan na portu 3905 (npr. postojeci proces), koristi ga odmah
  if (await checkBackendReady()) {
    backendState = "RUNNING";
    lastActivityTime = Date.now();
    log("VoiceStudio backend je vec aktivan na portu 3905.");
    return true;
  }

  backendState = "STARTING";
  log("Pokrecem VoiceStudio backend (on-demand start)...");
  const startTime = Date.now();

  startupPromise = (async () => {
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
      if (
        line &&
        (line.includes("ERROR") ||
          line.includes("Deferred startup complete") ||
          line.includes("Uvicorn running"))
      ) {
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
    if (backendState === "RUNNING" && activeGpuJobs === 0 && gpuQueue.length === 0) {
      const idleTime = Date.now() - lastActivityTime;
      if (idleTime >= IDLE_TIMEOUT_MS) {
        const mins = (IDLE_TIMEOUT_MS / 60000).toFixed(0);
        log(`Proslo je ${mins} min neaktivnosti bez zahtjeva.`);
        stopBackend();
      }
    }
  }, 10000);
}

function isHeavyGpuRoute(method, pathname) {
  if (method !== "POST") return false;
  return (
    pathname === "/generate" ||
    pathname === "/synthesize" ||
    pathname === "/synthesize/stream" ||
    pathname === "/convert" ||
    pathname === "/clean-audio"
  );
}

function cleanFileKey(rawPath) {
  if (!rawPath) return "";
  return String(rawPath).split("/").pop().split("\\").pop().trim();
}

const server = Bun.serve({
  port: GATEWAY_PORT,
  hostname: "0.0.0.0",
  async fetch(req) {
    const url = new URL(req.url);
    const userId = req.headers.get("x-vs-user-id")?.trim() || "";
    const userRole = req.headers.get("x-vs-user-role")?.trim() || "admin"; // 'admin' | 'premium' | 'user'
    const allowedHeader = req.headers.get("x-vs-allowed-voices")?.trim() || "";
    const customAllowedVoiceIds = allowedHeader
      ? allowedHeader.split(",").map((s) => s.trim()).filter(Boolean)
      : null;
    const isAdmin = userRole === "admin";
    const isNonAdminUser = !isAdmin && userId.length > 0;

    // 1. Non-waking Gateway Status Endpoint
    if (url.pathname === "/gateway/status") {
      const remainingMs = Math.max(0, IDLE_TIMEOUT_MS - (Date.now() - lastActivityTime));
      return Response.json({
        service: "VoiceStudio On-Demand Multi-User Gateway",
        gateway_port: GATEWAY_PORT,
        backend_internal_port: BACKEND_PORT,
        status: backendState,
        idle_timeout_minutes: IDLE_TIMEOUT_MS / 60000,
        idle_seconds_remaining: backendState === "RUNNING" ? Math.floor(remainingMs / 1000) : 0,
        queue_length: gpuQueue.length,
        active_gpu_jobs: activeGpuJobs,
        public_profile_ids: multiUserState.publicProfileIds,
        pid: isNonAdminUser ? null : (backendProcess?.pid ?? null),
      });
    }

    if (url.pathname === "/gateway/public-profiles" && req.method === "POST") {
      if (!isAdmin) {
        return Response.json({ error: "Forbidden" }, { status: 403 });
      }
      try {
        const body = await req.json();
        if (body && Array.isArray(body.profile_ids)) {
          multiUserState.publicProfileIds = body.profile_ids.map((x) => String(x));
          saveMultiUserState();
          return Response.json({
            success: true,
            public_profile_ids: multiUserState.publicProfileIds,
          });
        }
      } catch (err) {
        return Response.json({ error: String(err) }, { status: 400 });
      }
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
      if (!isAdmin) {
        return Response.json(
          { error: "Samo administrator moze ugasiti GPU servis." },
          { status: 403 }
        );
      }
      if ((activeGpuJobs > 0 || gpuQueue.length > 0) && url.searchParams.get("force") !== "true") {
        return Response.json(
          { error: "Sinteza je trenutno u tijeku za korisnika. Pricekajte zavrsetak." },
          { status: 409 }
        );
      }
      stopBackend();
      return Response.json({ success: true, status: "sleeping" });
    }

    // 2. Multi-User Authorization Check for Profile Deletion & Editing (Non-admins can only edit/delete their OWN cloned voices)
    if ((req.method === "DELETE" || req.method === "PUT") && url.pathname.startsWith("/profiles/")) {
      const profileId = decodeURIComponent(url.pathname.replace("/profiles/", "").split("/")[0]);
      if (isNonAdminUser) {
        const owner = multiUserState.profileOwners[profileId];
        if (!owner || owner !== userId) {
          return Response.json(
            { detail: "Nemate ovlasti za izmjenu ili brisanje administratorskog glasa." },
            { status: 403 }
          );
        }
      }
    }

    touchActivity();

    // Wake backend if sleeping
    if (backendState === "SLEEPING") {
      log(`Prispio zahtjev [${req.method} ${url.pathname}] (user: ${userId || "admin"}, role: ${userRole}). Budim VoiceStudio...`);
      try {
        await startBackend();
      } catch (err) {
        return Response.json(
          {
            error: "VoiceStudio startup failed",
            detail: String(err),
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

    const targetUrl = `http://127.0.0.1:${BACKEND_PORT}${url.pathname}${url.search}`;
    const headers = new Headers(req.headers);
    headers.set("host", `127.0.0.1:${BACKEND_PORT}`);

    const executeProxyFetch = async () => {
      const isBodyAllowed = req.method !== "GET" && req.method !== "HEAD";
      return await fetch(targetUrl, {
        method: req.method,
        headers,
        body: isBodyAllowed ? req.body : undefined,
        // @ts-ignore
        duplex: "half",
      });
    };

    try {
      const resp = isHeavyGpuRoute(req.method, url.pathname)
        ? await enqueueGpuJob(executeProxyFetch)
        : await executeProxyFetch();

      // --- Multi-User Isolation Interception ---
      // A) Filter GET /profiles for non-admin users ('user' vs 'premium' vs custom group/selection)
      if (req.method === "GET" && url.pathname === "/profiles" && resp.status === 200 && isNonAdminUser) {
        const list = await resp.json();
        if (Array.isArray(list)) {
          const filtered = list.filter((p) =>
            isProfileVisibleToUser(p, userId, userRole, customAllowedVoiceIds)
          );
          return Response.json(filtered);
        }
      }

      // B) Record ownership when a non-admin user creates a profile (POST /profiles)
      if (
        req.method === "POST" &&
        url.pathname === "/profiles" &&
        (resp.status === 200 || resp.status === 201) &&
        isNonAdminUser
      ) {
        const created = await resp.json();
        if (created && created.id) {
          multiUserState.profileOwners[created.id] = userId;
          saveMultiUserState();
        }
        return Response.json(created, { status: resp.status });
      }

      // C) Clean up ownership on DELETE /profiles/{id}
      if (req.method === "DELETE" && url.pathname.startsWith("/profiles/") && resp.status === 200) {
        const profileId = decodeURIComponent(url.pathname.replace("/profiles/", "").split("/")[0]);
        if (multiUserState.profileOwners[profileId]) {
          delete multiUserState.profileOwners[profileId];
          saveMultiUserState();
        }
      }

      // D) Record ownership of generated audio on POST /generate or POST /convert
      if (req.method === "POST" && url.pathname === "/generate" && resp.status === 200 && userId) {
        const audioPathHeader = resp.headers.get("X-Audio-Path");
        if (audioPathHeader) {
          const key = cleanFileKey(audioPathHeader);
          if (key) {
            multiUserState.historyOwners[key] = userId;
            saveMultiUserState();
          }
        }
      }

      if (req.method === "POST" && url.pathname === "/convert" && resp.status === 200 && userId) {
        const data = await resp.json();
        if (data) {
          if (data.id) multiUserState.historyOwners[String(data.id)] = userId;
          if (data.audio_url) multiUserState.historyOwners[cleanFileKey(data.audio_url)] = userId;
          saveMultiUserState();
        }
        return Response.json(data, { status: 200 });
      }

      // E) Filter GET /history so non-admin users only see their own generations
      if (req.method === "GET" && url.pathname === "/history" && resp.status === 200 && isNonAdminUser) {
        const list = await resp.json();
        if (Array.isArray(list)) {
          const filtered = list.filter((item) => {
            const fileKey = cleanFileKey(item.filename || item.audio_path || item.audio_url || "");
            const idKey = String(item.id || "");
            return (
              multiUserState.historyOwners[fileKey] === userId ||
              multiUserState.historyOwners[idKey] === userId
            );
          });
          return Response.json(filtered);
        }
      }

      return new Response(resp.body, {
        status: resp.status,
        statusText: resp.statusText,
        headers: resp.headers,
      });
    } catch (err) {
      log(`Greska pri prosljedjivanju na backend: ${err.message}`);
      const status = String(err.message).includes("red cekanja") ? 429 : 502;
      return Response.json(
        { error: "Backend proxy error", detail: err.message },
        { status }
      );
    }
  },
});

log("===================================================================");
log("   VoiceStudio Multi-User Tihi Servis (On-Demand Gateway + Queue)");
log("===================================================================");
log(`Slusam na: http://0.0.0.0:${GATEWAY_PORT} (Cloudflare Tunnel port)`);
log(`Interni backend port: ${BACKEND_PORT}`);
log(`GPU Red Cekanja (Max istodobnih sinteza): ${MAX_CONCURRENT_GPU_JOBS}`);
log(`Uloge: 'user' (4 demo glasa), 'premium' (svi admin glasovi), 'admin'`);
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
