// MotorTown HUD – Modern Pro

// Tacho-Geometrie: 240° Bogen, CX=170, CY=155, R=120
const CX = 170,
  CY = 155,
  R = 120;
const D0 = -120,
  DR = 240;

function polar(deg, r) {
  const rad = ((deg - 90) * Math.PI) / 180;
  return {
    x: +(CX + r * Math.cos(rad)).toFixed(2),
    y: +(CY + r * Math.sin(rad)).toFixed(2),
  };
}

function arcPath(from, to, r) {
  const s = polar(from, r),
    e = polar(to, r);
  return `M${s.x} ${s.y} A${r} ${r} 0 ${to - from > 180 ? 1 : 0} 1 ${e.x} ${e.y}`;
}

// ── Skala aufbauen ─────────────────────────────────────────
(function buildScale() {
  const gm = document.getElementById("scale-g");
  const gl = document.getElementById("scale-labels");
  if (!gm) return;

  for (let i = 0; i <= 10; i++) {
    const deg = D0 + (i / 10) * DR;
    const outer = polar(deg, 120);
    const inner = polar(deg, 106);
    const tick = document.createElementNS("http://www.w3.org/2000/svg", "line");
    tick.setAttribute("x1", outer.x);
    tick.setAttribute("y1", outer.y);
    tick.setAttribute("x2", inner.x);
    tick.setAttribute("y2", inner.y);
    tick.setAttribute("class", "sm major");
    gm.appendChild(tick);

    if (gl) {
      const lp = polar(deg, 92);
      const lbl = document.createElementNS(
        "http://www.w3.org/2000/svg",
        "text",
      );
      lbl.setAttribute("x", lp.x);
      lbl.setAttribute("y", lp.y);
      lbl.setAttribute("class", "slbl");
      lbl.textContent = i;
      gl.appendChild(lbl);
    }

    if (i < 10) {
      for (let j = 1; j < 4; j++) {
        const d2 = D0 + ((i + j / 4) / 10) * DR;
        const sub_o = polar(d2, 120);
        const sub_i = polar(d2, 113);
        const sub = document.createElementNS(
          "http://www.w3.org/2000/svg",
          "line",
        );
        sub.setAttribute("x1", sub_o.x);
        sub.setAttribute("y1", sub_o.y);
        sub.setAttribute("x2", sub_i.x);
        sub.setAttribute("y2", sub_i.y);
        sub.setAttribute("class", "sm");
        gm.appendChild(sub);
      }
    }
  }
})();

// ── RPM: Nadel + Bogen ─────────────────────────────────────
function setRPM(v) {
  const pct = Math.min(Math.max(v, 0), 100) / 100;
  const deg = D0 + pct * DR;

  const needle = document.getElementById("s-needle");
  if (needle) needle.style.transform = `rotate(${deg}deg)`;

  const arc = document.getElementById("rpm-arc");
  if (arc) {
    arc.setAttribute("d", pct < 0.003 ? `M${CX} ${CY}` : arcPath(D0, deg, R));
    arc.classList.remove("yellow", "red");
    if (pct > 0.87) arc.classList.add("red");
    else if (pct > 0.67) arc.classList.add("yellow");
  }
}

// ── Sprit: einzelner Bogen rechts ─────────────────────────
// Bogen-Pfad: "M 318 82 A 162 162 0 0 1 318 228"
// Länge ≈ π × 162 × (146° / 180°) ≈ 206 px  →  wir nutzen 204
const FUEL_LEN = 207;

function setFuel(pct) {
  const filled = (Math.max(0, Math.min(100, pct)) / 100) * FUEL_LEN;
  const el = document.getElementById("fuel-fill");
  if (!el) return;

  el.style.strokeDasharray = `${filled.toFixed(1)} ${FUEL_LEN}`;
  el.style.strokeDashoffset = "0";

  el.classList.remove("warning", "critical");
  if (pct <= 10) el.classList.add("critical");
  else if (pct <= 25) el.classList.add("warning");
}

