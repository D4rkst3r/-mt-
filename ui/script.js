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

  const spriteEl = document.getElementById("ze-sprite");
  const bcolorEl = document.getElementById("ze-bcolor");
  const noblipEl = document.getElementById("ze-noblip");

  // GTA V Blip-Farben: ID → [hex, name]
  const BLIP_COLORS = {
    0: ["#ffffff", "Weiß"],
    1: ["#e8474a", "Rot"],
    2: ["#61bd4f", "Grün"],
    3: ["#4a90d9", "Blau"],
    5: ["#f0c040", "Gelb"],
    6: ["#9b59b6", "Lila"],
    7: ["#2ecc71", "Hellgrün"],
    8: ["#e67e22", "Orange"],
    17: ["#1abc9c", "Türkis"],
    25: ["#5dade2", "Hellblau"],
    38: ["#ff69b4", "Pink"],
    46: ["#f4d03f", "Gold"],
    47: ["#95a5a6", "Grau"],
    49: ["#2471a3", "Dunkelblau"],
    59: ["#cb4335", "Dunkelorange"],
    66: ["#76d7c4", "Mintgrün"],
  };

  // Blip Sprites: ID → filename (alle 875 Einträge aus docs.fivem.net)
  const BLIP_SPRITES = {
    0: "radar_higher",
    1: "radar_level",
    2: "radar_lower",
    3: "radar_police_ped",
    4: "radar_wanted_radius",
    5: "radar_area_blip",
    6: "radar_centre",
    7: "radar_north",
    8: "radar_waypoint",
    9: "radar_radius_blip",
    10: "radar_radius_outline_blip",
    11: "radar_weapon_higher",
    12: "radar_weapon_lower",
    13: "radar_higher_ai",
    14: "radar_lower_ai",
    15: "radar_police_heli_spin",
    16: "radar_police_plane_move",
    27: "radar_mp_crew",
    28: "radar_mp_friendlies",
    36: "radar_cable_car",
    37: "radar_activities",
    38: "radar_raceflag",
    40: "radar_safehouse",
    41: "radar_police",
    42: "radar_police_chase",
    43: "radar_police_heli",
    44: "radar_bomb_a",
    47: "radar_snitch",
    48: "radar_planning_locations",
    50: "radar_crim_carsteal",
    51: "radar_crim_drugs",
    52: "radar_crim_holdups",
    54: "radar_crim_player",
    56: "radar_cop_patrol",
    57: "radar_cop_player",
    58: "radar_crim_wanted",
    59: "radar_heist",
    60: "radar_police_station",
    61: "radar_hospital",
    62: "radar_assassins_mark",
    63: "radar_elevator",
    64: "radar_helicopter",
    66: "radar_random_character",
    67: "radar_security_van",
    68: "radar_tow_truck",
    70: "radar_illegal_parking",
    71: "radar_barber",
    72: "radar_car_mod_shop",
    73: "radar_clothes_store",
    75: "radar_tattoo",
    76: "radar_armenian_family",
    77: "radar_lester_family",
    78: "radar_michael_family",
    79: "radar_trevor_family",
    80: "radar_jewelry_heist",
    82: "radar_drag_race_finish",
    84: "radar_rampage",
    85: "radar_vinewood_tours",
    86: "radar_lamar_family",
    88: "radar_franklin_family",
    89: "radar_chinese_strand",
    90: "radar_flight_school",
    91: "radar_eye_sky",
    92: "radar_air_hockey",
    93: "radar_bar",
    94: "radar_base_jump",
    95: "radar_basketball",
    96: "radar_biolab_heist",
    99: "radar_cabaret_club",
    100: "radar_car_wash",
    102: "radar_comedy_club",
    103: "radar_darts",
    104: "radar_docks_heist",
    105: "radar_fbi_heist",
    106: "radar_fbi_officers_strand",
    107: "radar_finale_bank_heist",
    108: "radar_financier_strand",
    109: "radar_golf",
    110: "radar_gun_shop",
    111: "radar_internet_cafe",
    112: "radar_michael_family_exile",
    113: "radar_nice_house_heist",
    114: "radar_random_female",
    115: "radar_random_male",
    118: "radar_rural_bank_heist",
    119: "radar_shooting_range",
    120: "radar_solomon_strand",
    121: "radar_strip_club",
    122: "radar_tennis",
    123: "radar_trevor_family_exile",
    124: "radar_michael_trevor_family",
    126: "radar_triathlon",
    127: "radar_off_road_racing",
    128: "radar_gang_cops",
    129: "radar_gang_mexicans",
    130: "radar_gang_bikers",
    133: "radar_snitch_red",
    134: "radar_crim_cuff_keys",
    135: "radar_cinema",
    136: "radar_music_venue",
    137: "radar_police_station_blue",
    138: "radar_airport",
    139: "radar_crim_saved_vehicle",
    140: "radar_weed_stash",
    141: "radar_hunting",
    142: "radar_pool",
    143: "radar_objective_blue",
    144: "radar_objective_green",
    145: "radar_objective_red",
    146: "radar_objective_yellow",
    147: "radar_arms_dealing",
    148: "radar_mp_friend",
    149: "radar_celebrity_theft",
    150: "radar_weapon_assault_rifle",
    151: "radar_weapon_bat",
    152: "radar_weapon_grenade",
    153: "radar_weapon_health",
    154: "radar_weapon_knife",
    155: "radar_weapon_molotov",
    156: "radar_weapon_pistol",
    157: "radar_weapon_rocket",
    158: "radar_weapon_shotgun",
    159: "radar_weapon_smg",
    160: "radar_weapon_sniper",
    161: "radar_mp_noise",
    162: "radar_poi",
    163: "radar_passive",
    164: "radar_usingmenu",
    171: "radar_gang_cops_partner",
    173: "radar_weapon_minigun",
    175: "radar_weapon_armour",
    176: "radar_property_takeover",
    177: "radar_gang_mexicans_highlight",
    178: "radar_gang_bikers_highlight",
    179: "radar_triathlon_cycling",
    180: "radar_triathlon_swimming",
    181: "radar_property_takeover_bikers",
    182: "radar_property_takeover_cops",
    183: "radar_property_takeover_vagos",
    184: "radar_camera",
    185: "radar_centre_red",
    186: "radar_handcuff_keys_bikers",
    187: "radar_handcuff_keys_vagos",
    188: "radar_handcuffs_closed_bikers",
    189: "radar_handcuffs_closed_vagos",
    192: "radar_camera_badger",
    193: "radar_camera_facade",
    194: "radar_camera_ifruit",
    197: "radar_yoga",
    198: "radar_taxi",
    205: "radar_shrink",
    206: "radar_epsilon",
    207: "radar_financier_strand_grey",
    208: "radar_trevor_family_grey",
    209: "radar_trevor_family_red",
    210: "radar_franklin_family_grey",
    211: "radar_franklin_family_blue",
    212: "radar_franklin_a",
    213: "radar_franklin_b",
    214: "radar_franklin_c",
    225: "radar_gang_vehicle",
    226: "radar_gang_vehicle_bikers",
    227: "radar_gang_vehicle_cops",
    228: "radar_gang_vehicle_vagos",
    229: "radar_guncar",
    230: "radar_driving_bikers",
    231: "radar_driving_cops",
    232: "radar_driving_vagos",
    233: "radar_gang_cops_highlight",
    234: "radar_shield_bikers",
    235: "radar_shield_cops",
    236: "radar_shield_vagos",
    237: "radar_custody_bikers",
    238: "radar_custody_vagos",
    251: "radar_arms_dealing_air",
    252: "radar_playerstate_arrested",
    253: "radar_playerstate_custody",
    254: "radar_playerstate_driving",
    255: "radar_playerstate_keyholder",
    256: "radar_playerstate_partner",
    262: "radar_ztype",
    263: "radar_stinger",
    264: "radar_packer",
    265: "radar_monroe",
    266: "radar_fairground",
    267: "radar_property",
    268: "radar_gang_highlight",
    269: "radar_altruist",
    270: "radar_ai",
    271: "radar_on_mission",
    272: "radar_cash_pickup",
    273: "radar_chop",
    274: "radar_dead",
    275: "radar_territory_locked",
    276: "radar_cash_lost",
    277: "radar_cash_vagos",
    278: "radar_cash_cops",
    279: "radar_hooker",
    280: "radar_friend",
    281: "radar_mission_2to4",
    282: "radar_mission_2to8",
    283: "radar_mission_2to12",
    284: "radar_mission_2to16",
    285: "radar_custody_dropoff",
    286: "radar_onmission_cops",
    287: "radar_onmission_lost",
    288: "radar_onmission_vagos",
    289: "radar_crim_carsteal_cops",
    290: "radar_crim_carsteal_bikers",
    291: "radar_crim_carsteal_vagos",
    292: "radar_band_strand",
    293: "radar_simeon_family",
    294: "radar_mission_1",
    295: "radar_mission_2",
    296: "radar_friend_darts",
    297: "radar_friend_comedyclub",
    298: "radar_friend_cinema",
    299: "radar_friend_tennis",
    300: "radar_friend_stripclub",
    301: "radar_friend_livemusic",
    302: "radar_friend_golf",
    303: "radar_bounty_hit",
    304: "radar_ugc_mission",
    305: "radar_horde",
    306: "radar_cratedrop",
    307: "radar_plane_drop",
    308: "radar_sub",
    309: "radar_race",
    310: "radar_deathmatch",
    311: "radar_arm_wrestling",
    312: "radar_mission_1to2",
    313: "radar_shootingrange_gunshop",
    314: "radar_race_air",
    315: "radar_race_land",
    316: "radar_race_sea",
    317: "radar_tow",
    318: "radar_garbage",
    319: "radar_drill",
    320: "radar_spikes",
    321: "radar_firetruck",
    322: "radar_minigun2",
    323: "radar_bugstar",
    324: "radar_submarine",
    325: "radar_chinook",
    326: "radar_getaway_car",
    327: "radar_mission_bikers_1",
    328: "radar_mission_bikers_1to2",
    329: "radar_mission_bikers_2",
    330: "radar_mission_bikers_2to4",
    331: "radar_mission_bikers_2to8",
    332: "radar_mission_bikers_2to12",
    333: "radar_mission_bikers_2to16",
    334: "radar_mission_cops_1",
    335: "radar_mission_cops_1to2",
    336: "radar_mission_cops_2",
    337: "radar_mission_cops_2to4",
    338: "radar_mission_cops_2to8",
    339: "radar_mission_cops_2to12",
    340: "radar_mission_cops_2to16",
    341: "radar_mission_vagos_1",
    342: "radar_mission_vagos_1to2",
    343: "radar_mission_vagos_2",
    344: "radar_mission_vagos_2to4",
    345: "radar_mission_vagos_2to8",
    346: "radar_mission_vagos_2to12",
    347: "radar_mission_vagos_2to16",
    348: "radar_gang_bike",
    349: "radar_gas_grenade",
    350: "radar_property_for_sale",
    351: "radar_gang_attack_package",
    352: "radar_martin_madrazzo",
    353: "radar_enemy_heli_spin",
    354: "radar_boost",
    355: "radar_devin",
    356: "radar_dock",
    357: "radar_garage",
    358: "radar_golf_flag",
    359: "radar_hangar",
    360: "radar_helipad",
    361: "radar_jerry_can",
    362: "radar_mask",
    363: "radar_heist_prep",
    364: "radar_incapacitated",
    365: "radar_spawn_point_pickup",
    366: "radar_boilersuit",
    367: "radar_completed",
    368: "radar_rockets",
    369: "radar_garage_for_sale",
    370: "radar_helipad_for_sale",
    371: "radar_dock_for_sale",
    372: "radar_hangar_for_sale",
    373: "radar_placeholder_6",
    374: "radar_business",
    375: "radar_business_for_sale",
    376: "radar_race_bike",
    377: "radar_parachute",
    378: "radar_team_deathmatch",
    379: "radar_race_foot",
    380: "radar_vehicle_deathmatch",
    381: "radar_barry",
    382: "radar_dom",
    383: "radar_maryann",
    384: "radar_cletus",
    385: "radar_josh",
    386: "radar_minute",
    387: "radar_omega",
    388: "radar_tonya",
    389: "radar_paparazzo",
    390: "radar_aim",
    391: "radar_cratedrop_background",
    392: "radar_green_and_net_player1",
    393: "radar_green_and_net_player2",
    394: "radar_green_and_net_player3",
    395: "radar_green_and_friendly",
    396: "radar_net_player1_and_net_player2",
    397: "radar_net_player1_and_net_player3",
    398: "radar_creator",
    399: "radar_creator_direction",
    400: "radar_abigail",
    401: "radar_blimp",
    402: "radar_repair",
    403: "radar_testosterone",
    404: "radar_dinghy",
    405: "radar_fanatic",
    407: "radar_info_icon",
    408: "radar_capture_the_flag",
    409: "radar_last_team_standing",
    410: "radar_boat",
    411: "radar_capture_the_flag_base",
    412: "radar_mp_crew",
    413: "radar_capture_the_flag_outline",
    414: "radar_capture_the_flag_base_nobag",
    415: "radar_weapon_jerrycan",
    416: "radar_rp",
    417: "radar_level_inside",
    418: "radar_bounty_hit_inside",
    419: "radar_capture_the_usaflag",
    420: "radar_capture_the_usaflag_outline",
    421: "radar_tank",
    422: "radar_player_heli",
    423: "radar_player_plane",
    424: "radar_player_jet",
    425: "radar_centre_stroke",
    426: "radar_player_guncar",
    427: "radar_player_boat",
    428: "radar_mp_heist",
    429: "radar_temp_1",
    430: "radar_temp_2",
    431: "radar_temp_3",
    432: "radar_temp_4",
    433: "radar_temp_5",
    434: "radar_temp_6",
    435: "radar_race_stunt",
    436: "radar_hot_property",
    437: "radar_urbanwarfare_versus",
    438: "radar_king_of_the_castle",
    439: "radar_player_king",
    440: "radar_dead_drop",
    441: "radar_penned_in",
    442: "radar_beast",
    443: "radar_edge_pointer",
    444: "radar_edge_crosstheline",
    445: "radar_mp_lamar",
    446: "radar_bennys",
    447: "radar_corner_number_1",
    448: "radar_corner_number_2",
    449: "radar_corner_number_3",
    450: "radar_corner_number_4",
    451: "radar_corner_number_5",
    452: "radar_corner_number_6",
    453: "radar_corner_number_7",
    454: "radar_corner_number_8",
    455: "radar_yacht",
    456: "radar_finders_keepers",
    457: "radar_assault_package",
    458: "radar_hunt_the_boss",
    459: "radar_sightseer",
    460: "radar_turreted_limo",
    461: "radar_belly_of_the_beast",
    462: "radar_yacht_location",
    463: "radar_pickup_beast",
    464: "radar_pickup_zoned",
    465: "radar_pickup_random",
    466: "radar_pickup_slow_time",
    467: "radar_pickup_swap",
    468: "radar_pickup_thermal",
    469: "radar_pickup_weed",
    470: "radar_weapon_railgun",
    471: "radar_seashark",
    472: "radar_pickup_hidden",
    473: "radar_warehouse",
    474: "radar_warehouse_for_sale",
    475: "radar_office",
    476: "radar_office_for_sale",
    477: "radar_truck",
    478: "radar_contraband",
    479: "radar_trailer",
    480: "radar_vip",
    481: "radar_cargobob",
    482: "radar_area_outline_blip",
    483: "radar_pickup_accelerator",
    484: "radar_pickup_ghost",
    485: "radar_pickup_detonator",
    486: "radar_pickup_bomb",
    487: "radar_pickup_armoured",
    488: "radar_stunt",
    489: "radar_weapon_lives",
    490: "radar_stunt_premium",
    491: "radar_adversary",
    492: "radar_biker_clubhouse",
    493: "radar_biker_caged_in",
    494: "radar_biker_turf_war",
    495: "radar_biker_joust",
    496: "radar_production_weed",
    497: "radar_production_crack",
    498: "radar_production_fake_id",
    499: "radar_production_meth",
    500: "radar_production_money",
    501: "radar_package",
    502: "radar_capture_1",
    503: "radar_capture_2",
    504: "radar_capture_3",
    505: "radar_capture_4",
    506: "radar_capture_5",
    507: "radar_capture_6",
    508: "radar_capture_7",
    509: "radar_capture_8",
    510: "radar_capture_9",
    511: "radar_capture_10",
    512: "radar_quad",
    513: "radar_bus",
    514: "radar_drugs_package",
    515: "radar_pickup_jump",
    516: "radar_adversary_4",
    517: "radar_adversary_8",
    518: "radar_adversary_10",
    519: "radar_adversary_12",
    520: "radar_adversary_16",
    521: "radar_laptop",
    522: "radar_pickup_deadline",
    523: "radar_sports_car",
    524: "radar_warehouse_vehicle",
    525: "radar_reg_papers",
    526: "radar_police_station_dropoff",
    527: "radar_junkyard",
    528: "radar_ex_vech_1",
    529: "radar_ex_vech_2",
    530: "radar_ex_vech_3",
    531: "radar_ex_vech_4",
    532: "radar_ex_vech_5",
    533: "radar_ex_vech_6",
    534: "radar_ex_vech_7",
    535: "radar_target_a",
    536: "radar_target_b",
    537: "radar_target_c",
    538: "radar_target_d",
    539: "radar_target_e",
    540: "radar_target_f",
    541: "radar_target_g",
    542: "radar_target_h",
    543: "radar_jugg",
    544: "radar_pickup_repair",
    545: "radar_steeringwheel",
    546: "radar_trophy",
    547: "radar_pickup_rocket_boost",
    548: "radar_pickup_homing_rocket",
    549: "radar_pickup_machinegun",
    550: "radar_pickup_parachute",
    551: "radar_pickup_time_5",
    552: "radar_pickup_time_10",
    553: "radar_pickup_time_15",
    554: "radar_pickup_time_20",
    555: "radar_pickup_time_30",
    556: "radar_supplies",
    557: "radar_property_bunker",
    558: "radar_gr_wvm_1",
    559: "radar_gr_wvm_2",
    560: "radar_gr_wvm_3",
    561: "radar_gr_wvm_4",
    562: "radar_gr_wvm_5",
    563: "radar_gr_wvm_6",
    564: "radar_gr_covert_ops",
    565: "radar_adversary_bunker",
    566: "radar_gr_moc_upgrade",
    567: "radar_gr_w_upgrade",
    568: "radar_sm_cargo",
    569: "radar_sm_hangar",
    570: "radar_tf_checkpoint",
    571: "radar_race_tf",
    572: "radar_sm_wp1",
    573: "radar_sm_wp2",
    574: "radar_sm_wp3",
    575: "radar_sm_wp4",
    576: "radar_sm_wp5",
    577: "radar_sm_wp6",
    578: "radar_sm_wp7",
    579: "radar_sm_wp8",
    580: "radar_sm_wp9",
    581: "radar_sm_wp10",
    582: "radar_sm_wp11",
    583: "radar_sm_wp12",
    584: "radar_sm_wp13",
    585: "radar_sm_wp14",
    586: "radar_nhp_bag",
    587: "radar_nhp_chest",
    588: "radar_nhp_orbit",
    589: "radar_nhp_veh1",
    590: "radar_nhp_base",
    591: "radar_nhp_overlay",
    592: "radar_nhp_turret",
    593: "radar_nhp_mg_firewall",
    594: "radar_nhp_mg_node",
    595: "radar_nhp_wp1",
    596: "radar_nhp_wp2",
    597: "radar_nhp_wp3",
    598: "radar_nhp_wp4",
    599: "radar_nhp_wp5",
    600: "radar_nhp_wp6",
    601: "radar_nhp_wp7",
    602: "radar_nhp_wp8",
    603: "radar_nhp_wp9",
    604: "radar_nhp_cctv",
    605: "radar_nhp_starterpack",
    606: "radar_nhp_turret_console",
    607: "radar_nhp_mg_mir_rotate",
    608: "radar_nhp_mg_mir_static",
    609: "radar_nhp_mg_proxy",
    610: "radar_acsr_race_target",
    611: "radar_acsr_race_hotring",
    612: "radar_acsr_wp1",
    613: "radar_acsr_wp2",
    614: "radar_bat_club_property",
    615: "radar_bat_cargo",
    616: "radar_bat_truck",
    617: "radar_bat_hack_jewel",
    618: "radar_bat_hack_gold",
    619: "radar_bat_keypad",
    620: "radar_bat_hack_target",
    621: "radar_pickup_dtb_health",
    622: "radar_pickup_dtb_blast_increase",
    623: "radar_pickup_dtb_blast_decrease",
    624: "radar_pickup_dtb_bomb_increase",
    625: "radar_pickup_dtb_bomb_decrease",
    626: "radar_bat_rival_club",
    627: "radar_bat_drone",
    628: "radar_bat_cash_reg",
    629: "radar_cctv",
    630: "radar_bat_assassinate",
    631: "radar_bat_pbus",
    632: "radar_bat_wp1",
    633: "radar_bat_wp2",
    634: "radar_bat_wp3",
    635: "radar_bat_wp4",
    636: "radar_bat_wp5",
    637: "radar_bat_wp6",
    638: "radar_blimp_2",
    639: "radar_oppressor_2",
    640: "radar_bat_wp7",
    641: "radar_arena_series",
    642: "radar_arena_premium",
    643: "radar_arena_workshop",
    644: "radar_race_wars",
    645: "radar_arena_turret",
    646: "radar_arena_rc_car",
    647: "radar_arena_rc_workshop",
    648: "radar_arena_trap_fire",
    649: "radar_arena_trap_flip",
    650: "radar_arena_trap_sea",
    651: "radar_arena_trap_turn",
    652: "radar_arena_trap_pit",
    653: "radar_arena_trap_mine",
    654: "radar_arena_trap_bomb",
    655: "radar_arena_trap_wall",
    656: "radar_arena_trap_brd",
    657: "radar_arena_trap_sbrd",
    658: "radar_arena_bruiser",
    659: "radar_arena_brutus",
    660: "radar_arena_cerberus",
    661: "radar_arena_deathbike",
    662: "radar_arena_dominator",
    663: "radar_arena_impaler",
    664: "radar_arena_imperator",
    665: "radar_arena_issi",
    666: "radar_arena_sasquatch",
    667: "radar_arena_scarab",
    668: "radar_arena_slamvan",
    669: "radar_arena_zr380",
    670: "radar_ap",
    671: "radar_comic_store",
    672: "radar_cop_car",
    673: "radar_rc_time_trials",
    674: "radar_king_of_the_hill",
    675: "radar_king_of_the_hill_teams",
    676: "radar_rucksack",
    677: "radar_shipping_container",
    678: "radar_agatha",
    679: "radar_casino",
    680: "radar_casino_table_games",
    681: "radar_casino_wheel",
    682: "radar_casino_concierge",
    683: "radar_casino_chips",
    684: "radar_casino_horse_racing",
    685: "radar_adversary_featured",
    686: "radar_roulette_1",
    687: "radar_roulette_2",
    688: "radar_roulette_3",
    689: "radar_roulette_4",
    690: "radar_roulette_5",
    691: "radar_roulette_6",
    692: "radar_roulette_7",
    693: "radar_roulette_8",
    694: "radar_roulette_9",
    695: "radar_roulette_10",
    696: "radar_roulette_11",
    697: "radar_roulette_12",
    698: "radar_roulette_13",
    699: "radar_roulette_14",
    700: "radar_roulette_15",
    701: "radar_roulette_16",
    702: "radar_roulette_17",
    703: "radar_roulette_18",
    704: "radar_roulette_19",
    705: "radar_roulette_20",
    706: "radar_roulette_21",
    707: "radar_roulette_22",
    708: "radar_roulette_23",
    709: "radar_roulette_24",
    710: "radar_roulette_25",
    711: "radar_roulette_26",
    712: "radar_roulette_27",
    713: "radar_roulette_28",
    714: "radar_roulette_29",
    715: "radar_roulette_30",
    716: "radar_roulette_31",
    717: "radar_roulette_32",
    718: "radar_roulette_33",
    719: "radar_roulette_34",
    720: "radar_roulette_35",
    721: "radar_roulette_36",
    722: "radar_roulette_0",
    723: "radar_roulette_00",
    724: "radar_limo",
    725: "radar_weapon_alien",
    726: "radar_race_open_wheel",
    727: "radar_rappel",
    728: "radar_swap_car",
    729: "radar_scuba_gear",
    730: "radar_cpanel_1",
    731: "radar_cpanel_2",
    732: "radar_cpanel_3",
    733: "radar_cpanel_4",
    734: "radar_snow_truck",
    735: "radar_buggy_1",
    736: "radar_buggy_2",
    737: "radar_zhaba",
    738: "radar_gerald",
    739: "radar_ron",
    740: "radar_arcade",
    741: "radar_drone_controls",
    742: "radar_rc_tank",
    743: "radar_stairs",
    744: "radar_camera_2",
    745: "radar_winky",
    746: "radar_mini_sub",
    747: "radar_kart_retro",
    748: "radar_kart_modern",
    749: "radar_military_quad",
    750: "radar_military_truck",
    751: "radar_ship_wheel",
    752: "radar_ufo",
    753: "radar_seasparrow2",
    754: "radar_dinghy2",
    755: "radar_patrol_boat",
    756: "radar_retro_sports_car",
    757: "radar_squadee",
    758: "radar_folding_wing_jet",
    759: "radar_valkyrie2",
    760: "radar_sub2",
    761: "radar_bolt_cutters",
    762: "radar_rappel_gear",
    763: "radar_keycard",
    764: "radar_password",
    765: "radar_island_heist_prep",
    766: "radar_island_party",
    767: "radar_control_tower",
    768: "radar_underwater_gate",
    769: "radar_power_switch",
    770: "radar_compound_gate",
    771: "radar_rappel_point",
    772: "radar_keypad",
    773: "radar_sub_controls",
    774: "radar_sub_periscope",
    775: "radar_sub_missile",
    776: "radar_painting",
    777: "radar_car_meet",
    778: "radar_car_test_area",
    779: "radar_auto_shop_property",
    780: "radar_docks_export",
    781: "radar_prize_car",
    782: "radar_test_car",
    783: "radar_car_robbery_board",
    784: "radar_car_robbery_prep",
    785: "radar_street_race_series",
    786: "radar_pursuit_series",
    787: "radar_car_meet_organiser",
    788: "radar_securoserv",
    789: "radar_bounty_collectibles",
    790: "radar_movie_collectibles",
    791: "radar_trailer_ramp",
    792: "radar_race_organiser",
    793: "radar_chalkboard_list",
    794: "radar_export_vehicle",
    795: "radar_train",
    796: "radar_heist_diamond",
    797: "radar_heist_doomsday",
    798: "radar_heist_island",
    799: "radar_slamvan2",
    800: "radar_crusader",
    801: "radar_construction_outfit",
    802: "radar_overlay_jammed",
    803: "radar_heist_island_unavailable",
    804: "radar_heist_diamond_unavailable",
    805: "radar_heist_doomsday_unavailable",
    806: "radar_placeholder_7",
    807: "radar_placeholder_8",
    808: "radar_placeholder_9",
    809: "radar_featured_series",
    810: "radar_vehicle_for_sale",
    811: "radar_van_keys",
    812: "radar_suv_service",
    813: "radar_security_contract",
    814: "radar_safe",
    815: "radar_ped_r",
    816: "radar_ped_e",
    817: "radar_payphone",
    818: "radar_patriot3",
    819: "radar_music_studio",
    820: "radar_jubilee",
    821: "radar_granger2",
    822: "radar_explosive_charge",
    823: "radar_deity",
    824: "radar_d_champion",
    825: "radar_buffalo4",
    826: "radar_agency",
    827: "radar_biker_bar",
    828: "radar_simeon_overlay",
    829: "radar_junk_skydive",
    830: "radar_luxury_car_showroom",
    831: "radar_car_showroom",
    832: "radar_car_showroom_simeon",
    833: "radar_flaming_skull",
    834: "radar_weapon_ammo",
    835: "radar_community_series",
    836: "radar_cayo_series",
    837: "radar_clubhouse_contract",
    838: "radar_agent_ulp",
    839: "radar_acid",
    840: "radar_acid_lab",
    841: "radar_dax_overlay",
    842: "radar_dead_drop_package",
    843: "radar_downtown_cab",
    844: "radar_gun_van",
    845: "radar_stash_house",
    846: "radar_tractor",
    847: "radar_warehouse_juggalo",
    848: "radar_warehouse_juggalo_dax",
    849: "radar_weapon_crowbar",
    850: "radar_duffel_bag",
    851: "radar_oil_tanker",
    852: "radar_acid_lab_tent",
    853: "radar_van_burrito",
    854: "radar_acid_boost",
    855: "radar_ped_gang_leader",
    856: "radar_multistorey_garage",
    857: "radar_seized_asset_sales",
    858: "radar_cayo_attrition",
    859: "radar_bicycle",
    860: "radar_bicycle_trial",
    861: "radar_raiju",
    862: "radar_conada2",
    863: "radar_overlay_ready_for_sell",
    864: "radar_overlay_missing_supplies",
    865: "radar_streamer216",
    866: "radar_signal_jammer",
    867: "radar_salvage_yard",
    868: "radar_robbery_prep_equipment",
    869: "radar_robbery_prep_overlay",
    870: "radar_yusuf",
    871: "radar_vincent",
    872: "radar_vinewood_garage",
    873: "radar_lstb",
    874: "radar_cctv_workstation",
    875: "radar_hacking_device",
    876: "radar_race_drag",
    877: "radar_race_drift",
    878: "radar_casino_prep",
    879: "radar_planning_wall",
    880: "radar_weapon_crate",
    881: "radar_weapon_snowball",
    882: "radar_train_signals_green",
    883: "radar_train_signals_red",
    884: "radar_office_transporter",
    885: "radar_yankton_survival",
    886: "radar_daily_bounty",
    887: "radar_bounty_target",
    888: "radar_filming_schedule",
    889: "radar_pizza_this",
    890: "radar_aircraft_carrier",
    891: "radar_weapon_emp",
    892: "radar_maude_eccles",
    893: "radar_bail_bonds_office",
    894: "radar_weapon_emp_mine",
    895: "radar_zombie_disease",
    896: "radar_zombie_proximity",
    897: "radar_zombie_fire",
    898: "radar_animal_possessed",
    899: "radar_mobile_phone",
    900: "radar_garment_factory",
    901: "radar_garment_factory_for_sale",
    902: "radar_garment_factory_equipment",
    903: "radar_field_hangar",
    904: "radar_field_hangar_for_sale",
    905: "radar_cargobob_ch53",
    906: "radar_chopper_lift_ammo",
    907: "radar_chopper_lift_armor",
    908: "radar_chopper_lift_explosives",
    909: "radar_chopper_lift_upgrade",
    910: "radar_chopper_lift_weapon",
    911: "radar_cargo_ship",
    912: "radar_submarine_missile",
    913: "radar_propeller_engine",
    914: "radar_shark",
    915: "radar_fast_travel",
    916: "radar_plane_duster2",
    917: "radar_plane_titan2",
    918: "radar_collectible",
    919: "radar_field_hangar_discount",
    920: "radar_garment_factory_discount",
    921: "radar_weapon_gusenberg_sweeper",
    922: "radar_weapon_tear_gas",
    923: "radar_dog",
    924: "radar_bobcat_security",
    925: "radar_smoke_shop",
    926: "radar_smoke_shop_for_sale",
    927: "radar_smoke_shop_attention",
    928: "radar_helitours",
    929: "radar_helitours_for_sale",
    930: "radar_helitours_attention",
    931: "radar_car_wash_business",
    932: "radar_car_wash_business_for_sale",
    933: "radar_car_wash_business_attention",
    934: "radar_attention",
    935: "radar_alarm",
    936: "radar_helitours_discount",
    937: "radar_smoke_shop_discount",
    938: "radar_car_wash_business_discount",
    939: "radar_real_estate",
    940: "radar_medical_courier",
    941: "radar_gruppe_sechs",
    942: "radar_fire_station",
    943: "radar_fire_truck",
    944: "radar_alpha_mail",
    945: "radar_ls_meteor",
    946: "radar_four20_survival",
    947: "radar_community_mission_series",
    948: "radar_property_mansion",
    949: "radar_ai_keypad",
    950: "radar_taxi_self_drive",
    951: "radar_train_subway",
    952: "radar_trashbag",
    953: "radar_mission_creator",
    954: "radar_cat",
    955: "radar_mansion_ai_m",
    956: "radar_mansion_ai_f",
    957: "radar_mansion_ai_gang",
  };

  const BLIP_IDS = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 27, 28, 36, 37,
    38, 40, 41, 42, 43, 44, 47, 48, 50, 51, 52, 54, 56, 57, 58, 59, 60, 61, 62,
    63, 64, 66, 67, 68, 70, 71, 72, 73, 75, 76, 77, 78, 79, 80, 82, 84, 85, 86,
    88, 89, 90, 91, 92, 93, 94, 95, 96, 99, 100, 102, 103, 104, 105, 106, 107,
    108, 109, 110, 111, 112, 113, 114, 115, 118, 119, 120, 121, 122, 123, 124,
    126, 127, 128, 129, 130, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142,
    143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157,
    158, 159, 160, 161, 162, 163, 164, 171, 173, 175, 176, 177, 178, 179, 180,
    181, 182, 183, 184, 185, 186, 187, 188, 189, 192, 193, 194, 197, 198, 205,
    206, 207, 208, 209, 210, 211, 212, 213, 214, 225, 226, 227, 228, 229, 230,
    231, 232, 233, 234, 235, 236, 237, 238, 251, 252, 253, 254, 255, 256, 262,
    263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277,
    278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292,
    293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307,
    308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322,
    323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337,
    338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352,
    353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367,
    368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382,
    383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397,
    398, 399, 400, 401, 402, 403, 404, 405, 407, 408, 409, 410, 411, 412, 413,
    414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428,
    429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443,
    444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458,
    459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473,
    474, 475, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488,
    489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503,
    504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518,
    519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533,
    534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548,
    549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563,
    564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576, 577, 578,
    579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593,
    594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608,
    609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623,
    624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638,
    639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653,
    654, 655, 656, 657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668,
    669, 670, 671, 672, 673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683,
    684, 685, 686, 687, 688, 689, 690, 691, 692, 693, 694, 695, 696, 697, 698,
    699, 700, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710, 711, 712, 713,
    714, 715, 716, 717, 718, 719, 720, 721, 722, 723, 724, 725, 726, 727, 728,
    729, 730, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 741, 742, 743,
    744, 745, 746, 747, 748, 749, 750, 751, 752, 753, 754, 755, 756, 757, 758,
    759, 760, 761, 762, 763, 764, 765, 766, 767, 768, 769, 770, 771, 772, 773,
    774, 775, 776, 777, 778, 779, 780, 781, 782, 783, 784, 785, 786, 787, 788,
    789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799, 800, 801, 802, 803,
    804, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816, 817, 818,
    819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 833,
    834, 835, 836, 837, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848,
    849, 850, 851, 852, 853, 854, 855, 856, 857, 858, 859, 860, 861, 862, 863,
    864, 865, 866, 867, 868, 869, 870, 871, 872, 873, 874, 875, 876, 877, 878,
    879, 880, 881, 882, 883, 884, 885, 886, 887, 888, 889, 890, 891, 892, 893,
    894, 895, 896, 897, 898, 899, 900, 901, 902, 903, 904, 905, 906, 907, 908,
    909, 910, 911, 912, 913, 914, 915, 916, 917, 918, 919, 920, 921, 922, 923,
    924, 925, 926, 927, 928, 929, 930, 931, 932, 933, 934, 935, 936, 937, 938,
    939, 940, 941, 942, 943, 944, 945, 946, 947, 948, 949, 950, 951, 952, 953,
    954, 955, 956, 957,
  ];

  const BLIP_IMG_BASE = "https://docs.fivem.net/blips/";

  function getBlipImgUrl(spriteId) {
    const name = BLIP_SPRITES[spriteId];
    if (!name) return null;
    return BLIP_IMG_BASE + name + ".png";
  }
  function getBlipSpriteName(spriteId) {
    const name = BLIP_SPRITES[spriteId];
    if (!name) return "Sprite " + spriteId;
    return name.replace("radar_", "").replace(/_/g, " ");
  }

  function nearestBlipId(id, direction) {
    const idx = BLIP_IDS.indexOf(id);
    if (idx === -1) {
      const next = BLIP_IDS.find((i) => i >= id);
      return next ?? BLIP_IDS[BLIP_IDS.length - 1];
    }
    return BLIP_IDS[
      Math.max(0, Math.min(BLIP_IDS.length - 1, idx + direction))
    ];
  }

  function updateBlipPreview() {
    const spriteId = parseInt(spriteEl?.value || 477);
    const colorId = parseInt(bcolorEl?.value || 2);
    const colorDef = BLIP_COLORS[colorId] || ["#aaaaaa", "Unbekannt"];

    const preview = document.getElementById("ze-blip-preview");
    const nameEl = document.getElementById("ze-blip-name");
    const cnEl = document.getElementById("ze-blip-colorname");

    if (preview) {
      preview.style.background = colorDef[0];
      const imgUrl = getBlipImgUrl(spriteId);
      if (imgUrl) {
        preview.innerHTML = `<img src="${imgUrl}" style="width:22px;height:22px;object-fit:contain;filter:brightness(0) invert(1)" onerror="this.style.display='none';this.parentElement.textContent='?'">`;
      } else {
        preview.textContent = "?";
      }
    }
    if (nameEl) nameEl.textContent = getBlipSpriteName(spriteId);
    if (cnEl) cnEl.textContent = colorDef[1];

    document.querySelectorAll(".ze-color-swatch").forEach((s) => {
      s.classList.toggle("active", parseInt(s.dataset.id) === colorId);
    });
  }

  function buildColorPalette() {
    const container = document.getElementById("ze-color-palette");
    if (!container) return;
    Object.entries(BLIP_COLORS).forEach(([id, [hex, name]]) => {
      const swatch = document.createElement("div");
      swatch.className = "ze-color-swatch";
      swatch.style.background = hex;
      swatch.dataset.id = id;
      swatch.title = `${name} (${id})`;
      swatch.addEventListener("click", () => {
        bcolorEl.value = id;
        document.getElementById("ze-bcolor-val").textContent = id;
        updateBlipPreview();
        sendChange();
      });
      container.appendChild(swatch);
    });
  }
  buildColorPalette();

  function getBlipData() {
    if (noblipEl && noblipEl.checked) return null;
    return {
      sprite: parseInt(spriteEl?.value || 477),
      color: parseInt(bcolorEl?.value || 2),
      scale: 0.85,
    };
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
        blip: getBlipData(),
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
  function setSprite(id) {
    spriteEl.value = id;
    document.getElementById("ze-sprite-val").textContent = id;
    const nameEl2 = document.getElementById("ze-sprite-name");
    if (nameEl2) nameEl2.textContent = getBlipSpriteName(id);
    updateTrack(spriteEl);
    updateBlipPreview();
    sendChange();
  }

  spriteEl?.addEventListener("input", () => {
    const snapped = nearestBlipId(parseInt(spriteEl.value), 0);
    setSprite(snapped);
  });
  document.getElementById("ze-sprite-prev")?.addEventListener("click", () => {
    setSprite(nearestBlipId(parseInt(spriteEl.value), -1));
  });
  document.getElementById("ze-sprite-next")?.addEventListener("click", () => {
    setSprite(nearestBlipId(parseInt(spriteEl.value), 1));
  });
  labelEl.addEventListener("input", sendChange);
  if (noblipEl)
    noblipEl.addEventListener("change", () => {
      updateBlipPreview();
      sendChange();
    });

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
        blip: getBlipData(),
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
      // Blip-Felder
      const blip = d.blip;
      const initSprite = blip?.sprite ?? 477;
      if (spriteEl) spriteEl.value = initSprite;
      if (bcolorEl) bcolorEl.value = blip?.color ?? 2;
      if (noblipEl) noblipEl.checked = !blip;
      document.getElementById("ze-sprite-val").textContent = initSprite;
      document.getElementById("ze-bcolor-val").textContent =
        bcolorEl?.value || 2;
      const sn = document.getElementById("ze-sprite-name");
      if (sn) sn.textContent = getBlipSpriteName(initSprite);
      [sxEl, syEl, szEl, rotEl, spriteEl].forEach(updateTrack);
      updateBlipPreview();
      panel.classList.add("visible");
    }

    if (d.action === "closeZoneEditor") {
      panel.classList.remove("visible");
    }
  });
})();

