// Validación estricta de entrada (lo que manda la app) y de salida (lo que
// devuelve la IA). Todo campo desconocido se descarta; todo número se acota.

const INVISIBLE = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‏‪-‮⁠-⁤⁦-⁩﻿]/g;
const MARKUP = /[<>{}\[\]`\\|^~$]/g;

export const MUSCLES = [
  "chest", "abs", "obliques", "shoulders", "biceps", "triceps", "forearms",
  "traps", "lats", "lowerBack", "glutes", "quads", "hamstrings", "calves",
];
const KINDS = ["strength", "cardio", "mobility"];
const SLOTS = ["breakfast", "snackAm", "lunch", "snackPm", "dinner"];
const SEX = ["male", "female", "other"];
const ACTIVITY = ["sedentary", "light", "moderate", "active", "veryActive"];
const EQUIPMENT = ["gym", "calisthenics", "home"];
const GOALS = ["mountain", "running", "muscle", "fatLoss", "strength", "general"];

export function cleanText(v, max = 200) {
  if (typeof v !== "string") return "";
  return v
    .replace(INVISIBLE, "")
    .replace(MARKUP, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .slice(0, max);
}

function num(v, min, max, fallback) {
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}

function int(v, min, max, fallback) {
  return Math.round(num(v, min, max, fallback));
}

function oneOf(v, list, fallback) {
  return list.includes(v) ? v : fallback;
}

function arr(v, max) {
  return Array.isArray(v) ? v.slice(0, max) : [];
}

const INJECTION = [
  /ignor[ae]\w*\s+(las\s+|todas\s+las\s+)?(instrucciones|reglas|indicaciones)/i,
  /ignore\s+(all\s+|the\s+)?(previous|prior|above)/i,
  /(system|developer)\s*prompt/i,
  /\b(you\s+are\s+now|act\s+as|act[uú]a\s+como|ahora\s+eres)\b/i,
  /\b(jailbreak|modo\s+desarrollador)\b/i,
];

export function looksLikeInjection(text) {
  return INJECTION.some((r) => r.test(text));
}

/** Valida el cuerpo que envía la app. Devuelve null si no es aceptable. */
export function validateRequest(body) {
  if (!body || typeof body !== "object" || body.schemaVersion !== 1) return null;
  const p = body.profile;
  if (!p || typeof p !== "object") return null;

  const profile = {
    sex: oneOf(p.sex, SEX, "other"),
    age: int(p.age, 13, 100, 30),
    weightKg: num(p.weightKg, 30, 300, 70),
    heightCm: int(p.heightCm, 120, 230, 170),
    bodyFatPct: p.bodyFatPct == null ? null : int(p.bodyFatPct, 3, 70, 20),
    activity: oneOf(p.activity, ACTIVITY, "moderate"),
    equipment: oneOf(p.equipment, EQUIPMENT, "home"),
    injuries: cleanText(p.injuries, 400),
    goalType: oneOf(p.goalType, GOALS, "general"),
    goalText: cleanText(p.goalText, 200),
    weeksAvailable: int(p.weeksAvailable, 1, 104, 8),
    dailyStepGoal: int(p.dailyStepGoal, 1000, 50000, 10000),
  };
  const t = body.targets || {};
  const targets = {
    calories: int(t.calories, 1000, 6000, 2000),
    proteinG: int(t.proteinG, 20, 400, 120),
    carbsG: int(t.carbsG, 20, 800, 220),
    fatG: int(t.fatG, 20, 250, 65),
  };
  const request = cleanText(body.request, 300);

  for (const text of [profile.injuries, profile.goalText, request]) {
    if (looksLikeInjection(text)) return null;
  }
  return { profile, targets, request };
}

function exercise(e) {
  if (!e || typeof e !== "object") return null;
  const name = cleanText(e.name, 80);
  if (!name) return null;
  return {
    name,
    kind: oneOf(e.kind, KINDS, "strength"),
    sets: int(e.sets, 1, 12, 3),
    reps: cleanText(String(e.reps ?? "10"), 24) || "10",
    restSec: int(e.restSec, 0, 600, 60),
    durationSec: e.durationSec == null ? null : int(e.durationSec, 5, 14400, 60),
    distanceKm: e.distanceKm == null ? null : num(e.distanceKm, 0.1, 60, 1),
    muscles: arr(e.muscles, 8).filter((m) => MUSCLES.includes(m)),
    notes: cleanText(e.notes, 200),
  };
}

function trainingDay(d) {
  if (!d || typeof d !== "object") return null;
  return {
    weekday: int(d.weekday, 1, 7, 1),
    title: cleanText(d.title, 60) || "Entrenamiento",
    focus: cleanText(d.focus, 120),
    requiresStepGoal: d.requiresStepGoal === true,
    exercises: arr(d.exercises, 14).map(exercise).filter(Boolean),
  };
}

function meal(m) {
  if (!m || typeof m !== "object") return null;
  const name = cleanText(m.name, 80);
  if (!name) return null;
  const time = /^([01]\d|2[0-3]):[0-5]\d$/.test(m.time) ? m.time : "12:00";
  return {
    slot: oneOf(m.slot, SLOTS, "lunch"),
    time,
    name,
    description: cleanText(m.description, 300),
    kcal: int(m.kcal, 0, 3000, 0),
    proteinG: int(m.proteinG, 0, 300, 0),
    carbsG: int(m.carbsG, 0, 500, 0),
    fatG: int(m.fatG, 0, 250, 0),
    alternatives: arr(m.alternatives, 4).map((a) => cleanText(a, 120)).filter(Boolean),
  };
}

function isHttpsUrl(s) {
  try {
    const u = new URL(s);
    return u.protocol === "https:" && s.length < 300;
  } catch {
    return false;
  }
}

/** Normaliza la respuesta de la IA al esquema que entiende la app. */
export function validatePlan(raw, extraReferences = []) {
  if (!raw || typeof raw !== "object") return null;
  const tr = raw.training || {};
  const nu = raw.nutrition || {};

  const byDay = new Map();
  for (const d of arr(tr.days, 7).map(trainingDay).filter(Boolean)) {
    byDay.set(d.weekday, d);
  }
  const days = [...byDay.values()].sort((a, b) => a.weekday - b.weekday);
  if (days.length === 0) return null;

  const nutritionDays = arr(nu.days, 7)
    .map((d) => {
      if (!d || typeof d !== "object") return null;
      const meals = arr(d.meals, 6).map(meal).filter(Boolean);
      if (meals.length === 0) return null;
      return { weekday: int(d.weekday, 1, 7, 1), meals };
    })
    .filter(Boolean);
  if (nutritionDays.length === 0) return null;

  const refs = [...arr(tr.references, 10), ...extraReferences]
    .filter((r) => typeof r === "string" && isHttpsUrl(r));

  return {
    training: {
      title: cleanText(tr.title, 80) || "Plan de entrenamiento",
      summary: cleanText(tr.summary, 600),
      weeks: int(tr.weeks, 1, 104, 8),
      progression: cleanText(tr.progression, 400),
      references: [...new Set(refs)].slice(0, 8),
      source: "ai",
      createdAt: new Date().toISOString(),
      days,
    },
    nutrition: {
      calories: int(nu.calories, 1000, 6000, 2000),
      proteinG: int(nu.proteinG, 20, 400, 120),
      carbsG: int(nu.carbsG, 20, 800, 220),
      fatG: int(nu.fatG, 20, 250, 65),
      notes: arr(nu.notes, 8).map((n) => cleanText(n, 240)).filter(Boolean),
      days: nutritionDays,
    },
  };
}

/** Extrae el primer objeto JSON del texto de la IA (con o sin ```json). */
export function extractJson(text) {
  if (typeof text !== "string") return null;
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidate = fenced ? fenced[1] : text;
  const start = candidate.indexOf("{");
  const end = candidate.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    return JSON.parse(candidate.slice(start, end + 1));
  } catch {
    return null;
  }
}
