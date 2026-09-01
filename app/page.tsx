"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type * as THREE from "three";
import {
  CHECKPOINT,
  ENCOUNTER_WAVES,
  ENEMY_ROLE,
  OBJECTIVE,
  TOTAL_ENEMIES,
  WEAPON,
  type EncounterId,
  type EnemyRole,
} from "./game/design";

type HudState = {
  ammo: number;
  reserve: number;
  health: number;
  kills: number;
  total: number;
  echo: number;
  objective: string;
  prompt: string;
  boss: number;
  lowHealth: boolean;
};

type Enemy = {
  group: THREE.Group;
  body: THREE.Mesh;
  head: THREE.Mesh;
  role: EnemyRole;
  encounter: EncounterId;
  health: number;
  maxHealth: number;
  speed: number;
  phase: number;
  cooldown: number;
  boss: boolean;
  dead: boolean;
  velocity: THREE.Vector3;
  material: THREE.MeshStandardMaterial;
};

type Particle = {
  mesh: THREE.Mesh;
  velocity: THREE.Vector3;
  life: number;
};

const initialHud: HudState = {
  ammo: WEAPON.magazineSize,
  reserve: WEAPON.startingReserve,
  health: 100,
  kills: 0,
  total: TOTAL_ENEMIES,
  echo: 1,
  objective: OBJECTIVE.approach,
  prompt: "",
  boss: 0,
  lowHealth: false,
};

function makeSeededRandom(seed: number) {
  let value = seed >>> 0;
  return () => {
    value += 0x6d2b79f5;
    let result = value;
    result = Math.imul(result ^ (result >>> 15), result | 1);
    result ^= result + Math.imul(result ^ (result >>> 7), result | 61);
    return ((result ^ (result >>> 14)) >>> 0) / 4294967296;
  };
}

const ridgeHeight = (x: number, z: number) => {
  const base = Math.sin(x * 0.055) * 0.7 + Math.cos(z * 0.045) * 0.55;
  const detail = Math.sin((x + z) * 0.12) * 0.22;
  const path = Math.max(0, Math.abs(x) - 9) * 0.18;
  const ascent = Math.max(0, 28 - z) * 0.115;
  return base + detail + path + ascent - 2.2;
};

function makeNoiseTexture(
  THREE: typeof import("three"),
  random: () => number,
  size = 256,
) {
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d")!;
  const image = ctx.createImageData(size, size);
  for (let i = 0; i < image.data.length; i += 4) {
    const grain =
      195 +
      (random() - 0.5) * 34 +
      (random() - 0.5) * 18;
    image.data[i] = grain * 0.84;
    image.data[i + 1] = grain * 0.94;
    image.data[i + 2] = Math.min(255, grain * 1.1);
    image.data[i + 3] = 255;
  }
  ctx.putImageData(image, 0, 0);
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(18, 18);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function makeRockTexture(
  THREE: typeof import("three"),
  random: () => number,
  size = 256,
) {
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d")!;
  ctx.fillStyle = "#252e32";
  ctx.fillRect(0, 0, size, size);
  for (let i = 0; i < 1800; i++) {
    const v = 34 + random() * 45;
    ctx.fillStyle = `rgba(${v},${v + 7},${v + 9},${random() * 0.2})`;
    const r = random() * 3 + 0.3;
    ctx.fillRect(random() * size, random() * size, r * 3, r);
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(2, 3);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function makeWoodTexture(THREE: typeof import("three"), size = 256) {
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d")!;
  const gradient = ctx.createLinearGradient(0, 0, size, 0);
  gradient.addColorStop(0, "#5c2f19");
  gradient.addColorStop(0.45, "#8b512b");
  gradient.addColorStop(1, "#4b2515");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, size, size);
  for (let y = 0; y < size; y += 2) {
    const wobble = Math.sin(y * 0.17) * 8 + Math.sin(y * 0.041) * 18;
    ctx.strokeStyle = `rgba(30,12,7,${0.08 + (y % 11) * 0.006})`;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.bezierCurveTo(size * 0.3, y + wobble, size * 0.7, y - wobble, size, y + wobble * 0.25);
    ctx.stroke();
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(1.2, 2.8);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function makeAudioEngine() {
  let ctx: AudioContext | null = null;
  let master: GainNode | null = null;
  let wind: AudioBufferSourceNode | null = null;
  let windGain: GainNode | null = null;

  const noiseBuffer = (audio: AudioContext, seconds: number) => {
    const buffer = audio.createBuffer(1, audio.sampleRate * seconds, audio.sampleRate);
    const data = buffer.getChannelData(0);
    let last = 0;
    for (let i = 0; i < data.length; i++) {
      const white = Math.random() * 2 - 1;
      last = last * 0.985 + white * 0.015;
      data[i] = white * 0.55 + last * 1.8;
    }
    return buffer;
  };

  const ensure = () => {
    if (ctx) return ctx;
    ctx = new AudioContext();
    master = ctx.createGain();
    master.gain.value = 0.36;
    master.connect(ctx.destination);

    wind = ctx.createBufferSource();
    wind.buffer = noiseBuffer(ctx, 4);
    wind.loop = true;
    const filter = ctx.createBiquadFilter();
    filter.type = "bandpass";
    filter.frequency.value = 520;
    filter.Q.value = 0.45;
    windGain = ctx.createGain();
    windGain.gain.value = 0.075;
    wind.connect(filter).connect(windGain).connect(master);
    wind.start();
    return ctx;
  };

  const tone = (
    frequency: number,
    duration: number,
    gain = 0.2,
    type: OscillatorType = "sine",
    slide = 0,
  ) => {
    const audio = ensure();
    const osc = audio.createOscillator();
    const volume = audio.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(frequency, audio.currentTime);
    osc.frequency.exponentialRampToValueAtTime(
      Math.max(20, frequency + slide),
      audio.currentTime + duration,
    );
    volume.gain.setValueAtTime(gain, audio.currentTime);
    volume.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + duration);
    osc.connect(volume).connect(master!);
    osc.start();
    osc.stop(audio.currentTime + duration);
  };

  const noise = (duration: number, gain: number, frequency: number) => {
    const audio = ensure();
    const source = audio.createBufferSource();
    const filter = audio.createBiquadFilter();
    const volume = audio.createGain();
    source.buffer = noiseBuffer(audio, duration);
    filter.type = "lowpass";
    filter.frequency.value = frequency;
    volume.gain.setValueAtTime(gain, audio.currentTime);
    volume.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + duration);
    source.connect(filter).connect(volume).connect(master!);
    source.start();
  };

  return {
    start() {
      ensure().resume();
    },
    shot() {
      noise(0.16, 0.75, 2100);
      tone(92, 0.18, 0.34, "sawtooth", -54);
    },
    click() {
      tone(1250, 0.035, 0.06, "square", -500);
    },
    hit(critical = false) {
      tone(critical ? 1180 : 720, 0.07, critical ? 0.13 : 0.075, "triangle", -220);
    },
    enemyShot() {
      noise(0.1, 0.2, 1400);
      tone(125, 0.12, 0.09, "square", -70);
    },
    echo() {
      tone(64, 1.5, 0.38, "sine", 36);
      tone(128, 1.2, 0.17, "triangle", -42);
      window.setTimeout(() => tone(252, 0.8, 0.12, "sine", -70), 110);
    },
    reload() {
      tone(640, 0.06, 0.06, "square", -260);
      window.setTimeout(() => tone(390, 0.08, 0.06, "square", 190), 720);
    },
    hurt() {
      noise(0.3, 0.2, 430);
      tone(70, 0.4, 0.18, "sine", -32);
    },
    setWind(value: number) {
      if (windGain && ctx) {
        windGain.gain.setTargetAtTime(value, ctx.currentTime, 0.4);
      }
    },
    stop() {
      if (ctx) void ctx.close();
      ctx = null;
    },
  };
}

function createWolverine(
  THREE: typeof import("three"),
  scene: THREE.Scene,
  position: THREE.Vector3,
  role: EnemyRole = "rifleman",
  encounter: EncounterId = 1,
): Enemy {
  const boss = role === "boss";
  const brute = role === "brute";
  const stalker = role === "stalker";
  const tuning = ENEMY_ROLE[role];
  const scale = boss ? 1.34 : brute ? 1.16 : stalker ? 0.92 : 1;
  const group = new THREE.Group();
  group.position.copy(position);
  const armor = new THREE.MeshStandardMaterial({
    color: boss ? 0x3a0b08 : brute ? 0x273036 : stalker ? 0x191412 : 0x121719,
    roughness: 0.43,
    metalness: 0.66,
    emissive: boss ? 0x5b0903 : 0x000000,
    emissiveIntensity: boss ? 0.26 : 0,
  });
  const fur = new THREE.MeshStandardMaterial({
    color: boss ? 0x42130e : 0x1e2526,
    roughness: 0.95,
  });
  const body = new THREE.Mesh(
    new THREE.CapsuleGeometry(0.52 * scale, 1.2 * scale, 5, 10),
    armor,
  );
  body.position.y = boss ? 1.45 : 1.1;
  body.castShadow = true;
  body.userData.enemy = true;
  group.add(body);

  const head = new THREE.Mesh(
    new THREE.DodecahedronGeometry(0.43 * scale, 1),
    fur,
  );
  head.position.set(0, 2.05 * scale, 0.06);
  head.scale.set(1, 0.82, 1.15);
  head.castShadow = true;
  head.userData.enemy = true;
  head.userData.critical = true;
  group.add(head);

  const snout = new THREE.Mesh(
    new THREE.ConeGeometry(boss ? 0.28 : 0.2, boss ? 0.68 : 0.5, 5),
    new THREE.MeshStandardMaterial({ color: 0x0b0d0e, roughness: 0.8 }),
  );
  snout.position.set(0, boss ? 2.52 : 1.96, -0.52);
  snout.rotation.x = -Math.PI / 2;
  group.add(snout);

  const eyeMat = new THREE.MeshBasicMaterial({ color: boss ? 0xff3b16 : 0xffa322 });
  for (const x of [-0.18, 0.18]) {
    const eye = new THREE.Mesh(new THREE.SphereGeometry(0.045, 8, 8), eyeMat);
    eye.position.set(x * (boss ? 1.25 : 1), boss ? 2.68 : 2.09, -0.44);
    group.add(eye);
  }

  const gun = new THREE.Mesh(
    new THREE.BoxGeometry(boss ? 0.18 : 0.13, 0.16, boss ? 1.3 : 1),
    new THREE.MeshStandardMaterial({ color: 0x202325, metalness: 0.85, roughness: 0.24 }),
  );
  gun.position.set(0.45, boss ? 1.55 : 1.2, -0.5);
  gun.rotation.x = 0.12;
  group.add(gun);

  if (boss) {
    const rigMat = new THREE.MeshStandardMaterial({
      color: 0x171a1b,
      metalness: 0.9,
      roughness: 0.34,
    });
    for (const x of [-1, 1]) {
      const piston = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.16, 2.4, 8), rigMat);
      piston.position.set(x * 0.82, 1.25, 0.25);
      piston.rotation.z = x * -0.18;
      group.add(piston);
    }
    const claw = new THREE.Mesh(
      new THREE.TorusGeometry(0.85, 0.07, 8, 24, Math.PI * 1.45),
      new THREE.MeshStandardMaterial({
        color: 0xb83716,
        emissive: 0x5a0802,
        emissiveIntensity: 0.6,
        metalness: 0.7,
      }),
    );
    claw.position.set(0, 1.45, 0.42);
    claw.rotation.z = 0.76;
    group.add(claw);
  }

  body.userData.root = group;
  head.userData.root = group;
  group.userData.enemy = true;
  scene.add(group);
  return {
    group,
    body,
    head,
    role,
    encounter,
    health: tuning.health,
    maxHealth: tuning.health,
    speed: tuning.speed,
    phase: Math.random() * Math.PI * 2,
    cooldown: 0.8 + Math.random() * 1.2,
    boss,
    dead: false,
    velocity: new THREE.Vector3(),
    material: armor,
  };
}