// ════════════════════════════════════════════════════════
//  COMPANY PANEL
// ════════════════════════════════════════════════════════
(function () {
  const panel = document.getElementById("company-panel");
  const overlay = panel.querySelector(".cp-overlay");
  const closeBtn = document.getElementById("cp-close");
  const tabs = panel.querySelectorAll(".cp-tab");
  const panes = panel.querySelectorAll(".cp-pane");

  let currentData = null;

  // ── Helpers ─────────────────────────────────────────
  function fmt(n) {
    return "$" + Math.abs(n).toLocaleString("de-DE");
  }
  function roleLabel(role) {
    return role === "owner"
      ? "OWNER"
      : role === "manager"
        ? "MANAGER"
        : "FAHRER";
  }
  function roleCls(role) {
    return role === "owner" ? "" : role === "manager" ? "manager" : "driver";
  }

  // ── Tab switching ────────────────────────────────────
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      if (tab.classList.contains("hidden")) return;
      tabs.forEach((t) => t.classList.remove("active"));
      panes.forEach((p) => p.classList.remove("active"));
      tab.classList.add("active");
      document
        .getElementById("cp-pane-" + tab.dataset.tab)
        ?.classList.add("active");
    });
  });

  // ── Close ────────────────────────────────────────────
  function closePanel() {
    panel.classList.add("hidden");
    fetch("https://motortown/companyClose", {
      method: "POST",
      body: JSON.stringify({}),
    });
  }
  closeBtn.addEventListener("click", closePanel);
  overlay.addEventListener("click", closePanel);

  // ── Render: Overview ─────────────────────────────────
  function renderOverview(data) {
    const noComp = document.getElementById("cp-no-company");
    const statsGrid = panel.querySelector(".cp-stats-grid");

    if (!data.membership) {
      statsGrid.classList.add("hidden");
      noComp.classList.remove("hidden");
      return;
    }
    statsGrid.classList.remove("hidden");
    noComp.classList.add("hidden");

    const activeRoutes = (data.routes || []).filter(
      (r) => r.active === 1,
    ).length;
    document.getElementById("cp-balance").textContent = fmt(
      data.company.balance,
    );
    document.getElementById("cp-members-count").textContent =
      data.members?.length || 0;
    document.getElementById("cp-routes-count").textContent = activeRoutes;
    document.getElementById("cp-reputation").textContent =
      data.company.reputation || 0;
  }

  // ── Render: Members ──────────────────────────────────
  function renderMembers(data) {
    const list = document.getElementById("cp-members-list");
    list.innerHTML = "";
    if (!data.members || data.members.length === 0) {
      list.innerHTML =
        '<div style="color:rgba(255,255,255,0.3);font-size:13px;text-align:center;padding:20px">Keine Mitglieder</div>';
      return;
    }
    const myRole = data.membership?.role;
    data.members.forEach((m) => {
      const canManage = myRole !== "driver" && m.role !== "owner";
      const item = document.createElement("div");
      item.className = "cp-list-item";
      item.innerHTML = `
                <div class="cp-list-icon">👤</div>
                <div class="cp-list-info">
                    <div class="cp-list-name">${m.name}</div>
                    <div class="cp-list-sub">${roleLabel(m.role)}</div>
                </div>
                <div class="cp-list-actions">
                    ${canManage && m.role === "driver" ? `<button class="cp-btn cp-btn-icon" data-action="promote" data-id="${m.identifier}">↑ Befördern</button>` : ""}
                    ${canManage ? `<button class="cp-btn cp-btn-icon danger" data-action="kick" data-id="${m.identifier}">Raus</button>` : ""}
                </div>`;
      list.appendChild(item);
    });

    list.querySelectorAll("[data-action]").forEach((btn) => {
      btn.addEventListener("click", () => {
        fetch("https://motortown/companyAction", {
          method: "POST",
          body: JSON.stringify({
            action: btn.dataset.action,
            identifier: btn.dataset.id,
          }),
        });
      });
    });
  }

  // ── Render: Routes ───────────────────────────────────
  function renderRoutes(data) {
    const list = document.getElementById("cp-routes-list");
    const addBtn = document.getElementById("cp-route-add-btn");
    const myRole = data.membership?.role;
    list.innerHTML = "";

    if (!data.routes || data.routes.length === 0) {
      list.innerHTML =
        '<div style="color:rgba(255,255,255,0.3);font-size:13px;text-align:center;padding:16px">Keine Routen vorhanden</div>';
    } else {
      data.routes.forEach((r) => {
        const isActive = r.active === 1;
        const item = document.createElement("div");
        item.className = "cp-list-item";
        item.innerHTML = `
                    <div class="cp-route-dot ${isActive ? "active" : "paused"}"></div>
                    <div class="cp-list-info">
                        <div class="cp-list-name">${r.jobLabel || r.route_type}</div>
                        <div class="cp-list-sub">${r.plate ? (r.model || "?") + " · " + r.plate : "Kein Fahrzeug"}</div>
                    </div>
                    <div class="cp-list-actions">
                        ${myRole !== "driver" ? `<button class="cp-btn cp-btn-icon" data-action="toggle" data-id="${r.id}">${isActive ? "⏸ Pause" : "▶ Start"}</button>` : ""}
                    </div>`;
        list.appendChild(item);
      });
      list.querySelectorAll('[data-action="toggle"]').forEach((btn) => {
        btn.addEventListener("click", () => {
          fetch("https://motortown/companyAction", {
            method: "POST",
            body: JSON.stringify({
              action: "toggle_route",
              routeId: parseInt(btn.dataset.id),
            }),
          });
        });
      });
    }
    addBtn.style.display = myRole !== "driver" ? "" : "none";
  }

  // ── Route form ───────────────────────────────────────
  document.getElementById("cp-route-add-btn").addEventListener("click", () => {
    document.getElementById("cp-route-form").classList.remove("hidden");
    document.getElementById("cp-route-add-btn").style.display = "none";
  });
  document.getElementById("cp-route-cancel").addEventListener("click", () => {
    document.getElementById("cp-route-form").classList.add("hidden");
    document.getElementById("cp-route-add-btn").style.display = "";
  });
  document.getElementById("cp-route-create").addEventListener("click", () => {
    const type = document.getElementById("cp-route-type").value;
    const vehId = parseInt(document.getElementById("cp-route-vehicle").value);
    if (!type || !vehId) return;
    fetch("https://motortown/companyAction", {
      method: "POST",
      body: JSON.stringify({
        action: "create_route",
        routeType: type,
        vehicleId: vehId,
      }),
    });
    document.getElementById("cp-route-form").classList.add("hidden");
  });

  // ── Finance ──────────────────────────────────────────
  document.getElementById("cp-deposit-btn").addEventListener("click", () => {
    const amt = parseFloat(document.getElementById("cp-deposit-amount").value);
    if (!amt || amt <= 0) return;
    fetch("https://motortown/companyAction", {
      method: "POST",
      body: JSON.stringify({ action: "deposit", amount: amt }),
    });
    document.getElementById("cp-deposit-amount").value = "";
  });
  document.getElementById("cp-withdraw-btn").addEventListener("click", () => {
    const amt = parseFloat(document.getElementById("cp-withdraw-amount").value);
    if (!amt || amt <= 0) return;
    fetch("https://motortown/companyAction", {
      method: "POST",
      body: JSON.stringify({ action: "withdraw", amount: amt }),
    });
    document.getElementById("cp-withdraw-amount").value = "";
  });

  // ── Found company ────────────────────────────────────
  document.getElementById("cp-found-btn").addEventListener("click", () => {
    const name = document.getElementById("cp-found-name").value.trim();
    if (!name) return;
    fetch("https://motortown/companyAction", {
      method: "POST",
      body: JSON.stringify({ action: "found", name }),
    });
  });

  // ── Open panel ───────────────────────────────────────
  function openPanel(data) {
    currentData = data;

    // Header
    document.getElementById("cp-name").textContent =
      data.company?.name || "Neue Firma";
    const badge = document.getElementById("cp-role");
    badge.textContent = roleLabel(data.membership?.role);
    badge.className = "cp-role-badge " + roleCls(data.membership?.role);

    // Tab visibility
    const canManage = data.membership && data.membership.role !== "driver";
    const isOwner = data.membership?.role === "owner";
    document
      .getElementById("cp-tab-members")
      .classList.toggle("hidden", !canManage);
    document.getElementById("cp-tab-routes").classList.toggle("hidden", false);
    document
      .getElementById("cp-tab-finance")
      .classList.toggle("hidden", !isOwner);

    // Reset to overview tab
    tabs.forEach((t) => t.classList.remove("active"));
    panes.forEach((p) => p.classList.remove("active"));
    panel.querySelector('[data-tab="overview"]').classList.add("active");
    document.getElementById("cp-pane-overview").classList.add("active");

    // Populate route type select
    const sel = document.getElementById("cp-route-type");
    sel.innerHTML = "";
    if (data.jobs) {
      data.jobs.forEach((j) => {
        const opt = document.createElement("option");
        opt.value = j.key;
        opt.textContent = j.label;
        sel.appendChild(opt);
      });
    }

    // Finance balance
    document.getElementById("cp-finance-balance").textContent = fmt(
      data.company?.balance || 0,
    );

    // Render all panes
    renderOverview(data);
    renderMembers(data);
    renderRoutes(data);

    panel.classList.remove("hidden");
  }

  // ── Update balance live ──────────────────────────────
  function updateBalance(balance) {
    document.getElementById("cp-balance").textContent = fmt(balance);
    document.getElementById("cp-finance-balance").textContent = fmt(balance);
    if (currentData?.company) currentData.company.balance = balance;
  }

  // ── Message listener ─────────────────────────────────
  window.addEventListener("message", (e) => {
    const d = e.data;
    if (d.action === "companyOpen") openPanel(d.data);
    if (d.action === "companyClose") panel.classList.add("hidden");
    if (d.action === "companyRefresh") {
      if (d.data) openPanel(d.data);
    }
    if (d.action === "companyBalance") updateBalance(d.balance);
  });
})();

