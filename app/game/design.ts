export type EnemyRole = "stalker" | "rifleman" | "brute" | "boss";

export type EncounterId = 0 | 1 | 2 | 3 | 4;

export type SpawnSpec = {
  x: number;
  z: number;
  role: EnemyRole;
};

export const WEAPON = {
  magazineSize: 24,
  startingReserve: 96,
  fireIntervalMs: 96,
  reloadMs: 1050,
  hipFov: 68,
  adsFov: 54,
} as const;

export const ENEMY_ROLE = {
  stalker: { health: 82, speed: 4.2, desiredRange: 3.2, cooldown: 2.6 },
  rifleman: { health: 110, speed: 2.25, desiredRange: 22, cooldown: 1.25 },
  brute: { health: 190, speed: 1.7, desiredRange: 10, cooldown: 2.25 },
  boss: { health: 520, speed: 3.1, desiredRange: 15, cooldown: 0.58 },
} as const;

export const ENCOUNTER_WAVES: Record<1 | 3, readonly SpawnSpec[]> = {
  1: [
    { x: -8, z: 5, role: "rifleman" },
    { x: 7, z: -2, role: "stalker" },
    { x: -10, z: -12, role: "brute" },
  ],
  3: [
    { x: 9, z: -36, role: "stalker" },
    { x: -9, z: -41, role: "rifleman" },
    { x: 4, z: -51, role: "brute" },
    { x: -5, z: -58, role: "stalker" },
    { x: 0, z: -67, role: "rifleman" },
  ],
} as const;

export const OBJECTIVE = {
  approach: "Ascend through the black ravine",
  ambush: "Survive the homestead ambush",
  bell: "Ring the stolen bell",
  siege: "Break Varkas' mountain siege",
  gate: "Enter Varkas' iron gate",
  boss: "KILL VARKAS — THE IRON WOLVERINE",
  victory: "THE FAMILY IS AVENGED",
} as const;

export const CHECKPOINT = {
  1: { x: 0, z: 24, kills: 0, objective: OBJECTIVE.ambush },
  3: { x: -7, z: -15, kills: 3, objective: OBJECTIVE.siege },
  4: { x: 0, z: -63, kills: 8, objective: OBJECTIVE.boss },
} as const;

export const TOTAL_ENEMIES = 9;