function GameCanvas({
  active,
  fallbackControls,
  onHud,
  onLocked,
  onReady,
  onWin,
}: {
  active: boolean;
  fallbackControls: boolean;
  onHud: (state: HudState) => void;
  onLocked: (locked: boolean) => void;
  onReady: (ready: boolean) => void;
  onWin: () => void;
}) {
  const mountRef = useRef<HTMLDivElement>(null);
  const activeRef = useRef(active);
  const fallbackRef = useRef(fallbackControls);

  useEffect(() => {
    activeRef.current = active;
  }, [active]);

  useEffect(() => {
    fallbackRef.current = fallbackControls;
  }, [fallbackControls]);

  useEffect(() => {
    const mount = mountRef.current;
    if (!mount) return;

    let cancelled = false;
    let teardown: (() => void) | undefined;

    const boot = async () => {
      const [
        THREE,
        { EffectComposer },
        { RenderPass },
        { UnrealBloomPass },
        { OutputPass },
      ] = await Promise.all([
        import("three"),
        import("three/examples/jsm/postprocessing/EffectComposer.js"),
        import("three/examples/jsm/postprocessing/RenderPass.js"),
        import("three/examples/jsm/postprocessing/UnrealBloomPass.js"),
        import("three/examples/jsm/postprocessing/OutputPass.js"),
      ]);
      if (cancelled) return;

    const worldRandom = makeSeededRandom(0x4d474b31);

    const scene = new THREE.Scene();
    scene.fog = new THREE.FogExp2(0x152432, 0.0065);
    const camera = new THREE.PerspectiveCamera(WEAPON.hipFov, 1, 0.05, 520);
    camera.position.set(0, 2, 28);
    camera.rotation.order = "YXZ";

    const renderer = new THREE.WebGLRenderer({
      antialias: true,
      powerPreference: "high-performance",
      stencil: false,
    });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.65));
    renderer.setSize(mount.clientWidth, mount.clientHeight);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 0.9;
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    mount.appendChild(renderer.domElement);

    const composer = new EffectComposer(renderer);
    composer.addPass(new RenderPass(scene, camera));
    const bloom = new UnrealBloomPass(
      new THREE.Vector2(mount.clientWidth, mount.clientHeight),
      0.34,
      0.8,
      0.78,
    );
    composer.addPass(bloom);
    composer.addPass(new OutputPass());

    const sky = new THREE.Mesh(
      new THREE.SphereGeometry(390, 32, 20),
      new THREE.ShaderMaterial({
        side: THREE.BackSide,
        uniforms: {
          top: { value: new THREE.Color(0x020812) },
          horizon: { value: new THREE.Color(0x1a2b3d) },
          glow: { value: new THREE.Color(0x704427) },
        },
        vertexShader: `
          varying vec3 vWorld;
          void main() {
            vec4 world = modelMatrix * vec4(position, 1.0);
            vWorld = world.xyz;
            gl_Position = projectionMatrix * viewMatrix * world;
          }`,
        fragmentShader: `
          uniform vec3 top;
          uniform vec3 horizon;
          uniform vec3 glow;
          varying vec3 vWorld;
          void main() {
            float h = normalize(vWorld).y;
            float band = smoothstep(-0.12, 0.5, h);
            vec3 color = mix(horizon, top, band);
            float dusk = pow(max(0.0, 1.0 - abs(h + 0.03) * 6.0), 3.0);
            color += glow * dusk * 0.12;
            gl_FragColor = vec4(color, 1.0);
          }`,
      }),
    );
    scene.add(sky);

    const fortressMatteTexture = new THREE.TextureLoader().load("/fortress-matte.png");
    fortressMatteTexture.colorSpace = THREE.SRGBColorSpace;
    fortressMatteTexture.minFilter = THREE.LinearFilter;
    fortressMatteTexture.magFilter = THREE.LinearFilter;
    const fortressMatte = new THREE.Mesh(
      new THREE.PlaneGeometry(410, 231),
      new THREE.MeshBasicMaterial({
        map: fortressMatteTexture,
        fog: false,
        toneMapped: false,
        depthWrite: false,
      }),
    );
    fortressMatte.position.set(-48, 38, -154);
    fortressMatte.renderOrder = 1;
    scene.add(fortressMatte);

    const hemi = new THREE.HemisphereLight(0x8ba9be, 0x070b10, 0.58);
    scene.add(hemi);
    const sun = new THREE.DirectionalLight(0x9fc8e5, 3.1);
    sun.position.set(-28, 38, 14);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.camera.left = -30;
    sun.shadow.camera.right = 30;
    sun.shadow.camera.top = 42;
    sun.shadow.camera.bottom = -42;
    sun.shadow.camera.near = 1;
    sun.shadow.camera.far = 150;
    sun.shadow.bias = -0.00015;
    scene.add(sun);

    const moon = new THREE.PointLight(0x7fc9ff, 7.5, 115, 1.35);
    moon.position.set(20, 32, -70);
    scene.add(moon);

    const snowTex = makeNoiseTexture(THREE, worldRandom);
    const groundGeo = new THREE.PlaneGeometry(130, 245, 110, 190);
    groundGeo.rotateX(-Math.PI / 2);
    const positions = groundGeo.attributes.position;
    for (let i = 0; i < positions.count; i++) {
      const x = positions.getX(i);
      const z = positions.getZ(i) - 68;
      positions.setZ(i, z);
      positions.setY(i, ridgeHeight(x, z));
    }
    positions.needsUpdate = true;
    groundGeo.computeVertexNormals();
    const ground = new THREE.Mesh(
      groundGeo,
      new THREE.MeshStandardMaterial({
        map: snowTex,
        color: 0x52677a,
        roughness: 0.92,
        metalness: 0.04,
        bumpMap: snowTex,
        bumpScale: 0.045,
      }),
    );
    ground.receiveShadow = true;
    scene.add(ground);

    const rockTex = makeRockTexture(THREE, worldRandom);
    const rockMat = new THREE.MeshStandardMaterial({
      map: rockTex,
      color: 0x252f38,
      roughness: 0.92,
      metalness: 0.03,
    });
    const rockGeo = new THREE.DodecahedronGeometry(1, 1);
    const rocks = new THREE.InstancedMesh(rockGeo, rockMat, 72);
    rocks.castShadow = true;
    rocks.receiveShadow = true;
    const dummy = new THREE.Object3D();
    const rockColor = new THREE.Color();
    for (let i = 0; i < 72; i++) {
      const side = i % 2 ? 1 : -1;
      const z = 38 - worldRandom() * 195;
      const x = side * (12.5 + worldRandom() * 39);
      const s = 1.2 + worldRandom() * 3.8;
      dummy.position.set(x, ridgeHeight(x, z) + s * 0.28 - 1.2, z);
      dummy.rotation.set(worldRandom(), worldRandom() * Math.PI, worldRandom());
      dummy.scale.set(s * (0.7 + worldRandom()), s, s * (0.8 + worldRandom()));
      dummy.updateMatrix();
      rocks.setMatrixAt(i, dummy.matrix);
      rocks.setColorAt(i, rockColor.setHSL(0.57, 0.11, 0.34 + worldRandom() * 0.12));
    }
    scene.add(rocks);

    const routeMat = new THREE.MeshStandardMaterial({
      color: 0x536c78,
      roughness: 0.98,
      metalness: 0,
      polygonOffset: true,
      polygonOffsetFactor: -3,
      polygonOffsetUnits: -2,
    });
    const routeSteps = 58;
    const routePositions: number[] = [];
    const routeIndices: number[] = [];
    for (let i = 0; i < routeSteps; i++) {
      const z = 31 - i * 2.2;
      const x = Math.sin(i * 0.22) * 2.25;
      const halfWidth = 3.5 + Math.sin(i * 0.37) * 0.35;
      for (const edge of [-1, 1]) {
        const px = x + edge * halfWidth;
        routePositions.push(px, ridgeHeight(px, z) + 0.13, z);
      }
      if (i < routeSteps - 1) {
        const a = i * 2;
        routeIndices.push(a, a + 2, a + 1, a + 1, a + 2, a + 3);
      }
    }
    const routeGeo = new THREE.BufferGeometry();
    routeGeo.setAttribute("position", new THREE.Float32BufferAttribute(routePositions, 3));
    routeGeo.setIndex(routeIndices);
    routeGeo.computeVertexNormals();
    const route = new THREE.Mesh(routeGeo, routeMat);
    route.receiveShadow = true;
    scene.add(route);

    const coverGroup = new THREE.Group();
    const coverPoints: Array<[number, number, number]> = [
      [-6.3, 14, 2.4],
      [8.1, -3, 1.8],
      [-5.8, -17, 2.8],
      [6.7, -43, 2.5],
      [-6.6, -56, 3.1],
    ];
    for (const [x, z, scale] of coverPoints) {
      for (let j = 0; j < 3; j++) {
        const stone = new THREE.Mesh(rockGeo, rockMat);
        const sx = scale * (j === 0 ? 1 : 0.58 + j * 0.08);
        stone.position.set(
          x + (j - 1) * scale * 0.62,
          ridgeHeight(x, z) + sx * 0.32,
          z + (j % 2 ? 0.5 : -0.35),
        );
        stone.scale.set(sx * 0.9, sx, sx * 0.72);
        stone.rotation.set(j * 0.35, j * 0.9 + z, j * 0.16);
        stone.castShadow = stone.receiveShadow = true;
        coverGroup.add(stone);
      }
    }
    scene.add(coverGroup);

    const mountainMat = new THREE.MeshStandardMaterial({
      color: 0x111b25,
      roughness: 1,
      flatShading: true,
    });
    for (let i = 0; i < 15; i++) {
      const mountain = new THREE.Mesh(
        new THREE.IcosahedronGeometry(1, 2),
        mountainMat,
      );
      const angle = (i / 15) * Math.PI * 1.4 + 0.75;
      const distance = 175 + worldRandom() * 80;
      const width = 14 + worldRandom() * 17;
      mountain.scale.set(width, 32 + worldRandom() * 34, width * (0.7 + worldRandom() * 0.45));
      mountain.position.set(
        Math.cos(angle) * distance,
        9 + worldRandom() * 7,
        Math.sin(angle) * distance - 60,
      );
      mountain.rotation.y = worldRandom() * Math.PI;
      scene.add(mountain);
    }

    const cliffGroup = new THREE.Group();
    const cliffGeometry = new THREE.IcosahedronGeometry(1, 2);
    const cliffMaterial = new THREE.MeshStandardMaterial({
      color: 0x111a23,
      roughness: 1,
      flatShading: true,
    });
    for (const side of [-1, 1]) {
      for (let i = 0; i < 14; i++) {
        const z = 32 - i * 8.8;
        const height = 12 + worldRandom() * 17 + i * 0.48;
        const cliff = new THREE.Mesh(cliffGeometry, cliffMaterial);
        cliff.position.set(
          side * (23 + worldRandom() * 3.8),
          ridgeHeight(side * 18, z) + height * 0.38,
          z + (worldRandom() - 0.5) * 3,
        );
        cliff.scale.set(7 + worldRandom() * 3, height, 7 + worldRandom() * 4);
        cliff.rotation.set(worldRandom() * 0.3, worldRandom() * Math.PI, side * 0.08);
        cliff.castShadow = cliff.receiveShadow = true;
        cliffGroup.add(cliff);
      }
    }
    scene.add(cliffGroup);

    const timberMat = new THREE.MeshStandardMaterial({
      color: 0x2a1a12,
      roughness: 0.84,
      metalness: 0.02,
    });
    const ironMat = new THREE.MeshStandardMaterial({
      color: 0x20282c,
      roughness: 0.38,
      metalness: 0.86,
    });
    const emberMat = new THREE.MeshStandardMaterial({
      color: 0xff6a19,
      emissive: 0xff3b00,
      emissiveIntensity: 3.4,
    });
    const fortressMat = new THREE.MeshStandardMaterial({
      map: rockTex,
      color: 0x56636d,
      roughness: 0.9,
      metalness: 0.04,
      emissive: 0x0d1216,
      emissiveIntensity: 0.58,
    });

    const outpost = new THREE.Group();
    outpost.position.set(0, ridgeHeight(0, -76), -76);
    const addStoneBlock = (
      width: number,
      height: number,
      depth: number,
      x: number,
      y: number,
      z = 0,
    ) => {
      const block = new THREE.Mesh(new THREE.BoxGeometry(width, height, depth), fortressMat);
      block.position.set(x, y, z);
      block.castShadow = block.receiveShadow = true;
      outpost.add(block);
      return block;
    };
    const addBattlements = (width: number, y: number, z: number) => {
      const count = Math.max(3, Math.floor(width / 2.2));
      for (let i = 0; i < count; i++) {
        const x = -width / 2 + 1.1 + i * (width - 2.2) / Math.max(1, count - 1);
        const merlon = addStoneBlock(1.15, 1.55, 1.6, x, y, z);
        merlon.rotation.y = (worldRandom() - 0.5) * 0.035;
      }
    };

    for (const x of [-16.5, 16.5]) {
      addStoneBlock(5.8, 23, 7.2, x, 10.8, 0.8);
      addStoneBlock(7.2, 2, 8.2, x, 22.8, 0.8);
      addBattlements(8.8, 24.35, 0.8);
      for (const y of [4.5, 10.5, 16.5, 21.7]) {
        const slit = new THREE.Mesh(new THREE.BoxGeometry(0.5, 1.25, 0.28), emberMat);
        slit.position.set(x, y, -3.35);
        outpost.add(slit);
      }
    }

    const gate = new THREE.Mesh(new THREE.BoxGeometry(9.5, 10.8, 0.65), ironMat);
    gate.position.set(0, 4.7, -3.48);
    outpost.add(gate);
    for (const x of [-5.9, 5.9]) addStoneBlock(2.8, 13.5, 2.8, x, 6.1, -3.3);
    addStoneBlock(15.2, 3.1, 3.2, 0, 12.15, -3.3);
    for (let i = -4; i <= 4; i++) {
      const bar = new THREE.Mesh(new THREE.BoxGeometry(0.24, 10.5, 0.28), ironMat);
      bar.position.set(i * 1.02, 4.7, -3.88);
      outpost.add(bar);
    }
    for (const [x, y] of [
      [-7.8, 8.5],
      [7.8, 8.5],
      [-4.5, 18.5],
      [4.5, 18.5],
      [0, 30],
    ] as Array<[number, number]>) {
      const windowGlow = new THREE.Mesh(new THREE.BoxGeometry(0.7, 1.65, 0.3), emberMat);
      windowGlow.position.set(x, y, -4.2);
      outpost.add(windowGlow);
    }
    for (const x of [-16, -12, -8, -4, 0, 4, 8, 12, 16]) {
      const post = new THREE.Mesh(new THREE.BoxGeometry(0.36, 7.4, 0.36), timberMat);
      post.position.set(x, 3.4, 7);
      post.rotation.z = Math.sin(x) * 0.07;
      outpost.add(post);
      if (x < 16) {
        const rail = new THREE.Mesh(new THREE.BoxGeometry(4.3, 0.26, 0.26), timberMat);
        rail.position.set(x + 2, 6.5, 7);
        rail.rotation.z = (x % 8 === 0 ? 1 : -1) * 0.12;
        outpost.add(rail);
      }
    }
    scene.add(outpost);

    const fortressKey = new THREE.PointLight(0xff8a3d, 280, 92, 1.45);
    fortressKey.position.set(0, ridgeHeight(0, -76) + 13, -71);
    scene.add(fortressKey);
    const fortressMoon = new THREE.SpotLight(0x8fc9ed, 1800, 170, Math.PI * 0.34, 0.78, 1.1);
    fortressMoon.position.set(-34, ridgeHeight(0, -76) + 48, -48);
    fortressMoon.target.position.copy(outpost.position).add(new THREE.Vector3(0, 16, 0));
    scene.add(fortressMoon, fortressMoon.target);

    const bellGroup = new THREE.Group();
    const bell = new THREE.Mesh(
      new THREE.CylinderGeometry(1.25, 1.75, 2.3, 18, 1, true),
      new THREE.MeshStandardMaterial({
        color: 0xc37b2d,
        roughness: 0.3,
        metalness: 0.88,
        emissive: 0xb94c0a,
        emissiveIntensity: 1.25,
      }),
    );
    bell.position.y = 4.4;
    bellGroup.add(bell);
    const bellBeam = new THREE.Mesh(new THREE.BoxGeometry(8, 0.5, 0.5), timberMat);
    bellBeam.position.y = 6.1;
    bellGroup.add(bellBeam);
    for (const x of [-3.5, 3.5]) {
      const post = new THREE.Mesh(new THREE.BoxGeometry(0.5, 7, 0.5), timberMat);
      post.position.set(x, 2.7, 0);
      bellGroup.add(post);
    }
    bellGroup.position.set(-7, ridgeHeight(-7, -22), -22);
    bellGroup.scale.setScalar(1.3);
    scene.add(bellGroup);
    const bellLight = new THREE.PointLight(0xe58a3b, 58, 34, 1.5);
    bellLight.position.set(-7, ridgeHeight(-7, -22) + 6.4, -22);
    scene.add(bellLight);
    const objectiveGlow = new THREE.Mesh(
      new THREE.SphereGeometry(4.7, 18, 12),
      new THREE.MeshBasicMaterial({
        color: 0xe58a3b,
        transparent: true,
        opacity: 0.085,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      }),
    );
    objectiveGlow.position.copy(bellLight.position);
    scene.add(objectiveGlow);

    const playerColliders: Array<[number, number, number]> = [
      ...coverPoints.map(
        ([x, z, scale]) => [x, z, scale * 0.82 + 0.45] as [number, number, number],
      ),
      [-7.6, -76, 2.2],
      [7.6, -76, 2.2],
      [-11.55, -22, 0.95],
      [-2.45, -22, 0.95],
    ];

    const clothMat = new THREE.MeshStandardMaterial({
      color: 0x9a3d20,
      roughness: 0.9,
      side: THREE.DoubleSide,
      emissive: 0x351006,
      emissiveIntensity: 0.18,
    });
    const trailMarkers = new THREE.Group();
    for (const [x, z, lean] of [
      [-8.2, -8, 0.08],
      [-4.4, -47, -0.06],
    ] as Array<[number, number, number]>) {
      const arch = new THREE.Group();
      arch.position.set(x, ridgeHeight(x, z), z);
      arch.rotation.z = lean;
      for (const side of [-1, 1]) {
        const horn = new THREE.Mesh(
          new THREE.TorusGeometry(1.55, 0.12, 8, 22, Math.PI * 0.72),
          timberMat,
        );
        horn.position.set(side * 1.18, 2.15, 0);
        horn.rotation.set(Math.PI / 2, side * 0.2, side > 0 ? 0.48 : 2.66);
        horn.castShadow = true;
        arch.add(horn);
      }
      const cloth = new THREE.Mesh(new THREE.PlaneGeometry(0.78, 2.2), clothMat);
      cloth.position.set(0, 2.15, 0.12);
      cloth.rotation.y = 0.12 + z * 0.01;
      arch.add(cloth);
      trailMarkers.add(arch);
    }
    scene.add(trailMarkers);

    const lanterns: THREE.PointLight[] = [];
    for (const [x, z] of [
      [-8, 12],
      [9, -13],
      [-11, -43],
      [10, -70],
    ]) {
      const lamp = new THREE.Mesh(new THREE.OctahedronGeometry(0.2), emberMat);
      lamp.position.set(x, ridgeHeight(x, z) + 3.2, z);
      scene.add(lamp);
      const light = new THREE.PointLight(0xff7828, 22, 17, 1.8);
      light.position.copy(lamp.position);
      scene.add(light);
      lanterns.push(light);
    }

    const debris: Particle[] = [];
    for (let i = 0; i < 16; i++) {
      const mesh = new THREE.Mesh(
        i % 3 === 0
          ? new THREE.BoxGeometry(0.45, 0.45, 1.6)
          : new THREE.DodecahedronGeometry(0.35 + worldRandom() * 0.5, 0),
        i % 3 === 0 ? timberMat : rockMat,
      );
      const z = 22 - worldRandom() * 105;
      const side = i % 2 ? 1 : -1;
      const x = side * (4.8 + worldRandom() * 3.2);
      mesh.position.set(x, ridgeHeight(x, z) + 0.6, z);
      mesh.rotation.set(worldRandom(), worldRandom(), worldRandom());
      mesh.castShadow = true;
      scene.add(mesh);
      debris.push({ mesh, velocity: new THREE.Vector3(), life: Infinity });
    }

    const snowCount = 3900;
    const snowPositions = new Float32Array(snowCount * 3);
    const snowSizes = new Float32Array(snowCount);
    for (let i = 0; i < snowCount; i++) {
      snowPositions[i * 3] = (worldRandom() - 0.5) * 150;
      snowPositions[i * 3 + 1] = worldRandom() * 54 - 4;
      snowPositions[i * 3 + 2] = worldRandom() * 230 - 160;
      snowSizes[i] = 0.8 + worldRandom() * 1.7;
    }
    const snowGeo = new THREE.BufferGeometry();
    snowGeo.setAttribute("position", new THREE.BufferAttribute(snowPositions, 3));
    snowGeo.setAttribute("size", new THREE.BufferAttribute(snowSizes, 1));
    const snow = new THREE.Points(
      snowGeo,
      new THREE.ShaderMaterial({
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        uniforms: { pixelRatio: { value: renderer.getPixelRatio() } },
        vertexShader: `
          attribute float size;
          varying float fade;
          void main() {
            vec4 mv = modelViewMatrix * vec4(position, 1.0);
            gl_PointSize = size * 100.0 / max(1.0, -mv.z);
            gl_Position = projectionMatrix * mv;
            fade = clamp(1.0 - (-mv.z / 170.0), 0.2, 1.0);
          }`,
        fragmentShader: `
          varying float fade;
          void main() {
            float d = distance(gl_PointCoord, vec2(0.5));
            if (d > 0.5) discard;
            gl_FragColor = vec4(0.78, 0.92, 1.0, (1.0 - d * 2.0) * fade * 0.75);
          }`,
      }),
    );
    scene.add(snow);

    const weapon = new THREE.Group();
    camera.add(weapon);
    scene.add(camera);
    weapon.position.set(0.62, -0.7, -0.74);
    weapon.scale.setScalar(0.94);
    const woodTex = makeWoodTexture(THREE);
    const gunMetal = new THREE.MeshStandardMaterial({
      color: 0x424b50,
      metalness: 0.82,
      roughness: 0.32,
      emissive: 0x101619,
      emissiveIntensity: 0.28,
    });
    const gunWood = new THREE.MeshStandardMaterial({
      color: 0x624029,
      map: woodTex,
      roughness: 0.6,
      metalness: 0.02,
    });
    const brass = new THREE.MeshStandardMaterial({
      color: 0x82612f,
      roughness: 0.3,
      metalness: 0.84,
      emissive: 0x351a04,
      emissiveIntensity: 0.16,
    });
    const stockProfile = new THREE.Shape();
    stockProfile.moveTo(-0.15, 0.1);
    stockProfile.lineTo(0.08, 0.14);
    stockProfile.lineTo(0.16, 0.05);
    stockProfile.lineTo(0.07, -0.04);
    stockProfile.lineTo(0.03, -0.18);
    stockProfile.lineTo(-0.12, -0.14);
    stockProfile.lineTo(-0.18, -0.02);
    stockProfile.closePath();
    const stock = new THREE.Mesh(
      new THREE.ExtrudeGeometry(stockProfile, {
        depth: 0.62,
        bevelEnabled: true,
        bevelSegments: 3,
        bevelSize: 0.025,
        bevelThickness: 0.025,
      }),
      gunWood,
    );
    stock.position.set(0.04, -0.03, -0.06);
    stock.rotation.x = Math.PI;
    weapon.add(stock);
    const receiverProfile = new THREE.Shape();
    receiverProfile.moveTo(-0.16, -0.12);
    receiverProfile.lineTo(0.16, -0.1);
    receiverProfile.lineTo(0.135, 0.16);
    receiverProfile.lineTo(-0.12, 0.14);
    receiverProfile.closePath();
    const receiver = new THREE.Mesh(
      new THREE.ExtrudeGeometry(receiverProfile, {
        depth: 0.72,
        bevelEnabled: true,
        bevelSegments: 3,
        bevelSize: 0.024,
        bevelThickness: 0.024,
      }),
      gunMetal,
    );
    receiver.position.set(0, 0, -0.2);
    receiver.rotation.x = Math.PI;
    weapon.add(receiver);
    const receiverTop = new THREE.Mesh(new THREE.BoxGeometry(0.27, 0.07, 0.66), gunMetal);
    receiverTop.position.set(0, 0.17, -0.57);
    receiverTop.rotation.x = -0.025;
    weapon.add(receiverTop);
    const ejectionPort = new THREE.Mesh(
      new THREE.BoxGeometry(0.012, 0.095, 0.27),
      new THREE.MeshStandardMaterial({ color: 0x080a0b, metalness: 0.72, roughness: 0.28 }),
    );
    ejectionPort.position.set(0.166, 0.055, -0.66);
    weapon.add(ejectionPort);
    const receiverPlate = new THREE.Mesh(new THREE.BoxGeometry(0.255, 0.08, 0.38), brass);
    receiverPlate.position.set(0, 0.06, -0.53);
    weapon.add(receiverPlate);
    const magazine = new THREE.Mesh(new THREE.BoxGeometry(0.19, 0.42, 0.28), gunMetal);
    magazine.position.set(0, -0.25, -0.5);
    magazine.rotation.x = -0.16;
    weapon.add(magazine);
    const handguard = new THREE.Mesh(
      new THREE.CylinderGeometry(0.105, 0.12, 0.82, 12),
      gunWood,
    );
    handguard.rotation.x = Math.PI / 2;
    handguard.position.set(0, -0.015, -1.08);
    handguard.scale.x = 0.8;
    weapon.add(handguard);
    for (const z of [-0.78, -1.36]) {
      const band = new THREE.Mesh(new THREE.TorusGeometry(0.092, 0.018, 6, 14), gunMetal);
      band.position.set(0, -0.015, z);
      band.rotation.x = Math.PI / 2;
      weapon.add(band);
    }
    const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.075, 1.18, 18), gunMetal);
    barrel.rotation.x = Math.PI / 2;
    barrel.position.set(0, 0.045, -1.48);
    weapon.add(barrel);
    const sight = new THREE.Mesh(new THREE.TorusGeometry(0.075, 0.015, 7, 16), gunMetal);
    sight.position.set(0, 0.16, -1.98);
    weapon.add(sight);
    const rearSight = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.045, 0.08), gunMetal);
    rearSight.position.set(0, 0.19, -0.58);
    weapon.add(rearSight);
    const rail = new THREE.Mesh(new THREE.BoxGeometry(0.065, 0.035, 0.52), gunMetal);
    rail.position.set(0, 0.16, -0.85);
    weapon.add(rail);
    const bolt = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, 0.25, 10), brass);
    bolt.position.set(0.24, 0.06, -0.53);
    bolt.rotation.z = Math.PI / 2;
    weapon.add(bolt);
    const boltHorn = new THREE.Mesh(
      new THREE.TorusGeometry(0.11, 0.026, 7, 18, Math.PI * 1.25),
      brass,
    );
    boltHorn.position.set(0.34, 0.02, -0.53);
    boltHorn.rotation.y = Math.PI / 2;
    weapon.add(boltHorn);
    const pistolGrip = new THREE.Mesh(
      new THREE.CapsuleGeometry(0.09, 0.28, 5, 10),
      gunWood,
    );
    pistolGrip.position.set(0, -0.25, -0.28);
    pistolGrip.rotation.x = -0.32;
    weapon.add(pistolGrip);
    const triggerGuard = new THREE.Mesh(
      new THREE.TorusGeometry(0.105, 0.014, 6, 18, Math.PI * 1.55),
      brass,
    );
    triggerGuard.position.set(0, -0.13, -0.48);
    triggerGuard.rotation.z = 0.7;
    weapon.add(triggerGuard);
    const muzzleCollar = new THREE.Mesh(
      new THREE.CylinderGeometry(0.09, 0.09, 0.16, 18),
      brass,
    );
    muzzleCollar.position.set(0, 0.045, -2.07);
    muzzleCollar.rotation.x = Math.PI / 2;
    weapon.add(muzzleCollar);
    const goatFur = new THREE.MeshStandardMaterial({
      color: 0x8a8882,
      roughness: 1,
      metalness: 0,
    });
    const hoofMaterial = new THREE.MeshStandardMaterial({
      color: 0x17191a,
      roughness: 0.82,
    });
    const leatherWrap = new THREE.MeshStandardMaterial({
      color: 0x493225,
      roughness: 0.96,
    });
    for (const side of [-1, 1]) {
      const limb = new THREE.Mesh(
        new THREE.CapsuleGeometry(0.14, 0.5, 6, 10),
        goatFur,
      );
      const limbZ = side === 1 ? -0.72 : -0.12;
      limb.position.set(side * 0.2, -0.22, limbZ);
      limb.rotation.z = side * 0.26;
      limb.rotation.x = -0.82;
      weapon.add(limb);
      for (const cleft of [-1, 1]) {
        const hoof = new THREE.Mesh(
          new THREE.CapsuleGeometry(0.048, 0.12, 4, 7),
          hoofMaterial,
        );
        hoof.position.set(
          side * 0.2 + cleft * 0.052,
          -0.43,
          side === 1 ? -0.92 : -0.32,
        );
        hoof.rotation.x = -1;
        weapon.add(hoof);
      }
      const wrap = new THREE.Mesh(
        new THREE.TorusGeometry(0.1, 0.028, 5, 10),
        leatherWrap,
      );
      wrap.position.copy(limb.position);
      weapon.add(wrap);
    }
    const muzzle = new THREE.PointLight(0xffaa55, 0, 7, 2);
    muzzle.position.set(0, 0.03, -2.25);
    weapon.add(muzzle);
    const weaponFill = new THREE.PointLight(0xb7dded, 1.8, 4.2, 1.5);
    weaponFill.position.set(-0.65, 0.8, 0.1);
    weapon.add(weaponFill);
    const weaponWarm = new THREE.PointLight(0xe58a3b, 3, 3.2, 1.8);
    weaponWarm.position.set(0.7, -0.2, 0.1);
    weapon.add(weaponWarm);

    const enemies: Enemy[] = [];
    const worldTargets: THREE.Object3D[] = [
      ground,
      rocks,
      ...coverGroup.children,
      ...outpost.children,
      ...bellGroup.children,
    ];
    const spawnEncounter = (id: 1 | 3) => {
      for (const { x, z, role } of ENCOUNTER_WAVES[id]) {
        enemies.push(
          createWolverine(
            THREE,
            scene,
            new THREE.Vector3(x, ridgeHeight(x, z), z),
            role,
            id,
          ),
        );
      }
    };
    const removeEncounterEnemies = (id: EncounterId) => {
      for (let i = enemies.length - 1; i >= 0; i--) {
        if (enemies[i].encounter !== id) continue;
        scene.remove(enemies[i].group);
        enemies.splice(i, 1);
      }
    };
    spawnEncounter(1);

    const impactParticles: Particle[] = [];
    const spawnImpact = (
      point: THREE.Vector3,
      color: number,
      count: number,
      speed = 5,
    ) => {
      for (let i = 0; i < count; i++) {
        const mesh = new THREE.Mesh(
          new THREE.TetrahedronGeometry(0.025 + Math.random() * 0.05),
          new THREE.MeshBasicMaterial({ color, transparent: true }),
        );
        mesh.position.copy(point);
        scene.add(mesh);
        impactParticles.push({
          mesh,
          velocity: new THREE.Vector3(
            (Math.random() - 0.5) * speed,
            Math.random() * speed,
            (Math.random() - 0.5) * speed,
          ),
          life: 0.35 + Math.random() * 0.35,
        });
      }
    };

    const echoMat = new THREE.MeshBasicMaterial({
      color: 0xe7bd72,
      transparent: true,
      opacity: 0,
      side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const echoRing = new THREE.Mesh(new THREE.SphereGeometry(1, 28, 16), echoMat);
    echoRing.scale.setScalar(0.1);
    scene.add(echoRing);

    const audio = makeAudioEngine();
    const keys = new Set<string>();
    let yaw = 0;
    let pitch = 0.055;
    let verticalVelocity = 0;
    let grounded = true;
    let sprint = false;
    let ads = false;
    let ammo = WEAPON.magazineSize;
    let reserve = WEAPON.startingReserve;
    let reloading = false;
    let health = 100;
    let kills = 0;
    let echoCharge = 1;
    let echoActive = false;
    let echoHolding = false;
    let echoHold = 0;
    let echoTime = 0;
    let recoil = 0;
    let bobTime = 0;
    let lastShot = 0;
    let fireHeld = false;
    let bossSpawned = false;
    let bossKilled = false;
    let encounter: EncounterId = 0;
    let checkpointEncounter: 1 | 3 | 4 = 1;
    let bellRung = false;
    let damageFlash = 0;
    let objective = OBJECTIVE.approach;
    let prompt = "";
    let frame = 0;
    let disposed = false;
    let reloadGeneration = 0;
    let checkpointNoticeUntil = 0;
    const timers = new Set<number>();
    const clock = new THREE.Clock();
    const raycaster = new THREE.Raycaster();
    const forward = new THREE.Vector3();
    const right = new THREE.Vector3();
    const movement = new THREE.Vector3();
    const tmp = new THREE.Vector3();
    const echoAnchor = new THREE.Vector3();

    const schedule = (callback: () => void, delay: number) => {
      const id = window.setTimeout(() => {
        timers.delete(id);
        if (!disposed) callback();
      }, delay);
      timers.add(id);
      return id;
    };

    const updateHud = () => {
      const boss = enemies.find((enemy) => enemy.boss && !enemy.dead);
      onHud({
        ammo,
        reserve,
        health: Math.max(0, Math.round(health)),
        kills,
        total: TOTAL_ENEMIES,
        echo: echoCharge,
        objective,
        prompt,
        boss: boss ? boss.health / boss.maxHealth : bossKilled ? 0 : -1,
        lowHealth: health < 32,
      });
    };

    const reload = () => {
      if (reloading || ammo === WEAPON.magazineSize || reserve <= 0) return;
      reloading = true;
      const generation = ++reloadGeneration;
      audio.reload();
      schedule(() => {
        if (generation !== reloadGeneration) return;
        const amount = Math.min(WEAPON.magazineSize - ammo, reserve);
        ammo += amount;
        reserve -= amount;
        reloading = false;
        updateHud();
      }, WEAPON.reloadMs);
    };

    const spawnBoss = () => {
      const boss = createWolverine(
        THREE,
        scene,
        new THREE.Vector3(0, ridgeHeight(0, -82), -82),
        "boss",
        4,
      );
      enemies.push(boss);
      bossSpawned = true;
      gate.position.y = -5;
      scene.fog = new THREE.FogExp2(0x637984, 0.0165);
    };

    const resetEncounter = () => {
      reloadGeneration++;
      reloading = false;
      fireHeld = false;
      ads = false;
      sprint = false;
      keys.clear();
      echoActive = false;
      echoHolding = false;
      echoMat.opacity = 0;
      renderer.toneMappingExposure = 0.9;

      removeEncounterEnemies(checkpointEncounter);
      if (checkpointEncounter === 1) {
        spawnEncounter(1);
        bellRung = false;
        bossSpawned = false;
        gate.position.y = 4.7;
      } else if (checkpointEncounter === 3) {
        spawnEncounter(3);
        bellRung = true;
        bossSpawned = false;
        gate.position.y = 4.7;
      } else {
        bellRung = true;
        bossKilled = false;
        spawnBoss();
      }

      const checkpoint = CHECKPOINT[checkpointEncounter];
      encounter = checkpointEncounter;
      kills = checkpoint.kills;
      health = 100;
      ammo = WEAPON.magazineSize;
      reserve = Math.max(reserve, 48);
      echoCharge = 1;
      objective = checkpoint.objective;
      checkpointNoticeUntil = performance.now() + 2200;
      camera.position.set(
        checkpoint.x,
        ridgeHeight(checkpoint.x, checkpoint.z) + 1.68,
        checkpoint.z,
      );
      yaw = 0;
      pitch = 0.055;
      verticalVelocity = 0;
      updateHud();
    };

    const killEnemy = (enemy: Enemy, echoKill = false) => {
      if (enemy.dead) return;
      enemy.dead = true;
      enemy.velocity.set(
        (Math.random() - 0.5) * 6,
        echoKill ? 12 : 4,
        echoKill ? -15 : 2,
      );
      enemy.group.rotation.z = (Math.random() - 0.5) * 0.5;
      kills++;
      echoCharge = Math.min(1, echoCharge + (echoKill ? 0.3 : 0.2));
      spawnImpact(enemy.group.position.clone().add(new THREE.Vector3(0, 1.4, 0)), 0xbb2c18, 22, 7);
      if (kills === 3 && encounter === 1) {
        encounter = 2;
        objective = OBJECTIVE.bell;
      }
      if (enemy.boss) {
        bossKilled = true;
        objective = OBJECTIVE.victory;
        audio.echo();
        schedule(onWin, 2100);
      }
      updateHud();
    };

    const shoot = () => {
      const now = performance.now();
      if (
        now - lastShot < WEAPON.fireIntervalMs ||
        reloading ||
        !activeRef.current ||
        (document.pointerLockElement !== renderer.domElement && !fallbackRef.current) ||
        sprint ||
        echoHolding
      ) return;
      if (ammo <= 0) {
        audio.click();
        reload();
        return;
      }
      lastShot = now;
      ammo--;
      recoil = Math.min(recoil + (ads ? 0.018 : 0.032), 0.09);
      muzzle.intensity = 80;
      audio.shot();
      camera.getWorldDirection(forward);
      forward.x += (Math.random() - 0.5) * (ads ? 0.0025 : 0.009);
      forward.y += (Math.random() - 0.5) * (ads ? 0.0025 : 0.009);
      raycaster.set(camera.position, forward.normalize());
      raycaster.far = 180;
      const liveTargets = enemies
        .filter((enemy) => !enemy.dead)
        .flatMap((enemy) => [enemy.head, enemy.body]);
      const hits = raycaster.intersectObjects(liveTargets, false);
      const worldHit = raycaster.intersectObjects(worldTargets, true)[0];
      if (hits.length && (!worldHit || hits[0].distance < worldHit.distance)) {
        const hit = hits[0];
        const target = enemies.find(
          (enemy) => enemy.group === hit.object.userData.root,
        );
        if (target) {
          const critical = Boolean(hit.object.userData.critical);
          const damage = target.boss
            ? critical
              ? 56
              : 27
            : critical
              ? 125
              : 38;
          target.health -= damage;
          target.velocity.addScaledVector(forward, 2.2);
          spawnImpact(hit.point, critical ? 0xffd48a : 0xc9361d, critical ? 18 : 9, 6);
          audio.hit(critical);
          if (target.health <= 0) killEnemy(target);
        }
      } else if (worldHit) {
        spawnImpact(
          worldHit.point,
          worldHit.object === ground ? 0xddeeff : 0xa8b4b6,
          10,
          3.2,
        );
      }
      updateHud();
    };

    const activateEcho = (strength: number) => {
      if (echoCharge < 0.98 || echoActive || !activeRef.current) return;
      echoActive = true;
      echoHolding = false;
      echoCharge = 0;
      echoTime = 0;
      echoRing.position.copy(echoAnchor);
      echoRing.scale.setScalar(0.2);
      echoMat.opacity = 0.85;
      audio.echo();
      renderer.toneMappingExposure = 1.12;
      camera.getWorldDirection(forward);
      for (const enemy of enemies) {
        if (enemy.dead) continue;
        tmp.copy(enemy.group.position).sub(echoAnchor);
        const distance = tmp.length();
        if (distance > 12) continue;
        enemy.material.emissive.set(enemy.boss ? 0xff3311 : 0xff6a22);
        enemy.material.emissiveIntensity = 1.6;
        enemy.velocity
          .addScaledVector(forward, (enemy.boss ? 7 : 13) * strength)
          .setY((enemy.boss ? 4 : 8) + strength * 5);
        enemy.health -= enemy.boss ? 6 : 10;
        if (enemy.health <= 0) killEnemy(enemy, true);
      }
      for (const piece of debris) {
        const distance = piece.mesh.position.distanceTo(echoAnchor);
        if (distance < 12) {
          piece.velocity
            .copy(forward)
            .multiplyScalar(8 + 13 * strength)
            .setY(5 + strength * 11 + Math.random() * 3);
        }
      }
      updateHud();
    };

    const beginEcho = () => {
      if (echoCharge < 0.98 || echoActive || echoHolding) return;
      echoHolding = true;
      echoHold = 0;
      camera.getWorldDirection(forward);
      raycaster.set(camera.position, forward);
      raycaster.far = 35;
      const anchorHit = raycaster.intersectObjects(worldTargets, true)[0];
      echoAnchor.copy(
        anchorHit?.point ?? camera.position.clone().addScaledVector(forward, 20),
      );
      echoRing.position.copy(echoAnchor);
      echoRing.scale.setScalar(12);
      echoMat.opacity = 0.14;
    };

    const releaseEcho = () => {
      if (!echoHolding) return;
      const strength = THREE.MathUtils.clamp(echoHold / 1.2, 0.25, 1);
      activateEcho(strength);
    };

    const onPointerLock = () => {
      const locked = document.pointerLockElement === renderer.domElement;
      if (!locked && !fallbackRef.current) {
        keys.clear();
        fireHeld = false;
        ads = false;
      }
      onLocked(locked || fallbackRef.current);
    };
    const controlsActive = () =>
      activeRef.current &&
      (document.pointerLockElement === renderer.domElement || fallbackRef.current);
    const onMouseMove = (event: MouseEvent) => {
      if (!controlsActive()) return;
      yaw -= event.movementX * 0.00175;
      pitch -= event.movementY * 0.00155;
      pitch = THREE.MathUtils.clamp(pitch, -1.35, 1.25);
    };
    const onMouseDown = (event: MouseEvent) => {
      if (!controlsActive()) return;
      if (event.button === 0) {
        fireHeld = true;
        shoot();
      }
      if (event.button === 2) ads = true;
    };
    const onMouseUp = (event: MouseEvent) => {
      if (event.button === 0) fireHeld = false;
      if (event.button === 2) ads = false;
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (!controlsActive()) return;
      keys.add(event.code);
      if (event.code === "KeyR") reload();
      if (event.code === "KeyQ" && !event.repeat) beginEcho();
      if (event.code === "KeyE" && encounter === 2) {
        const bellDistance = camera.position.distanceTo(bellGroup.position);
        if (bellDistance < 7) {
          bellRung = true;
          encounter = 3;
          checkpointEncounter = 3;
          echoCharge = 1;
          objective = OBJECTIVE.siege;
          audio.echo();
          schedule(() => spawnEncounter(3), 1800);
        }
      }
      if (event.code === "Space" && grounded) {
        verticalVelocity = 7.2;
        grounded = false;
      }
    };
    const onKeyUp = (event: KeyboardEvent) => {
      keys.delete(event.code);
      if (event.code === "KeyQ") releaseEcho();
    };
    const onContext = (event: MouseEvent) => event.preventDefault();
    const onBlur = () => {
      keys.clear();
      fireHeld = false;
      ads = false;
    };
    const onVisibilityChange = () => {
      if (document.hidden) onBlur();
      clock.getDelta();
    };
    const onCanvasClick = () => {
      if (
        activeRef.current &&
        !fallbackRef.current &&
        document.pointerLockElement !== renderer.domElement
      ) {
        const request = renderer.domElement.requestPointerLock();
        if (request) void request.catch(() => {});
        audio.start();
      }
    };
    const onAudioStart = () => audio.start();
    const onPlayerStart = () => {
      camera.position.set(0, ridgeHeight(0, 28) + 1.68, 28);
      yaw = 0;
      pitch = 0.055;
      verticalVelocity = 0;
    };

    document.addEventListener("pointerlockchange", onPointerLock);
    document.addEventListener("mousemove", onMouseMove);
    document.addEventListener("mousedown", onMouseDown);
    document.addEventListener("mouseup", onMouseUp);
    document.addEventListener("keydown", onKeyDown);
    document.addEventListener("keyup", onKeyUp);
    renderer.domElement.addEventListener("click", onCanvasClick);
    renderer.domElement.addEventListener("contextmenu", onContext);
    window.addEventListener("goat-audio-start", onAudioStart);
    window.addEventListener("goat-player-start", onPlayerStart);
    window.addEventListener("blur", onBlur);
    document.addEventListener("visibilitychange", onVisibilityChange);
    onReady(true);

    const resize = () => {
      if (!mount) return;
      const width = mount.clientWidth;
      const height = mount.clientHeight;
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height);
      composer.setSize(width, height);
    };
    window.addEventListener("resize", resize);
    resize();
    updateHud();

    const animate = () => {
      if (disposed) return;
      requestAnimationFrame(animate);
      const dt = Math.min(clock.getDelta(), 0.033);
      frame++;

      const hasControls =
        activeRef.current &&
        (document.pointerLockElement === renderer.domElement || fallbackRef.current);
      if (hasControls) {
        const previousX = camera.position.x;
        const previousZ = camera.position.z;
        const turnSpeed = 1.65 * dt;
        if (keys.has("ArrowLeft")) yaw += turnSpeed;
        if (keys.has("ArrowRight")) yaw -= turnSpeed;
        if (keys.has("ArrowUp")) pitch = Math.min(1.25, pitch + turnSpeed);
        if (keys.has("ArrowDown")) pitch = Math.max(-1.35, pitch - turnSpeed);
        sprint = keys.has("ShiftLeft") || keys.has("ShiftRight");
        movement.set(0, 0, 0);
        forward.set(Math.sin(yaw), 0, -Math.cos(yaw));
        right.set(Math.cos(yaw), 0, Math.sin(yaw));
        if (keys.has("KeyW")) movement.add(forward);
        if (keys.has("KeyS")) movement.sub(forward);
        if (keys.has("KeyD")) movement.add(right);
        if (keys.has("KeyA")) movement.sub(right);
        if (movement.lengthSq() > 0) {
          movement.normalize();
          const speed = echoHolding ? 2.7 : ads ? 3.4 : sprint ? 8.4 : 5.4;
          camera.position.addScaledVector(movement, speed * dt);
          bobTime += dt * (sprint ? 13 : 8.5);
        }
        if (fireHeld) shoot();
        camera.position.x = THREE.MathUtils.clamp(camera.position.x, -11.5, 11.5);
        camera.position.z = THREE.MathUtils.clamp(camera.position.z, -91, 34);
        for (const [cx, cz, radius] of playerColliders) {
          const dx = camera.position.x - cx;
          const dz = camera.position.z - cz;
          if (dx * dx + dz * dz < radius ** 2) {
            camera.position.x = previousX;
            camera.position.z = previousZ;
            break;
          }
        }
        if (
          camera.position.z < -73.8 &&
          camera.position.z > -79 &&
          Math.abs(camera.position.x) < 5.1 &&
          !bossSpawned
        ) {
          camera.position.x = previousX;
          camera.position.z = previousZ;
        }
        verticalVelocity -= 19 * dt;
        camera.position.y += verticalVelocity * dt;
        const floor = ridgeHeight(camera.position.x, camera.position.z) + 1.68;
        if (camera.position.y <= floor) {
          camera.position.y = floor;
          verticalVelocity = 0;
          grounded = true;
        }
      }

      camera.rotation.y = yaw;
      if (activeRef.current) {
        camera.rotation.y = yaw;
        camera.rotation.x =
          pitch - recoil + (damageFlash > 0 ? Math.sin(frame * 2.9) * 0.006 : 0);
      } else {
        camera.position.set(
          0.8 + Math.sin(frame * 0.002) * 0.45,
          18.5 + Math.sin(frame * 0.0012) * 0.25,
          38 + Math.cos(frame * 0.0016) * 0.4,
        );
        camera.lookAt(0, 5.5, -74);
      }
      weapon.visible = activeRef.current;
      recoil = THREE.MathUtils.damp(recoil, 0, 16, dt);
      camera.fov = THREE.MathUtils.damp(
        camera.fov,
        ads ? WEAPON.adsFov : WEAPON.hipFov,
        14,
        dt,
      );
      camera.updateProjectionMatrix();
      const bob = hasControls && movement.lengthSq() ? Math.sin(bobTime) : 0;
      const adsX = ads ? 0 : 0.5;
      const adsY = ads ? -0.24 : -0.48;
      const adsZ = ads ? -0.82 : -0.63;
      weapon.position.x = THREE.MathUtils.damp(weapon.position.x, adsX + bob * 0.012, 12, dt);
      weapon.position.y = THREE.MathUtils.damp(
        weapon.position.y,
        adsY + Math.abs(bob) * 0.012 - recoil * 2.5,
        12,
        dt,
      );
      weapon.position.z = THREE.MathUtils.damp(weapon.position.z, adsZ, 12, dt);
      weapon.rotation.z = THREE.MathUtils.damp(weapon.rotation.z, -bob * 0.008, 9, dt);
      muzzle.intensity = THREE.MathUtils.damp(muzzle.intensity, 0, 45, dt);

      const snowArray = snowGeo.attributes.position.array as Float32Array;
      const reverse = echoActive ? -1 : 1;
      for (let i = 0; i < snowCount; i++) {
        snowArray[i * 3] += dt * 4.2 * reverse;
        snowArray[i * 3 + 1] -= dt * (4.2 + (i % 7) * 0.16) * reverse;
        if (snowArray[i * 3 + 1] < -5) snowArray[i * 3 + 1] = 50;
        if (snowArray[i * 3 + 1] > 52) snowArray[i * 3 + 1] = -4;
        if (snowArray[i * 3] > 75) snowArray[i * 3] = -75;
        if (snowArray[i * 3] < -75) snowArray[i * 3] = 75;
      }
      snowGeo.attributes.position.needsUpdate = true;
      snow.position.z = camera.position.z * 0.05;

      if (echoHolding) {
        echoHold = Math.min(1.5, echoHold + dt);
        echoMat.opacity = 0.1 + Math.min(0.34, echoHold * 0.2);
        echoRing.rotation.y += dt * (0.8 + echoHold * 2.4);
        renderer.toneMappingExposure = 0.9 + Math.min(0.18, echoHold * 0.12);
      } else if (echoActive) {
        echoTime += dt;
        const scale = 0.2 + echoTime * 46;
        echoRing.scale.setScalar(scale);
        echoMat.opacity = Math.max(0, 0.72 - echoTime * 0.62);
        if (echoTime > 1.25) {
          echoActive = false;
          echoMat.opacity = 0;
          renderer.toneMappingExposure = 0.9;
          for (const enemy of enemies) {
            enemy.material.emissiveIntensity = enemy.boss ? 0.26 : 0;
          }
        }
      } else {
        echoCharge = Math.min(1, echoCharge + dt / 24);
      }

      for (const piece of debris) {
        if (piece.velocity.lengthSq() > 0.01) {
          piece.velocity.y -= 12 * dt;
          piece.mesh.position.addScaledVector(piece.velocity, dt);
          piece.mesh.rotation.x += piece.velocity.z * dt * 0.2;
          piece.mesh.rotation.z += piece.velocity.x * dt * 0.2;
          const floor = ridgeHeight(piece.mesh.position.x, piece.mesh.position.z) + 0.25;
          if (piece.mesh.position.y < floor) {
            piece.mesh.position.y = floor;
            piece.velocity.y *= -0.22;
            piece.velocity.x *= 0.72;
            piece.velocity.z *= 0.72;
          }
          if (piece.velocity.length() > 13) {
            for (const enemy of enemies) {
              if (
                !enemy.dead &&
                piece.mesh.position.distanceTo(enemy.group.position) < (enemy.boss ? 1.8 : 1.25)
              ) {
                enemy.health -= enemy.boss ? 34 : 82;
                enemy.velocity.addScaledVector(piece.velocity, 0.38);
                spawnImpact(piece.mesh.position, 0xe6bd73, 14, 6);
                piece.velocity.multiplyScalar(0.22);
                if (enemy.health <= 0) killEnemy(enemy, true);
              }
            }
          }
        }
      }

      if (hasControls && encounter !== 0 && encounter !== 2) {
        for (const enemy of enemies) {
          if (enemy.dead) {
            enemy.velocity.y -= 15 * dt;
            enemy.group.position.addScaledVector(enemy.velocity, dt);
            enemy.group.rotation.x += dt * 1.4;
            if (enemy.group.position.y < -18) enemy.group.visible = false;
            continue;
          }
          enemy.phase += dt;
          enemy.cooldown -= dt;
          tmp.copy(camera.position).sub(enemy.group.position);
          tmp.y = 0;
          const distance = tmp.length();
          const desired =
            ENEMY_ROLE[enemy.role].desiredRange +
            (enemy.role === "rifleman" ? Math.sin(enemy.phase) * 4 : 0);
          if (distance > desired) {
            tmp.normalize();
            const roleSpeed =
              enemy.role === "stalker" && distance < 7 && enemy.cooldown < 0.55
                ? enemy.speed * 1.65
                : enemy.speed;
            enemy.velocity.x = THREE.MathUtils.damp(enemy.velocity.x, tmp.x * roleSpeed, 3, dt);
            enemy.velocity.z = THREE.MathUtils.damp(enemy.velocity.z, tmp.z * roleSpeed, 3, dt);
          } else {
            tmp.normalize();
            const strafeX = -tmp.z * Math.sin(enemy.phase * 1.8);
            const strafeZ = tmp.x * Math.sin(enemy.phase * 1.8);
            enemy.velocity.x = THREE.MathUtils.damp(enemy.velocity.x, strafeX * enemy.speed, 3, dt);
            enemy.velocity.z = THREE.MathUtils.damp(enemy.velocity.z, strafeZ * enemy.speed, 3, dt);
          }
          enemy.velocity.y -= 16 * dt;
          const enemyPreviousX = enemy.group.position.x;
          const enemyPreviousZ = enemy.group.position.z;
          enemy.group.position.addScaledVector(enemy.velocity, dt);
          for (const [cx, cz, radius] of playerColliders) {
            const dx = enemy.group.position.x - cx;
            const dz = enemy.group.position.z - cz;
            if (dx * dx + dz * dz < (radius + 0.4) ** 2) {
              enemy.group.position.x = enemyPreviousX;
              enemy.group.position.z = enemyPreviousZ;
              enemy.velocity.x *= -0.2;
              enemy.velocity.z *= -0.2;
              break;
            }
          }
          const enemyFloor = ridgeHeight(enemy.group.position.x, enemy.group.position.z);
          if (enemy.group.position.y < enemyFloor) {
            enemy.group.position.y = enemyFloor;
            enemy.velocity.y = 0;
          }
          enemy.group.lookAt(camera.position.x, enemy.group.position.y + 1.4, camera.position.z);
          enemy.body.rotation.z = Math.sin(enemy.phase * 4) * 0.025;
          if (
            enemy.cooldown <= 0 &&
            distance < (enemy.role === "stalker" ? 4.2 : enemy.boss ? 54 : 39)
          ) {
            const baseCooldown = ENEMY_ROLE[enemy.role].cooldown;
            enemy.cooldown =
              baseCooldown +
              (enemy.role === "boss"
                ? Math.random() * 0.55
                : enemy.role === "rifleman"
                  ? Math.random() * 1.2
                  : 0);
            audio.enemyShot();
            tmp.copy(camera.position).sub(enemy.group.position);
            const shotDistance = tmp.length();
            raycaster.set(
              enemy.group.position.clone().add(new THREE.Vector3(0, 1.5, 0)),
              tmp.normalize(),
            );
            raycaster.far = shotDistance;
            const coverHit = raycaster.intersectObjects(worldTargets, true)[0];
            const accuracy =
              enemy.role === "stalker"
                ? 1
                : enemy.role === "brute"
                  ? 0.62
                  : enemy.boss
                    ? 0.7
                    : 0.43;
            if (!coverHit && Math.random() < accuracy) {
              const damage =
                enemy.role === "stalker"
                  ? 18
                  : enemy.role === "brute"
                    ? 13 + Math.random() * 7
                    : enemy.boss
                      ? 8 + Math.random() * 7
                      : 5 + Math.random() * 7;
              health -= damage;
              damageFlash = 1;
              audio.hurt();
              if (health <= 0) {
                resetEncounter();
                break;
              }
              updateHud();
            }
            const tracer = new THREE.Mesh(
              new THREE.BoxGeometry(0.025, 0.025, distance),
              new THREE.MeshBasicMaterial({
                color: 0xff6a28,
                transparent: true,
                opacity: 0.55,
                blending: THREE.AdditiveBlending,
              }),
            );
            tracer.position.copy(enemy.group.position).lerp(camera.position, 0.5);
            tracer.position.y += 1.4;
            tracer.lookAt(camera.position);
            scene.add(tracer);
            impactParticles.push({ mesh: tracer, velocity: new THREE.Vector3(), life: 0.055 });
          }
        }
      }

      for (let i = impactParticles.length - 1; i >= 0; i--) {
        const particle = impactParticles[i];
        particle.life -= dt;
        particle.velocity.y -= 9 * dt;
        particle.mesh.position.addScaledVector(particle.velocity, dt);
        particle.mesh.rotation.x += dt * 8;
        const material = particle.mesh.material as THREE.Material & { opacity?: number };
        if (typeof material.opacity === "number") material.opacity = Math.max(0, particle.life * 2);
        if (particle.life <= 0) {
          scene.remove(particle.mesh);
          particle.mesh.geometry.dispose();
          material.dispose();
          impactParticles.splice(i, 1);
        }
      }

      damageFlash = Math.max(0, damageFlash - dt * 2.4);
      lanterns.forEach((light, index) => {
        light.intensity = 19 + Math.sin(frame * 0.08 + index) * 5 + Math.random() * 2;
      });
      const bellDistance = camera.position.distanceTo(bellGroup.position);
      if (encounter === 0 && camera.position.z < 12) {
        encounter = 1;
        checkpointEncounter = 1;
        objective = OBJECTIVE.ambush;
      }
      if (encounter === 2 && bellDistance < 7) {
        prompt = "E  RING THE STOLEN BELL";
      } else if (performance.now() < checkpointNoticeUntil) {
        prompt = "CHECKPOINT RESTORED";
      } else if (echoHolding) {
        prompt = `BENDING GRAVITY  ${Math.round(Math.min(1, echoHold / 1.2) * 100)}%`;
      } else {
        prompt = "";
      }
      if (bellRung && kills >= 8 && camera.position.z < -64 && !bossSpawned) {
        encounter = 4;
        checkpointEncounter = 4;
        objective = OBJECTIVE.boss;
        spawnBoss();
      } else if (bellRung && kills < 8 && camera.position.z < -28) {
        objective = OBJECTIVE.siege;
      } else if (bellRung && kills >= 8 && !bossSpawned) {
        objective = OBJECTIVE.gate;
      }
      if (frame % 12 === 0) {
        audio.setWind(sprint ? 0.14 : health < 32 ? 0.045 : 0.075);
        updateHud();
      }
      composer.render();
    };
    animate();

    return () => {
      disposed = true;
      timers.forEach((timer) => window.clearTimeout(timer));
      timers.clear();
      onReady(false);
      audio.stop();
      document.removeEventListener("pointerlockchange", onPointerLock);
      document.removeEventListener("mousemove", onMouseMove);
      document.removeEventListener("mousedown", onMouseDown);
      document.removeEventListener("mouseup", onMouseUp);
      document.removeEventListener("keydown", onKeyDown);
      document.removeEventListener("keyup", onKeyUp);
      renderer.domElement.removeEventListener("click", onCanvasClick);
      renderer.domElement.removeEventListener("contextmenu", onContext);
      window.removeEventListener("goat-audio-start", onAudioStart);
      window.removeEventListener("goat-player-start", onPlayerStart);
      window.removeEventListener("resize", resize);
      window.removeEventListener("blur", onBlur);
      document.removeEventListener("visibilitychange", onVisibilityChange);
      renderer.dispose();
      composer.dispose();
      snowTex.dispose();
      rockTex.dispose();
      woodTex.dispose();
      fortressMatteTexture.dispose();
      fortressMatte.geometry.dispose();
      (fortressMatte.material as THREE.Material).dispose();
      cliffGeometry.dispose();
      cliffMaterial.dispose();
      mount.removeChild(renderer.domElement);
    };
    };

    void boot().then((cleanup) => {
      if (!cleanup) return;
      if (cancelled) {
        cleanup();
      } else {
        teardown = cleanup;
      }
    });

    return () => {
      cancelled = true;
      teardown?.();
    };
  }, [onHud, onLocked, onReady, onWin]);

  return <div ref={mountRef} className="game-canvas" aria-hidden="true" />;
}