// ════════════════════════════════════════════════════════
//  FACTORY STATUS PANEL
// ════════════════════════════════════════════════════════
(function () {
  const panel = document.getElementById("factory-panel");
  const list = document.getElementById("fp-list");
  const closeBtn = document.getElementById("fp-close");

  closeBtn.addEventListener("click", () => {
    panel.classList.add("hidden");
    fetch("https://motortown/factoryClose", {
      method: "POST",
      body: JSON.stringify({}),
    });
  });

  function barClass(pct, type) {
    if (pct < 20) return "crit";
    if (pct < 45) return "warn";
    return type;
  }
  function statusClass(inputPct, outputPct) {
    if (inputPct < 20 || outputPct < 20) return "crit";
    if (inputPct < 45 || outputPct < 45) return "warn";
    return "ok";
  }

  function renderFactories(factories) {
    list.innerHTML = "";
    if (!factories || factories.length === 0) {
      list.innerHTML =
        '<div style="color:rgba(255,255,255,0.3);font-size:12px;text-align:center;padding:20px">Keine Fabrikdaten</div>';
      return;
    }
    factories.forEach((f) => {
      const sCls = statusClass(f.inputPct, f.outputPct);
      const div = document.createElement("div");
      div.className = "fp-factory";
      div.dataset.key = f.key;
      div.innerHTML = `
                <div class="fp-factory-name">
                    <div class="fp-factory-status ${sCls}"></div>
                    ${f.label}
                </div>
                <div class="fp-stock">
                    <div class="fp-stock-header">
                        <span class="fp-stock-label">⬇ Input · ${f.inputItem}</span>
                        <span class="fp-stock-val">${f.inputStock}/${f.maxInput}</span>
                    </div>
                    <div class="fp-bar-track">
                        <div class="fp-bar-fill input ${barClass(f.inputPct, "input")}"
                             style="width:${f.inputPct}%"></div>
                    </div>
                </div>
                <div class="fp-stock">
                    <div class="fp-stock-header">
                        <span class="fp-stock-label">⬆ Output · ${f.outputItem}</span>
                        <span class="fp-stock-val">${f.outputStock}/${f.maxOutput}</span>
                    </div>
                    <div class="fp-bar-track">
                        <div class="fp-bar-fill output ${barClass(f.outputPct, "output")}"
                             style="width:${f.outputPct}%"></div>
                    </div>
                </div>`;
      list.appendChild(div);
    });
  }

  function updateFactory(f) {
    const div = list.querySelector(`[data-key="${f.key}"]`);
    if (!div) {
      return;
    } // wird beim nächsten open() neu gebaut

    const fills = div.querySelectorAll(".fp-bar-fill");
    const vals = div.querySelectorAll(".fp-stock-val");
    const statusDot = div.querySelector(".fp-factory-status");

    fills[0].style.width = f.inputPct + "%";
    fills[0].className = "fp-bar-fill input " + barClass(f.inputPct, "input");
    fills[1].style.width = f.outputPct + "%";
    fills[1].className =
      "fp-bar-fill output " + barClass(f.outputPct, "output");
    vals[0].textContent = `${f.inputStock}/${f.maxInput}`;
    vals[1].textContent = `${f.outputStock}/${f.maxOutput}`;
    statusDot.className =
      "fp-factory-status " + statusClass(f.inputPct, f.outputPct);
  }

  window.addEventListener("message", (e) => {
    const d = e.data;
    if (d.action === "factoryOpen") {
      renderFactories(d.factories);
      panel.classList.remove("hidden");
    }
    if (d.action === "factoryClose") panel.classList.add("hidden");
    if (d.action === "factoryUpdate") updateFactory(d.factory);
  });
})();