// ── Blinker (JS-Timer) ─────────────────────────────────────
let lOn = false,
  rOn = false,
  blinkTimer = null,
  blinkState = false;

function tickBlink() {
  blinkState = !blinkState;
  const lo = lOn && blinkState;
  const ro = rOn && blinkState;
  document.getElementById("sb-left")?.classList.toggle("lit", lo);
  document.getElementById("sb-right")?.classList.toggle("lit", ro);
  document
    .getElementById("sb-hazard")
    ?.classList.toggle("active", lOn && rOn && blinkState);
}

function updateBlinkers(l, r) {
  lOn = !!l;
  rOn = !!r;
  if ((l || r) && !blinkTimer) blinkTimer = setInterval(tickBlink, 550);
  if (!l && !r) {
    clearInterval(blinkTimer);
    blinkTimer = null;
    blinkState = false;
    document.getElementById("sb-left")?.classList.remove("lit");
    document.getElementById("sb-right")?.classList.remove("lit");
    document.getElementById("sb-hazard")?.classList.remove("active");
  }
}

// ── Hilfsfunktionen ────────────────────────────────────────
const $ = (id) => document.getElementById(id);
const tx = (id, v) => {
  const e = $(id);
  if (e) e.textContent = v;
};
const tog = (id, cls, on) => $(id)?.classList.toggle(cls, !!on);

// ── NUI Messages ───────────────────────────────────────────
window.addEventListener("message", (e) => {
  const d = e.data;
  if (!d || !d.action) return;

  // ── Fahrzeug anzeigen ────────────────────────────────
  if (d.action === "vehicle_show") {
    const hud = $("vehicle-hud");
    if (!hud) return;
    hud.classList.remove("hidden");

    const spd = d.speed ?? 0;
    const fuel = Math.max(0, Math.min(100, d.fuel ?? 100));
    const eng = Math.max(0, Math.min(100, d.engine ?? 100));
    const gear = d.gear ?? "N";

    tx("speed", spd);
    tx("gear", gear);
    tx("gear-bot", gear);
    tx("rpm-display", ((d.rpmRaw ?? 0) / 1000).toFixed(1));
    tx(
      "odo-display",
      String(Math.floor(d.odometer ?? 0)).padStart(6, "0") + " KM",
    );

    setRPM(d.rpm ?? 0);
    setFuel(fuel);

    // Fuel-Icon
    const ci = $("ci-fuel");
    if (ci) {
      ci.classList.remove("warning", "critical");
      if (fuel <= 10) ci.classList.add("critical");
      else if (fuel <= 25) ci.classList.add("warning");
    }

    // Engine-Icon
    tog("ci-engine", "active", eng <= 50);

    // Statusleiste
    tog("sb-light-low", "active", d.lightsLow);
    tog("sb-light-high", "active", d.lightsHigh);
    tog("sb-tcs", "active", d.tcs);

    // Gurt
    const sb = $("sb-seatbelt");
    if (sb) {
      sb.classList.remove("red", "green");
      if (d.seatbelt) sb.classList.add("green");
      else if (spd > 10) sb.classList.add("red");
    }

    updateBlinkers(d.leftSignal, d.rightSignal);
  }

  if (d.action === "vehicle_hide") {
    $("vehicle-hud")?.classList.add("hidden");
    clearInterval(blinkTimer);
    blinkTimer = null;
  }

  // ── Spieler ──────────────────────────────────────────
  if (d.action === "player_update") {
    $("player-panel")?.classList.remove("hidden");
    tx("player-money", d.money ?? "$0");
    tx("player-level", "LVL " + (d.level ?? 1));
    tx("player-xp", (d.xp ?? 0) + " XP");
    const b = $("xp-bar");
    if (b) b.style.width = (d.xpPct ?? 0) + "%";
  }

  // ── Job ───────────────────────────────────────────────
  if (d.action === "job_show") {
    $("job-panel")?.classList.remove("hidden");
    tx("job-icon", d.step === "Liefern" ? "📍" : "📦");
    tx("job-label", d.label ?? "—");
    tx("job-step", d.step ?? "—");
  }
  if (d.action === "job_hide") $("job-panel")?.classList.add("hidden");

  // ── Bonus ─────────────────────────────────────────────
  if (d.action === "bonus_show") {
    $("bonus-panel")?.classList.remove("hidden");
    tx("bonus-label", "+" + (d.pct ?? 0) + "%");
  }
  if (d.action === "bonus_hide") $("bonus-panel")?.classList.add("hidden");
});