function StartScreen({ onStart, ready }: { onStart: () => void; ready: boolean }) {
  return (
    <section className="start-screen">
      <div className="start-vignette" />
      <div className="title-stack">
        <div className="title-rule" />
        <h1>
          <span>MOUNTAIN</span>
          <strong>GOAT KILLER</strong>
        </h1>
        <p className="tagline">THE MOUNTAIN REMEMBERS EVERY CRY.</p>
      </div>
      <div className="mission-card">
        <div>
          <span className="eyebrow">MISSION 01</span>
          <strong>THE LAST BELL</strong>
        </div>
        <p>
          Varkas took your herd. Tonight, you take back the mountain.
        </p>
      </div>
      <button
        className="deploy-button"
        onClick={onStart}
        data-testid="deploy"
        disabled={!ready}
      >
        <span>{ready ? "DEPLOY" : "PREPARING THE PASS"}</span>
        <small>{ready ? "ENTER THE RAVINE" : "LOADING FIELD SYSTEMS"}</small>
      </button>
      <div className="controls-strip">
        <span><b>WASD</b> MOVE</span>
        <span><b>MOUSE</b> AIM</span>
        <span><b>LMB</b> FIRE</span>
        <span><b>RMB</b> FOCUS</span>
        <span><b>SHIFT</b> SPRINT</span>
        <span><b>Q</b> ECHOHORN</span>
        <span><b>R</b> RELOAD</span>
      </div>
      <div className="rating">HEADPHONES RECOMMENDED <i /></div>
    </section>
  );
}