// ══════════════════════════════════════════════════════
//  DEALER PANEL
// ══════════════════════════════════════════════════════
(function DealerPanel() {
  const CAT_ORDER = [
    "semi",
    "flatbed",
    "kipper",
    "tanker",
    "garbage",
    "refrigerated",
    "heavyhaul",
  ];
  const CAT_ICONS = {
    semi: "🚛",
    flatbed: "🪵",
    kipper: "⛏️",
    tanker: "⛽",
    garbage: "🗑️",
    refrigerated: "❄️",
    heavyhaul: "🏗️",
  };
  const CAT_LABELS = {
    semi: "Sattelzüge",
    flatbed: "Tieflader",
    kipper: "Kipper",
    tanker: "Tanker",
    garbage: "Müll",
    refrigerated: "Kühlung",
    heavyhaul: "Schwerlast",
  };
  const TYPE_LBL = {
    semi: "Sattelzug",
    flatbed: "Tieflader",
    kipper: "Kipper",
    tanker: "Tanker",
    garbage: "Müllwagen",
    refrigerated: "Kühler",
    heavyhaul: "Schwertransport",
  };
  const fmt = (n) => Number(n).toLocaleString("de-DE") + " $";

  let allCats = {};

  const overlay = document.getElementById("dealer-overlay");
  const nav = document.getElementById("dealer-nav");
  const grid = document.getElementById("dealer-grid");
  const balEl = document.getElementById("dealer-balance");
  document.getElementById("dealer-close").addEventListener("click", closePanel);

  function closePanel() {
    overlay.classList.add("hidden");
    fetch("https://motortown/dealerClose", {
      method: "POST",
      body: JSON.stringify({}),
    });
  }

  function open(data) {
    balEl.textContent = fmt(data.money);

    // Gruppieren nach Kategorie
    allCats = {};
    for (const v of data.vehicles) {
      const cat = v.category || v.vehicleType || "semi";
      if (!allCats[cat]) allCats[cat] = [];
      allCats[cat].push(v);
    }
    // Jede Kategorie nach Preis sortieren
    for (const cat in allCats) {
      allCats[cat].sort((a, b) => a.price - b.price);
    }

    // Sidebar aufbauen
    nav.innerHTML = "";
    const orderedCats = CAT_ORDER.filter((c) => allCats[c]);
    for (const cat of orderedCats) {
      const btn = document.createElement("button");
      btn.className = "dealer-cat-btn";
      btn.dataset.cat = cat;
      btn.innerHTML = `
                <span class="dealer-cat-icon">${CAT_ICONS[cat] || "🚚"}</span>
                <span class="dealer-cat-label">${CAT_LABELS[cat] || cat}</span>
                <span class="dealer-cat-count">${allCats[cat].length}</span>`;
      btn.addEventListener("click", () => selectCat(cat));
      nav.appendChild(btn);
    }

    // Erste Kategorie wählen
    if (orderedCats.length) selectCat(orderedCats[0]);
    overlay.classList.remove("hidden");
  }

  function selectCat(cat) {
    nav
      .querySelectorAll(".dealer-cat-btn")
      .forEach((b) => b.classList.toggle("active", b.dataset.cat === cat));
    grid.innerHTML = "";
    for (const v of allCats[cat] || []) {
      grid.appendChild(buildCard(v));
    }
  }

  function buildCard(v) {
    const card = document.createElement("div");
    card.className = "dealer-card" + (v.locked ? " locked" : "");

    let btnHtml;
    if (v.locked) {
      btnHtml = `<button class="dealer-card-btn locked-btn" disabled>🔒 Level ${v.minLevel}</button>`;
    } else if (!v.canAfford) {
      btnHtml = `<button class="dealer-card-btn cant-afford-btn" disabled>Kein Geld</button>`;
    } else {
      btnHtml = `<button class="dealer-card-btn buy-btn">Kaufen</button>`;
    }

    card.innerHTML = `
            <div class="dealer-card-top">
                <span class="dealer-card-icon">${CAT_ICONS[v.vehicleType] || "🚚"}</span>
                <span class="dealer-card-price${!v.locked && !v.canAfford ? " cant-afford" : ""}">${fmt(v.price)}</span>
            </div>
            <div class="dealer-card-name">${v.label}</div>
            <div class="dealer-card-desc">${v.description || ""}</div>
            <div class="dealer-card-meta">
                <span class="dealer-badge dealer-badge-level">Lv. ${v.minLevel}</span>
                <span class="dealer-badge dealer-badge-type">${TYPE_LBL[v.vehicleType] || v.vehicleType}</span>
            </div>
            ${btnHtml}`;

    const buyBtn = card.querySelector(".buy-btn");
    if (buyBtn) buyBtn.addEventListener("click", () => showConfirm(card, v));
    return card;
  }

  function showConfirm(card, v) {
    // Bestehende Bestätigung entfernen falls offen
    card.querySelector(".dealer-confirm")?.remove();
    const confirm = document.createElement("div");
    confirm.className = "dealer-confirm";
    confirm.innerHTML = `
            <div class="dealer-confirm-title">${v.label}<br>jetzt kaufen?</div>
            <div class="dealer-confirm-price">${fmt(v.price)}</div>
            <div class="dealer-confirm-btns">
                <button class="dealer-confirm-ok">Kaufen</button>
                <button class="dealer-confirm-cancel">Abbruch</button>
            </div>`;
    confirm
      .querySelector(".dealer-confirm-ok")
      .addEventListener("click", () => {
        fetch("https://motortown/dealerBuy", {
          method: "POST",
          body: JSON.stringify({ model: v.model }),
        });
        closePanel();
      });
    confirm
      .querySelector(".dealer-confirm-cancel")
      .addEventListener("click", () => confirm.remove());
    card.appendChild(confirm);
  }

  window.addEventListener("message", (e) => {
    if (e.data.action === "dealerOpen") open(e.data);
    if (e.data.action === "dealerClose") overlay.classList.add("hidden");
  });
})();

