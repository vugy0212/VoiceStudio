import { spawn } from 'node:child_process';

console.log('Pokretanje VoiceStudio servisa (API + Frontend)...');

const bunPath = process.execPath;

const api = spawn(bunPath, ['run', 'dev:api'], {
  stdio: 'inherit',
});

const fe = spawn(bunPath, ['run', 'dev:frontend'], {
  stdio: 'inherit',
});

let stopping = false;
function shutdown(code = 0) {
  if (stopping) return;
  stopping = true;
  try { api.kill(); } catch {}
  try { fe.kill(); } catch {}
  process.exit(code);
}

process.on('SIGINT', () => shutdown(0));
process.on('SIGTERM', () => shutdown(0));

api.on('exit', (code) => {
  if (!stopping && code !== 0) {
    console.error(`[api] Proces je neocekivano zavrsio (kod: ${code})`);
    shutdown(code ?? 1);
  }
});

fe.on('exit', (code) => {
  if (!stopping && code !== 0) {
    console.error(`[fe] Proces je neocekivano zavrsio (kod: ${code})`);
    shutdown(code ?? 1);
  }
});