export default function Home() {
  const [started, setStarted] = useState(false);
  const [locked, setLocked] = useState(false);
  const [fallbackControls, setFallbackControls] = useState(false);
  const [gameReady, setGameReady] = useState(false);
  const [won, setWon] = useState(false);
  const [hud, setHud] = useState<HudState>(initialHud);
  const handleWin = useCallback(() => setWon(true), []);
  const requestGameControls = (resetPlayer = false) => {
    window.dispatchEvent(new Event("goat-audio-start"));
    if (resetPlayer) window.dispatchEvent(new Event("goat-player-start"));
    setStarted(true);
    setLocked(false);
    setFallbackControls(false);

    const enableFallback = () => {
      setFallbackControls(true);
      setLocked(true);
    };

    const canvas = document.querySelector<HTMLCanvasElement>("canvas");
    if (!canvas || typeof canvas.requestPointerLock !== "function") {
      enableFallback();
      return;
    }

    try {
      const request = canvas.requestPointerLock();
      if (request) void request.catch(enableFallback);
      document.addEventListener("pointerlockerror", enableFallback, { once: true });
      document.addEventListener(
        "pointerlockchange",
        () => document.removeEventListener("pointerlockerror", enableFallback),
        { once: true },
      );
    } catch {
      enableFallback();
    }
  };
  const enterGame = () => requestGameControls(true);

  return (
    <main className={`game-shell ${hud.lowHealth ? "is-hurt" : ""}`}>
      <GameCanvas
        active={started && !won}
        fallbackControls={fallbackControls}
        onHud={setHud}
        onLocked={setLocked}
        onReady={setGameReady}
        onWin={handleWin}
      />
      {!started && <StartScreen onStart={enterGame} ready={gameReady} />}

      {started && !won && (
        <div className="hud">
          <div className="cinematic-bars" />
          <div className="mission-label">
            <span>OBJECTIVE</span>
            <strong>{hud.objective}</strong>
          </div>
          <div className="compass">
            <i />
            <span>NW</span><b>340</b><span>N</span><b>018</b><span>NE</span>
          </div>
          <div className={`crosshair ${locked ? "" : "paused"}`}>
            <i /><i /><i /><i />
            <span style={{ "--echo": `${hud.echo * 360}deg` } as React.CSSProperties} />
          </div>
          <div className="weapon-info">
            <div className="weapon-name">
              <span>HERDKEEPER</span>
              <strong>CARBINE / 7.62</strong>
            </div>
            <div className="ammo">
              <strong>{String(hud.ammo).padStart(2, "0")}</strong>
              <span>/ {hud.reserve}</span>
            </div>
          </div>
          <div className="status-panel">
            <div className="health-dashes">
              {Array.from({ length: 5 }).map((_, i) => (
                <i key={i} className={hud.health > i * 20 ? "live" : ""} />
              ))}
            </div>
            <span>HERD // LAST SURVIVOR</span>
          </div>
          <div className="threat-counter">
            <span>VARKAS&apos; WARPACK</span>
            <strong>{hud.kills}<small> / {hud.total}</small></strong>
          </div>
          {hud.prompt && <div className="world-prompt">{hud.prompt}</div>}
          {hud.boss >= 0 && (
            <div className="boss-bar">
              <span>VARKAS // IRON WOLVERINE</span>
              <i><b style={{ width: `${hud.boss * 100}%` }} /></i>
            </div>
          )}
          {!locked && (
            <button
              className="resume"
              onClick={() => requestGameControls(false)}
            >
              <span>FIELD PAUSED</span>
              CLICK TO RE-ENTER
            </button>
          )}
          {fallbackControls && (
            <div className="fallback-hint">
              LIMITED MOUSE CAPTURE <span>MOVE MOUSE OR USE ARROW KEYS TO AIM</span>
            </div>
          )}
          <div className="echo-callout">
            <kbd>Q</kbd>
            <div>
              <span>ECHOHORN</span>
              <i><b style={{ width: `${hud.echo * 100}%` }} /></i>
            </div>
          </div>
        </div>
      )}

      {won && (
        <section className="victory">
          <div className="victory-halo" />
          <span className="eyebrow">MISSION COMPLETE</span>
          <h2>THE MOUNTAIN<br />REMEMBERS.</h2>
          <p>Varkas is dead. Nine stolen bells ring again in the blue hour.</p>
          <div className="victory-stats">
            <span><b>{hud.kills}</b> ENEMIES SILENCED</span>
            <span><b>{hud.health}</b> WILL REMAINING</span>
          </div>
          <button
            className="deploy-button"
            onClick={() => window.location.reload()}
          >
            <span>PLAY AGAIN</span>
            <small>RETURN TO THE RAVINE</small>
          </button>
        </section>
      )}
      <div className="grain" />
      <div className="hurt-flash" />
    </main>
  );
}