// ══════════════════════════════════════════════════════
//  GARAGE PANEL
// ══════════════════════════════════════════════════════
(function GaragePanel() {
  const VEH_ICONS = {
    phantom: "🚛",
    phantom2: "🚛",
    hauler: "🚛",
    hauler2: "🚛",
    flatbed: "🪵",
    flatbed2: "🪵",
    dump: "⛏️",
    tipper: "⛏️",
    tipper2: "⛏️",
    tanker: "⛽",
    tanker2: "⛽",
    trash: "🗑️",
    trash2: "🗑️",
    mule4: "❄️",
    mule5: "❄️",
  };
  const VEH_LABELS = {
    phantom: "Jobuilt Phantom",
    phantom2: "Phantom Custom",
    hauler: "Jobuilt Hauler",
    hauler2: "Hauler Custom",
    flatbed: "MTL Flatbed",
    flatbed2: "Flatbed XL",
    dump: "Jobuilt S-95",
    tipper: "HVY Tipper",
    tipper2: "Tipper SX",
    tanker: "MTL Tanker",
    tanker2: "Tanker LNG",
    trash: "Trashmaster",
    trash2: "Trashmaster XL",
    mule4: "Mule (Kühlung)",
    mule5: "Mule LWB",
  };

  let currentZone = "";
  const overlay = document.getElementById("garage-overlay");
  const list = document.getElementById("garage-list");
  document.getElementById("garage-close").addEventListener("click", closePanel);

  function closePanel() {
    overlay.classList.add("hidden");
    fetch("https://motortown/garageClose", {
      method: "POST",
      body: JSON.stringify({}),
    });
  }

  function open(data) {
    currentZone = data.zoneName || "";
    list.innerHTML = "";

    if (!data.vehicles || data.vehicles.length === 0) {
      list.innerHTML =
        '<div class="garage-empty">Keine Fahrzeuge vorhanden.<br>Kaufe beim Händler dein erstes Fahrzeug.</div>';
      overlay.classList.remove("hidden");
      return;
    }

    for (const v of data.vehicles) list.appendChild(buildRow(v));
    overlay.classList.remove("hidden");
  }

  function buildRow(v) {
    const row = document.createElement("div");
    row.className = "garage-row";
    const fuel = Math.round(v.fuel || 0);
    const fuelCls = fuel > 60 ? "high" : fuel > 25 ? "mid" : "low";
    const km = v.mileage ? (v.mileage / 1000).toFixed(1) : "0.0";
    const upgCnt = Object.keys(v.upgrades || {}).length;
    const icon = VEH_ICONS[v.model] || "🚚";
    const label = VEH_LABELS[v.model] || v.model;
    const statusHtml = v.stored
      ? '<span class="garage-status-pill stored">🅿 Garage</span>'
      : '<span class="garage-status-pill out">🚛 Unterwegs</span>';

    row.innerHTML = `
            <div class="garage-row-top">
                <div class="garage-row-icon">${icon}</div>
                <div class="garage-row-info">
                    <div class="garage-row-name">${label}</div>
                    <div class="garage-row-plate">${v.plate}</div>
                </div>
                ${statusHtml}
            </div>
            <div class="garage-row-stats">
                <div class="garage-stat-item">
                    <div class="garage-stat-label">Kraftstoff</div>
                    <div class="garage-stat-val">${fuel}%</div>
                </div>
                <div class="garage-fuel-wrap">
                    <div class="garage-stat-label">Füllstand</div>
                    <div class="garage-fuel-bar">
                        <div class="garage-fuel-fill ${fuelCls}" style="width:${fuel}%"></div>
                    </div>
                </div>
                <div class="garage-stat-item">
                    <div class="garage-stat-label">Kilometer</div>
                    <div class="garage-stat-val">${km} km</div>
                </div>
                <div class="garage-stat-item">
                    <div class="garage-stat-label">Upgrades</div>
                    <div class="garage-stat-val">${upgCnt}</div>
                </div>
            </div>
            <div class="garage-row-footer">
                <button class="garage-retrieve-btn" ${v.stored ? "" : "disabled"}>
                    ${v.stored ? "Holen" : "Unterwegs"}
                </button>
            </div>`;

    const btn = row.querySelector(".garage-retrieve-btn");
    if (v.stored) {
      btn.addEventListener("click", () => {
        fetch("https://motortown/garageRetrieve", {
          method: "POST",
          body: JSON.stringify({ vehicleId: v.id, zoneName: currentZone }),
        });
        closePanel();
      });
    }
    return row;
  }

  window.addEventListener("message", (e) => {
    if (e.data.action === "garageOpen") open(e.data);
    if (e.data.action === "garageClose") overlay.classList.add("hidden");
  });
})();

