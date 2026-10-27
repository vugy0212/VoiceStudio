#!/usr/bin/env bun
/**
 * Test script for VoiceStudio On-Demand Gateway
 */

console.log("=== Testiranje VoiceStudio On-Demand Gateway-a ===");

async function test() {
  const base = "http://127.0.0.1:3900";

  console.log("\n[1] Provjera statusa Gateway-a dok spava (/gateway/status)...");
  try {
    const resStatus = await fetch(`${base}/gateway/status`);
    const statusData = await resStatus.json();
    console.log("Status odgovor:", statusData);
  } catch (err) {
    console.error("Greska pri spajanju na Gateway (da li je pokrenut?):", err.message);
    process.exit(1);
  }

  console.log("\n[2] Pozivanje /system/info sa 'hladnim startom' (on-demand buđenje)...");
  const t0 = Date.now();
  try {
    const resInfo = await fetch(`${base}/system/info`);
    const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
    console.log(`HTTP Kod: ${resInfo.status} (trajalo: ${elapsed}s)`);
    const infoData = await resInfo.json();
    console.log(`Backend javlja verziju: ${infoData.app_version}, Uređaj: ${infoData.device}, GPU: ${infoData.gpu_name}`);
  } catch (err) {
    console.error("Greska pri pozivu /system/info:", err.message);
    process.exit(1);
  }

  console.log("\n[3] Pozivanje /profiles dok je engine već budan (vrući poziv)...");
  const t1 = Date.now();
  try {
    const resProfiles = await fetch(`${base}/profiles`);
    const elapsedHot = ((Date.now() - t1) / 1000).toFixed(2);
    const profiles = await resProfiles.json();
    console.log(`HTTP Kod: ${resProfiles.status} (trajalo: ${elapsedHot}s, pronađeno profila: ${Array.isArray(profiles) ? profiles.length : 0})`);
  } catch (err) {
    console.error("Greska pri pozivu /profiles:", err.message);
  }

  console.log("\n[4] Provjera statusa nakon buđenja (/gateway/status)...");
  try {
    const resStatus2 = await fetch(`${base}/gateway/status`);
    const statusData2 = await resStatus2.json();
    console.log("Status odgovor:", statusData2);
  } catch (err) {}

  console.log("\n[5] Testiranje stavljanja u stanje spavanja (/gateway/sleep)...");
  try {
    const resSleep = await fetch(`${base}/gateway/sleep`, { method: "POST" });
    const sleepData = await resSleep.json();
    console.log("Sleep odgovor:", sleepData);
  } catch (err) {}

  console.log("\n=== TESTIRANJE USPJESNO ZAVRSENO! ===");
}

test();
