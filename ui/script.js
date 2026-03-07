// ═══════════════════════════════════════════════════════════
//  MotorTown HUD – script.js
//  Verarbeitet NUI-Nachrichten vom Lua-Client
// ═══════════════════════════════════════════════════════════

// ── Tacho-Geometrie ─────────────────────────────────────────
// Bogen: Start bei -110° (links), Ende bei +110° (rechts) → 220° gesamt
// RPM 0–100 → -110° bis +110°
const CX = 110,
  CY = 110,
  R = 88;
const ARC_START_DEG = -110;
const ARC_TOTAL_DEG = 220;

function degToRad(d) {
  return (d * Math.PI) / 180;
}

function polarToXY(deg, r) {
  const rad = degToRad(deg - 90); // SVG 0° = oben
  return {
    x: CX + r * Math.cos(rad),
    y: CY + r * Math.sin(rad),
  };
}

function arcPath(fromDeg, toDeg, r) {
  const start = polarToXY(fromDeg, r);
  const end = polarToXY(toDeg, r);
  const diff = toDeg - fromDeg;
  const large = diff > 180 ? 1 : 0;
  return `M ${start.x.toFixed(2)} ${start.y.toFixed(2)} A ${r} ${r} 0 ${large} 1 ${end.x.toFixed(2)} ${end.y.toFixed(2)}`;
}

// ── Skalenstriche beim Start generieren ─────────────────────
function buildScaleMarks() {
  const g = document.getElementById("scale-marks");
  if (!g) return;
  // 9 Hauptstriche (0–8 × 1000 RPM) + Nebenstriche
  for (let i = 0; i <= 8; i++) {
    const pct = i / 8;
    const deg = ARC_START_DEG + pct * ARC_TOTAL_DEG;
    const outer = polarToXY(deg, 88);
    const inner = polarToXY(deg, 76);
    const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
    line.setAttribute("x1", outer.x.toFixed(1));
    line.setAttribute("y1", outer.y.toFixed(1));
    line.setAttribute("x2", inner.x.toFixed(1));
    line.setAttribute("y2", inner.y.toFixed(1));
    line.setAttribute("class", "scale-mark major");
    g.appendChild(line);
  }
  // Kleine Zwischenstriche
  for (let i = 0; i < 8; i++) {
    for (let j = 1; j < 4; j++) {
      const pct = (i + j / 4) / 8;
      const deg = ARC_START_DEG + pct * ARC_TOTAL_DEG;
      const outer = polarToXY(deg, 88);
      const inner = polarToXY(deg, 82);
      const line = document.createElementNS(
        "http://www.w3.org/2000/svg",
        "line",
      );
      line.setAttribute("x1", outer.x.toFixed(1));
      line.setAttribute("y1", outer.y.toFixed(1));
      line.setAttribute("x2", inner.x.toFixed(1));
      line.setAttribute("y2", inner.y.toFixed(1));
      line.setAttribute("class", "scale-mark");
      g.appendChild(line);
    }
  }
}
buildScaleMarks();

// ── Nadel & Bogen aktualisieren ─────────────────────────────
function updateRPM(rpm) {
  const pct = Math.min(Math.max(rpm, 0), 100) / 100;
  const deg = ARC_START_DEG + pct * ARC_TOTAL_DEG;

  // Nadel drehen (transform-origin im SVG ist 110 110)
  const needle = document.getElementById("needle");
  if (needle) {
    needle.style.transform = `rotate(${ARC_START_DEG + pct * ARC_TOTAL_DEG}deg)`;
  }

  // Aktiver Bogen
  const arc = document.getElementById("arc-active");
  if (arc) {
    if (pct < 0.001) {
      arc.setAttribute("d", `M ${CX} ${CY}`);
    } else {
      arc.setAttribute("d", arcPath(ARC_START_DEG, deg, 88));
    }
    arc.className =
      "arc-active" + (pct > 0.85 ? " red" : pct > 0.65 ? " yellow" : " green");
  }
}

// ── Hilfsfunktionen ──────────────────────────────────────────
function setActive(id, active, extraClass) {
  const el = document.getElementById(id);
  if (!el) return;
  el.classList.toggle("active", active);
  if (extraClass) el.classList.toggle(extraClass, active);
}

function setClass(id, cls, active) {
  const el = document.getElementById(id);
  if (el) el.classList.toggle(cls, active);
}