// ══════════════════════════════════════════════════════
//  UPGRADE PANEL
// ══════════════════════════════════════════════════════
(function UpgradePanel() {
  const UP_ICONS = {
    motor: "⚡",
    getriebe: "⚙️",
    federung: "🔩",
    bremsen: "🛑",
    diffsperre: "🔄",
    turbo: "💨",
  };
  // Feste Reihenfolge für konsistente Darstellung
  const UP_ORDER = [
    "motor",
    "turbo",
    "getriebe",
    "federung",
    "bremsen",
    "diffsperre",
  ];
  const fmt = (n) => Number(n).toLocaleString("de-DE") + " $";
  let state = null;

  const panel = document.getElementById("upgrade-panel");
  const plateEl = document.getElementById("up-plate");
  const balEl = document.getElementById("up-balance");
  const list = document.getElementById("up-list");
  document
    .getElementById("upgrade-close")
    .addEventListener("click", closePanel);

  function closePanel() {
    panel.classList.add("hidden");
    fetch("https://motortown/upgradeClose", {
      method: "POST",
      body: JSON.stringify({}),
    });
  }

  function open(data) {
    state = data;
    plateEl.textContent = data.plate || "";
    balEl.textContent = fmt(data.money || 0);
    renderList(data);
    panel.classList.remove("hidden");
  }

  function renderList(data) {
    list.innerHTML = "";
    // Sortieren nach fixer Reihenfolge, Rest alphabetisch dahinter
    const sorted = [...data.upgrades].sort((a, b) => {
      const ia = UP_ORDER.indexOf(a.key);
      const ib = UP_ORDER.indexOf(b.key);
      if (ia === -1 && ib === -1) return a.key.localeCompare(b.key);
      if (ia === -1) return 1;
      if (ib === -1) return -1;
      return ia - ib;
    });
    for (const upg of sorted) list.appendChild(buildRow(upg, data.money));
  }

  function buildRow(upg, money) {
    const row = document.createElement("div");
    row.className = "up-row";
    const icon = UP_ICONS[upg.key] || "🔧";
    const isMax = upg.currentLevel >= upg.maxLevel;

    // Level-Punkte
    const dots = Array.from({ length: upg.maxLevel }, (_, i) => {
      const cls = i < upg.currentLevel ? (isMax ? "done" : "filled") : "empty";
      return `<div class="up-dot ${cls}"></div>`;
    }).join("");

    let costHtml, btnHtml;
    if (isMax) {
      costHtml = `<span class="up-cost maxed">✅ Max. erreicht</span>`;
      btnHtml = `<button class="up-buy-btn" disabled>Max</button>`;
    } else {
      const canAfford = money >= upg.cost;
      costHtml = `<span class="up-cost${canAfford ? "" : " cant-afford"}">${fmt(upg.cost)}</span>`;
      btnHtml = `<button class="up-buy-btn" ${canAfford ? "" : "disabled"}
                            data-key="${upg.key}" data-level="${upg.nextLevel}">
                            Stufe ${upg.nextLevel}
                        </button>`;
    }

    row.innerHTML = `
            <div class="up-row-top">
                <div class="up-row-icon">${icon}</div>
                <div class="up-row-info">
                    <div class="up-row-name">${upg.label}</div>
                    <div class="up-row-desc">${upg.description || ""}</div>
                </div>
                <div class="up-dots">${dots}</div>
            </div>
            <div class="up-row-bottom">
                ${costHtml}
                ${btnHtml}
            </div>`;

    const btn = row.querySelector(".up-buy-btn:not([disabled])");
    if (btn) {
      btn.addEventListener("click", () => {
        fetch("https://motortown/upgradeBuy", {
          method: "POST",
          body: JSON.stringify({ upgradeKey: upg.key, level: upg.nextLevel }),
        });
        // Button sofort deaktivieren – verhindert Doppelklick
        btn.disabled = true;
        btn.textContent = "...";
      });
    }
    return row;
  }

  window.addEventListener("message", (e) => {
    const d = e.data;
    if (d.action === "upgradeOpen") open(d);
    if (d.action === "upgradeClose") panel.classList.add("hidden");
    if (
      d.action === "upgradeRefresh" &&
      state &&
      !panel.classList.contains("hidden")
    ) {
      state.upgrades = d.upgrades;
      state.money = d.money;
      balEl.textContent = fmt(d.money);
      renderList(state);
    }
  });
})();