// ── Startup-Sweep ──────────────────────────────────────────
(function startup() {
  setFuel(100);
  let v = 0;
  const up = setInterval(() => {
    v += 2;
    setRPM(v);
    if (v >= 100) {
      clearInterval(up);
      setTimeout(() => {
        const dn = setInterval(() => {
          v -= 2;
          setRPM(v);
          if (v <= 0) {
            clearInterval(dn);
            setRPM(0);
          }
        }, 14);
      }, 200);
    }
  }, 14);
})();

// ── Zone Editor ────────────────────────────────────────────
(function zoneEditor() {
  const panel = document.getElementById("zone-editor");
  const keyEl = document.getElementById("ze-key");
  const labelEl = document.getElementById("ze-label");
  const sxEl = document.getElementById("ze-sx");
  const syEl = document.getElementById("ze-sy");
  const szEl = document.getElementById("ze-sz");
  const rotEl = document.getElementById("ze-rot");
  if (!panel) return;

  function updateTrack(el) {
    const pct =
      (((el.value - el.min) / (el.max - el.min)) * 100).toFixed(1) + "%";
    el.style.setProperty("--pct", pct);
  }

  function sendChange() {
    fetch(`https://motortown/zoneEditorChange`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        label: labelEl.value,
        sizeX: parseFloat(sxEl.value),
        sizeY: parseFloat(syEl.value),
        sizeZ: parseFloat(szEl.value),
        rotation: parseInt(rotEl.value),
      }),
    });
  }

  function bindSlider(el, valId) {
    el.addEventListener("input", () => {
      document.getElementById(valId).textContent = el.value;
      updateTrack(el);
      sendChange();
    });
  }

  bindSlider(sxEl, "ze-sx-val");
  bindSlider(syEl, "ze-sy-val");
  bindSlider(szEl, "ze-sz-val");
  bindSlider(rotEl, "ze-rot-val");
  labelEl.addEventListener("input", sendChange);

  document.getElementById("ze-save").addEventListener("click", () => {
    fetch(`https://motortown/zoneEditorSave`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        label: labelEl.value,
        sizeX: parseFloat(sxEl.value),
        sizeY: parseFloat(syEl.value),
        sizeZ: parseFloat(szEl.value),
        rotation: parseInt(rotEl.value),
      }),
    });
    panel.classList.remove("visible");
  });

  document.getElementById("ze-cancel").addEventListener("click", () => {
    fetch(`https://motortown/zoneEditorCancel`, { method: "POST" });
    panel.classList.remove("visible");
  });

  window.addEventListener("message", (e) => {
    const d = e.data;
    if (!d) return;

    if (d.action === "openZoneEditor") {
      keyEl.textContent = d.key || "—";
      labelEl.value = d.label || "";
      sxEl.value = d.sizeX || 4;
      syEl.value = d.sizeY || 4;
      szEl.value = d.sizeZ || 2;
      rotEl.value = d.rotation || 0;
      document.getElementById("ze-sx-val").textContent = sxEl.value;
      document.getElementById("ze-sy-val").textContent = syEl.value;
      document.getElementById("ze-sz-val").textContent = szEl.value;
      document.getElementById("ze-rot-val").textContent = rotEl.value;
      [sxEl, syEl, szEl, rotEl].forEach(updateTrack);
      panel.classList.add("visible");
    }

    if (d.action === "closeZoneEditor") {
      panel.classList.remove("visible");
    }
  });
})();