// ── NUI Message Handler ─────────────────────────────────────
window.addEventListener("message", function (event) {
  const d = event.data;

  // ── Fahrzeug-HUD ──────────────────────────────────────
  if (d.action === "vehicle_show") {
    document.getElementById("vehicle-hud").classList.remove("hidden");

    // Geschwindigkeit
    document.getElementById("speed").textContent = d.speed || 0;

    // RPM + Nadel
    updateRPM(d.rpm || 0);
    document.getElementById("rpm-display").textContent = d.rpmRaw || 0;

    // Gang
    document.getElementById("gear").textContent = d.gear || "N";

    // Kraftstoff
    const fuel = Math.max(0, Math.min(100, d.fuel || 0));
    const fuelBar = document.getElementById("fuel-bar");
    const fuelIcon = document.getElementById("fuel-icon");
    document.getElementById("fuel-pct").textContent = fuel + "%";
    if (fuelBar) {
      fuelBar.style.width = fuel + "%";
      fuelBar.className =
        "fuel-bar" + (fuel <= 10 ? " critical" : fuel <= 25 ? " warning" : "");
    }
    if (fuelIcon) {
      fuelIcon.className =
        "fuel-svg" + (fuel <= 10 ? " critical" : fuel <= 25 ? " warning" : "");
    }

    // Motor / ODO
    document.getElementById("engine-display").textContent = d.engine || 100;
    document.getElementById("odo-display").textContent = d.odometer
      ? d.odometer.toFixed(1)
      : "0.0";

    // Lichter
    setActive("light-low", d.lightsLow);
    setActive("light-high", d.lightsHigh);

    // Warnleuchten
    setActive("w-handbrake", d.handbrake);
    setActive("w-engine", d.engine <= 50);
    setActive("w-oil", d.isOilCritical);
    setActive("w-tcs", d.tcs);
    setActive("w-cruise", d.cruise);

    // Gurt
    const sb = document.getElementById("w-seatbelt");
    if (sb) {
      sb.classList.remove("active", "blink", "green");
      if (d.seatbelt) {
        sb.classList.add("green");
      } else {
        sb.classList.add("active");
        if (d.speed > 10) sb.classList.add("blink");
      }
    }

    // Blinker
    const bl = document.getElementById("blinker-left");
    const br = document.getElementById("blinker-right");
    if (d.leftSignal) bl.classList.add("active");
    else bl.classList.remove("active");
    if (d.rightSignal) br.classList.add("active");
    else br.classList.remove("active");
  }

  if (d.action === "vehicle_hide") {
    document.getElementById("vehicle-hud").classList.add("hidden");
  }

  // ── Spieler-Panel ──────────────────────────────────────
  if (d.action === "player_update") {
    document.getElementById("player-panel").classList.remove("hidden");
    document.getElementById("player-money").textContent = d.money || "$0";
    document.getElementById("player-level").textContent =
      "LVL " + (d.level || 1);
    document.getElementById("player-xp").textContent = (d.xp || 0) + " XP";
    const xpBar = document.getElementById("xp-bar");
    if (xpBar) xpBar.style.width = (d.xpPct || 0) + "%";
  }

  // ── Job-Panel ─────────────────────────────────────────
  if (d.action === "job_show") {
    const jp = document.getElementById("job-panel");
    jp.classList.remove("hidden");
    document.getElementById("job-icon").textContent =
      d.step === "Abholen" ? "📦" : "📍";
    document.getElementById("job-label").textContent = d.label || "—";
    document.getElementById("job-step").textContent = d.step || "—";
  }

  if (d.action === "job_hide") {
    document.getElementById("job-panel").classList.add("hidden");
  }

  // ── Bonus-Panel ───────────────────────────────────────
  if (d.action === "bonus_show") {
    const bp = document.getElementById("bonus-panel");
    bp.classList.remove("hidden");
    document.getElementById("bonus-label").textContent =
      "Bonus +" + (d.pct || 0) + "%";
  }

  if (d.action === "bonus_hide") {
    document.getElementById("bonus-panel").classList.add("hidden");
  }
});

// ── Startup-Animation ───────────────────────────────────────
(function startup() {
  let rpm = 0;
  const up = setInterval(() => {
    rpm += 3;
    updateRPM(rpm);
    if (rpm >= 100) {
      clearInterval(up);
      setTimeout(() => {
        const down = setInterval(() => {
          rpm -= 3;
          updateRPM(rpm);
          if (rpm <= 0) {
            clearInterval(down);
            updateRPM(0);
          }
        }, 15);
      }, 150);
    }
  }, 15);
})();