// ══════════════════════════════════════════════════════
//  CARGO LOAD PANEL
// ══════════════════════════════════════════════════════
(function CargoLoadPanel() {
  const CAT_LABELS = {
    rohstoff: "Rohstoff",
    fluessigkeit: "Flüssigkeit",
    gekuehlt: "Gekühlt",
    lebensmittel: "Lebensmittel",
    industrie: "Industrie",
  };
  const fmt = (n) => Number(n).toLocaleString("de-DE") + " $";

  const overlay = document.getElementById("cargo-load-overlay");
  const title = document.getElementById("cgl-title");
  const sub = document.getElementById("cgl-sub");
  const trLabel = document.getElementById("cgl-trailer-label");
  const capNums = document.getElementById("cgl-cap-nums");
  const capFill = document.getElementById("cgl-cap-fill");
  const usedEl = document.getElementById("cgl-used");
  const itemsEl = document.getElementById("cgl-items");
  document.getElementById("cgl-close").addEventListener("click", closeLoad);

  let zoneKey = "";
  let capData = { capacity: 0, usedSlots: 0 };

  function closeLoad() {
    overlay.classList.add("hidden");
    fetch("https://motortown/cargoLoadClose", { method: "POST", body: "{}" });
  }

  function updateCapBar(used, capacity) {
    const pct = capacity > 0 ? Math.round((used / capacity) * 100) : 0;
    capFill.style.width = pct + "%";
    capFill.className = "cargo-cap-fill" + (pct >= 100 ? " full" : "");
    usedEl.textContent = used;
    const numsSpan = capNums.querySelector("span") || capNums;
    capNums.innerHTML = `<span>${used}</span> / ${capacity} Slots`;
  }

  function open(data) {
    zoneKey = data.zone || "";
    title.textContent = "📦 " + (data.label || "Cargo laden");
    sub.textContent = data.trailer ? "🚛 " + data.trailer : "";
    trLabel.textContent = data.trailer || "Trailer";
    capData = { capacity: data.capacity || 0, usedSlots: data.usedSlots || 0 };
    updateCapBar(capData.usedSlots, capData.capacity);
    buildItems(data.items || []);
    overlay.classList.remove("hidden");
  }

  function buildItems(items) {
    itemsEl.innerHTML = "";
    if (items.length === 0) {
      itemsEl.innerHTML =
        '<div style="grid-column:1/-1;text-align:center;color:rgba(255,255,255,.28);padding:40px 0;">Keine kompatiblen Waren verfügbar.</div>';
      return;
    }
    for (const item of items) {
      itemsEl.appendChild(buildCard(item));
    }
  }

  function buildCard(item) {
    const card = document.createElement("div");
    const noStock = item.stock <= 0 || item.maxAmount <= 0;
    card.className = "cargo-item-card" + (noStock ? " no-stock" : "");

    const catLabel = CAT_LABELS[item.category] || item.category;
    const badges = [
      `<span class="cargo-badge cargo-badge-cat">${catLabel}</span>`,
      `<span class="cargo-badge cargo-badge-stock">⬟ ${item.stock}</span>`,
      item.perishable
        ? `<span class="cargo-badge cargo-badge-perishable">🕐 Verderblich</span>`
        : "",
      item.dangerous
        ? `<span class="cargo-badge cargo-badge-danger">⚠ Gefahrgut</span>`
        : "",
    ]
      .filter(Boolean)
      .join("");

    card.innerHTML = `
            <div class="cargo-item-top">
                <div class="cargo-item-icon">${item.icon || "📦"}</div>
                <div class="cargo-item-info">
                    <div class="cargo-item-name">${item.label}</div>
                    <div class="cargo-item-badges">${badges}</div>
                </div>
            </div>
            <div class="cargo-item-ctrl">
                <button class="cargo-qty-btn minus">−</button>
                <input type="number" class="cargo-qty-input"
                    value="${Math.min(item.maxAmount, 1)}"
                    min="1" max="${item.maxAmount}"
                    data-max="${item.maxAmount}">
                <span class="cargo-qty-max">max ${item.maxAmount}</span>
            </div>
            <button class="cargo-item-load-btn">📦 Laden</button>`;

    const input = card.querySelector(".cargo-qty-input");
    const minus = card.querySelector(".minus");
    const btn = card.querySelector(".cargo-item-load-btn");

    // Minus-Button
    minus.addEventListener("click", () => {
      const v = parseInt(input.value) - 1;
      input.value = Math.max(1, v);
    });
    // Plus kommt aus input max + steping
    card
      .querySelector(".cargo-qty-btn:not(.minus)")
      ?.addEventListener("click", () => {
        const v = parseInt(input.value) + 1;
        input.value = Math.min(item.maxAmount, v);
      });

    // Lade-Button
    btn.addEventListener("click", () => {
      const amount = parseInt(input.value) || 1;
      fetch("https://motortown/cargoLoadConfirm", {
        method: "POST",
        body: JSON.stringify({ zone: zoneKey, item: item.key, amount }),
      });
      overlay.classList.add("hidden");
    });

    return card;
  }

  // Kapazitäts-Update nach Laden (ohne Panel neu öffnen)
  function onCargoUpdate(data) {
    capData.usedSlots = data.loaded || 0;
    capData.capacity = data.capacity || capData.capacity;
    updateCapBar(capData.usedSlots, capData.capacity);
  }

  window.addEventListener("message", (e) => {
    const d = e.data;
    if (d.action === "cargoLoadOpen") open(d);
    if (d.action === "cargoLoadClose") overlay.classList.add("hidden");
    if (d.action === "cargoStateUpdate") onCargoUpdate(d);
  });
})();

// ══════════════════════════════════════════════════════
//  CARGO UNLOAD PANEL
// ══════════════════════════════════════════════════════
(function CargoUnloadPanel() {
  const fmt = (n) => Number(n).toLocaleString("de-DE") + " $";
  const overlay = document.getElementById("cargo-unload-overlay");
  const titleEl = document.getElementById("cgu-title");
  const subEl = document.getElementById("cgu-sub");
  const listEl = document.getElementById("cgu-list");
  const totalEl = document.getElementById("cgu-total");
  const confirmEl = document.getElementById("cgu-confirm");
  document.getElementById("cgu-close").addEventListener("click", closeUnload);

  let zoneKey = "";
  let matches = [];

  function closeUnload() {
    overlay.classList.add("hidden");
    fetch("https://motortown/cargoUnloadClose", { method: "POST", body: "{}" });
  }

  function open(data) {
    zoneKey = data.zone || "";
    matches = data.matches || [];
    titleEl.textContent = "📤 Abliefern: " + (data.label || "");
    subEl.textContent = matches.length + " Waren werden angenommen";

    listEl.innerHTML = "";
    let grand = 0;
    for (const m of matches) {
      grand += m.totalPay || 0;
      listEl.appendChild(buildRow(m));
    }
    totalEl.textContent = fmt(grand);
    overlay.classList.remove("hidden");
  }

  function buildRow(m) {
    const row = document.createElement("div");
    row.className = "cargo-unload-row";

    let penaltyNote = "";
    let payClass = "";
    if (m.penalty === 0) {
      penaltyNote = " ❌ Verdorben";
      payClass = " spoiled";
    } else if (m.penalty < 1) {
      penaltyNote = ` ⚠ ${Math.round(m.penalty * 100)}% Frische`;
      payClass = " penalty";
    }

    row.innerHTML = `
            <div class="cargo-unload-icon">${m.icon || "📦"}</div>
            <div class="cargo-unload-info">
                <div class="cargo-unload-name">${m.label}</div>
                <div class="cargo-unload-meta">
                    ${m.deliverable} von ${m.inTrailer} Einheiten${penaltyNote}
                    &nbsp;·&nbsp; ${fmt(m.pricePerUnit)} / Stück
                </div>
            </div>
            <div class="cargo-unload-pay">
                <div class="cargo-unload-pay-val${payClass}">${fmt(m.totalPay)}</div>
                <div class="cargo-unload-pay-lbl">Lohn</div>
            </div>`;
    return row;
  }

  confirmEl.addEventListener("click", () => {
    if (matches.length === 0) return;
    const items = {};
    for (const m of matches) items[m.key] = m.deliverable;
    fetch("https://motortown/cargoUnloadConfirm", {
      method: "POST",
      body: JSON.stringify({ zone: zoneKey, items }),
    });
    overlay.classList.add("hidden");
  });

  window.addEventListener("message", (e) => {
    const d = e.data;
    if (d.action === "cargoUnloadOpen") open(d);
    if (d.action === "cargoUnloadClose") overlay.classList.add("hidden");
  });
})();
