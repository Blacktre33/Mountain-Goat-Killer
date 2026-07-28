"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { EffectComposer } from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass } from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/examples/jsm/postprocessing/OutputPass.js";

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
  ammo: 24,
  reserve: 96,
  health: 100,
  kills: 0,
  total: 9,
  echo: 1,
  objective: "Reach the stolen bell",
  prompt: "",
  boss: 0,
  lowHealth: false,
};

const ridgeHeight = (x: number, z: number) => {
  const base = Math.sin(x * 0.055) * 0.7 + Math.cos(z * 0.045) * 0.55;
  const detail = Math.sin((x + z) * 0.12) * 0.22;
  const path = Math.max(0, Math.abs(x) - 9) * 0.18;
  return base + detail + path - 2.2;
};

function makeNoiseTexture(size = 256) {
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d")!;
  const image = ctx.createImageData(size, size);
  for (let i = 0; i < image.data.length; i += 4) {
    const grain =
      195 +
      (Math.random() - 0.5) * 34 +
      (Math.random() - 0.5) * 18;
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

function makeRockTexture(size = 256) {
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d")!;
  ctx.fillStyle = "#252e32";
  ctx.fillRect(0, 0, size, size);
  for (let i = 0; i < 1800; i++) {
    const v = 34 + Math.random() * 45;
    ctx.fillStyle = `rgba(${v},${v + 7},${v + 9},${Math.random() * 0.2})`;
    const r = Math.random() * 3 + 0.3;
    ctx.fillRect(Math.random() * size, Math.random() * size, r * 3, r);
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(2, 3);
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
  scene: THREE.Scene,
  position: THREE.Vector3,
  boss = false,
): Enemy {
  const group = new THREE.Group();
  group.position.copy(position);
  const armor = new THREE.MeshStandardMaterial({
    color: boss ? 0x3a0b08 : 0x121719,
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
    new THREE.CapsuleGeometry(boss ? 0.72 : 0.52, boss ? 1.6 : 1.2, 5, 10),
    armor,
  );
  body.position.y = boss ? 1.45 : 1.1;
  body.castShadow = true;
  body.userData.enemy = true;
  group.add(body);

  const head = new THREE.Mesh(
    new THREE.DodecahedronGeometry(boss ? 0.58 : 0.43, 1),
    fur,
  );
  head.position.set(0, boss ? 2.62 : 2.05, 0.06);
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
    health: boss ? 420 : 100,
    maxHealth: boss ? 420 : 100,
    speed: boss ? 3.2 : 2.15 + Math.random() * 0.75,
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
  onHud,
  onLocked,
  onWin,
}: {
  active: boolean;
  onHud: (state: HudState) => void;
  onLocked: (locked: boolean) => void;
  onWin: () => void;
}) {
  const mountRef = useRef<HTMLDivElement>(null);
  const activeRef = useRef(active);

  useEffect(() => {
    activeRef.current = active;
  }, [active]);

  useEffect(() => {
    const mount = mountRef.current;
    if (!mount) return;

    const scene = new THREE.Scene();
    scene.fog = new THREE.FogExp2(0x8cabbc, 0.0135);
    const camera = new THREE.PerspectiveCamera(74, 1, 0.05, 520);
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
    renderer.toneMappingExposure = 1.05;
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    mount.appendChild(renderer.domElement);

    const composer = new EffectComposer(renderer);
    composer.addPass(new RenderPass(scene, camera));
    const bloom = new UnrealBloomPass(
      new THREE.Vector2(mount.clientWidth, mount.clientHeight),
      0.28,
      0.65,
      0.88,
    );
    composer.addPass(bloom);
    composer.addPass(new OutputPass());

    const sky = new THREE.Mesh(
      new THREE.SphereGeometry(390, 32, 20),
      new THREE.ShaderMaterial({
        side: THREE.BackSide,
        uniforms: {
          top: { value: new THREE.Color(0x08131f) },
          horizon: { value: new THREE.Color(0x668698) },
          glow: { value: new THREE.Color(0xd6a46d) },
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
            color += glow * dusk * 0.25;
            gl_FragColor = vec4(color, 1.0);
          }`,
      }),
    );
    scene.add(sky);

    const hemi = new THREE.HemisphereLight(0xbad9e7, 0x162023, 1.65);
    scene.add(hemi);
    const sun = new THREE.DirectionalLight(0xf7d1a2, 3.35);
    sun.position.set(-34, 42, 22);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.camera.left = -62;
    sun.shadow.camera.right = 62;
    sun.shadow.camera.top = 70;
    sun.shadow.camera.bottom = -38;
    sun.shadow.camera.near = 1;
    sun.shadow.camera.far = 150;
    sun.shadow.bias = -0.00015;
    scene.add(sun);

    const moon = new THREE.PointLight(0x7fc9ff, 14, 95, 1.4);
    moon.position.set(20, 32, -70);
    scene.add(moon);

    const snowTex = makeNoiseTexture();
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
        color: 0xb7cfda,
        roughness: 0.72,
        metalness: 0.04,
        bumpMap: snowTex,
        bumpScale: 0.08,
      }),
    );
    ground.receiveShadow = true;
    scene.add(ground);

    const rockTex = makeRockTexture();
    const rockMat = new THREE.MeshStandardMaterial({
      map: rockTex,
      color: 0x536067,
      roughness: 0.92,
      metalness: 0.03,
    });
    const rockGeo = new THREE.DodecahedronGeometry(1, 1);
    const rocks = new THREE.InstancedMesh(rockGeo, rockMat, 140);
    rocks.castShadow = true;
    rocks.receiveShadow = true;
    const dummy = new THREE.Object3D();
    for (let i = 0; i < 140; i++) {
      const side = i % 2 ? 1 : -1;
      const z = 38 - Math.random() * 195;
      const x = side * (10 + Math.random() * 45);
      const s = 1.8 + Math.random() * 7.5;
      dummy.position.set(x, ridgeHeight(x, z) + s * 0.28 - 1.2, z);
      dummy.rotation.set(Math.random(), Math.random() * Math.PI, Math.random());
      dummy.scale.set(s * (0.7 + Math.random()), s, s * (0.8 + Math.random()));
      dummy.updateMatrix();
      rocks.setMatrixAt(i, dummy.matrix);
    }
    scene.add(rocks);

    const mountainMat = new THREE.MeshStandardMaterial({
      color: 0x34444c,
      roughness: 1,
      flatShading: true,
    });
    for (let i = 0; i < 21; i++) {
      const mountain = new THREE.Mesh(
        new THREE.ConeGeometry(22 + Math.random() * 30, 55 + Math.random() * 65, 7),
        mountainMat,
      );
      const angle = (i / 21) * Math.PI * 1.4 + 0.75;
      const distance = 105 + Math.random() * 90;
      mountain.position.set(
        Math.cos(angle) * distance,
        9 + Math.random() * 7,
        Math.sin(angle) * distance - 60,
      );
      mountain.rotation.y = Math.random() * Math.PI;
      scene.add(mountain);
    }

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

    const outpost = new THREE.Group();
    outpost.position.set(0, ridgeHeight(0, -76), -76);
    for (const x of [-7.6, 7.6]) {
      const tower = new THREE.Mesh(new THREE.BoxGeometry(3.4, 11, 3.4), rockMat);
      tower.position.set(x, 4.6, 0);
      tower.castShadow = tower.receiveShadow = true;
      outpost.add(tower);
      for (const y of [0.5, 4.3, 8]) {
        const slit = new THREE.Mesh(new THREE.BoxGeometry(3.52, 0.35, 0.22), emberMat);
        slit.position.set(x, y, -1.73);
        outpost.add(slit);
      }
    }
    const archTop = new THREE.Mesh(new THREE.BoxGeometry(19, 2.6, 4.2), rockMat);
    archTop.position.y = 9.2;
    outpost.add(archTop);
    const gate = new THREE.Mesh(new THREE.BoxGeometry(8.5, 8.4, 0.5), ironMat);
    gate.position.set(0, 3.9, 0);
    outpost.add(gate);
    for (const x of [-12, -8, -4, 0, 4, 8, 12]) {
      const post = new THREE.Mesh(new THREE.BoxGeometry(0.32, 5.6, 0.32), timberMat);
      post.position.set(x, 2.5, 7);
      post.rotation.z = Math.sin(x) * 0.07;
      outpost.add(post);
    }
    scene.add(outpost);

    const bellGroup = new THREE.Group();
    const bell = new THREE.Mesh(
      new THREE.CylinderGeometry(1.25, 1.75, 2.3, 18, 1, true),
      new THREE.MeshStandardMaterial({
        color: 0x8b6330,
        roughness: 0.3,
        metalness: 0.88,
        emissive: 0x5f3005,
        emissiveIntensity: 0.35,
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
    bellGroup.position.set(0, ridgeHeight(0, -31), -31);
    scene.add(bellGroup);

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
    for (let i = 0; i < 28; i++) {
      const mesh = new THREE.Mesh(
        i % 3 === 0
          ? new THREE.BoxGeometry(0.45, 0.45, 1.6)
          : new THREE.DodecahedronGeometry(0.35 + Math.random() * 0.5, 0),
        i % 3 === 0 ? timberMat : rockMat,
      );
      const z = 22 - Math.random() * 105;
      const x = (Math.random() - 0.5) * 23;
      mesh.position.set(x, ridgeHeight(x, z) + 0.6, z);
      mesh.rotation.set(Math.random(), Math.random(), Math.random());
      mesh.castShadow = true;
      scene.add(mesh);
      debris.push({ mesh, velocity: new THREE.Vector3(), life: Infinity });
    }

    const snowCount = 3900;
    const snowPositions = new Float32Array(snowCount * 3);
    const snowSizes = new Float32Array(snowCount);
    for (let i = 0; i < snowCount; i++) {
      snowPositions[i * 3] = (Math.random() - 0.5) * 150;
      snowPositions[i * 3 + 1] = Math.random() * 54 - 4;
      snowPositions[i * 3 + 2] = Math.random() * 230 - 160;
      snowSizes[i] = 0.8 + Math.random() * 1.7;
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
    weapon.position.set(0.42, -0.43, -0.72);
    weapon.scale.setScalar(0.78);
    const gunMetal = new THREE.MeshStandardMaterial({
      color: 0x4a5357,
      metalness: 0.82,
      roughness: 0.26,
    });
    const gunWood = new THREE.MeshStandardMaterial({
      color: 0x754325,
      roughness: 0.38,
      metalness: 0.02,
    });
    const brass = new THREE.MeshStandardMaterial({
      color: 0x9a6e2c,
      roughness: 0.3,
      metalness: 0.84,
      emissive: 0x351a04,
      emissiveIntensity: 0.16,
    });
    const stockProfile = new THREE.Shape();
    stockProfile.moveTo(-0.16, 0.09);
    stockProfile.lineTo(0.1, 0.13);
    stockProfile.lineTo(0.18, 0.01);
    stockProfile.lineTo(0.12, -0.17);
    stockProfile.lineTo(-0.14, -0.13);
    stockProfile.closePath();
    const stock = new THREE.Mesh(
      new THREE.ExtrudeGeometry(stockProfile, {
        depth: 1.02,
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
    const receiver = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.24, 0.72, 2, 2, 4), gunMetal);
    receiver.position.z = -0.55;
    weapon.add(receiver);
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
    const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.042, 0.055, 1.72, 16), gunMetal);
    barrel.rotation.x = Math.PI / 2;
    barrel.position.set(0, 0.045, -1.62);
    weapon.add(barrel);
    const sight = new THREE.Mesh(new THREE.TorusGeometry(0.075, 0.015, 7, 16), gunMetal);
    sight.position.set(0, 0.16, -2.08);
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
    for (const side of [-1, 1]) {
      const hoof = new THREE.Mesh(
        new THREE.CapsuleGeometry(0.095, 0.36, 4, 8),
        new THREE.MeshStandardMaterial({ color: 0x2d2724, roughness: 0.98 }),
      );
      hoof.position.set(side * 0.19, -0.18, side === 1 ? -0.32 : 0.12);
      hoof.rotation.z = side * 0.35;
      hoof.rotation.x = -0.75;
      weapon.add(hoof);
      const wrap = new THREE.Mesh(
        new THREE.TorusGeometry(0.1, 0.028, 5, 10),
        new THREE.MeshStandardMaterial({ color: 0x6d5135, roughness: 0.9 }),
      );
      wrap.position.copy(hoof.position);
      weapon.add(wrap);
    }
    const muzzle = new THREE.PointLight(0xffaa55, 0, 7, 2);
    muzzle.position.set(0, 0.03, -2.25);
    weapon.add(muzzle);
    const weaponFill = new THREE.PointLight(0xb7dded, 1.9, 3.5, 1.5);
    weaponFill.position.set(-0.65, 0.8, 0.1);
    weapon.add(weaponFill);

    const enemies: Enemy[] = [];
    const worldTargets: THREE.Object3D[] = [
      ground,
      rocks,
      ...outpost.children,
      ...bellGroup.children,
    ];
    const spawnWave = (wave: number) => {
      const positionsByWave = [
        [
          [-8, 5],
          [7, -2],
          [-10, -12],
        ],
        [
          [9, -36],
          [-9, -41],
          [4, -51],
          [-5, -58],
          [0, -67],
        ],
      ];
      for (const [x, z] of positionsByWave[wave] ?? []) {
        enemies.push(
          createWolverine(
            scene,
            new THREE.Vector3(x, ridgeHeight(x, z), z),
          ),
        );
      }
    };
    spawnWave(0);

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
    let pitch = -0.04;
    let verticalVelocity = 0;
    let grounded = true;
    let sprint = false;
    let ads = false;
    let ammo = 24;
    let reserve = 96;
    let reloading = false;
    let health = 100;
    let kills = 0;
    let wave = 0;
    let echoCharge = 1;
    let echoActive = false;
    let echoTime = 0;
    let recoil = 0;
    let bobTime = 0;
    let lastShot = 0;
    let fireHeld = false;
    let bossSpawned = false;
    let bossKilled = false;
    let damageFlash = 0;
    let objective = "Reach the stolen bell";
    let prompt = "";
    let frame = 0;
    let disposed = false;
    const clock = new THREE.Clock();
    const raycaster = new THREE.Raycaster();
    const forward = new THREE.Vector3();
    const right = new THREE.Vector3();
    const movement = new THREE.Vector3();
    const tmp = new THREE.Vector3();

    const updateHud = () => {
      const boss = enemies.find((enemy) => enemy.boss && !enemy.dead);
      onHud({
        ammo,
        reserve,
        health: Math.max(0, Math.round(health)),
        kills,
        total: 9,
        echo: echoCharge,
        objective,
        prompt,
        boss: boss ? boss.health / boss.maxHealth : bossKilled ? 0 : -1,
        lowHealth: health < 32,
      });
    };

    const reload = () => {
      if (reloading || ammo === 24 || reserve <= 0) return;
      reloading = true;
      audio.reload();
      window.setTimeout(() => {
        if (disposed) return;
        const amount = Math.min(24 - ammo, reserve);
        ammo += amount;
        reserve -= amount;
        reloading = false;
        updateHud();
      }, 1050);
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
      spawnImpact(enemy.group.position.clone().add(new THREE.Vector3(0, 1.4, 0)), 0xbb2c18, 22, 7);
      if (kills === 3 && wave === 0) {
        wave = 1;
        objective = "Break the mountain siege";
        window.setTimeout(() => spawnWave(1), 750);
      }
      if (kills >= 8 && !bossSpawned) {
        bossSpawned = true;
        objective = "KILL VARKAS — THE IRON WOLVERINE";
        const boss = createWolverine(
          scene,
          new THREE.Vector3(0, ridgeHeight(0, -79), -79),
          true,
        );
        enemies.push(boss);
        scene.fog = new THREE.FogExp2(0x6e7f87, 0.018);
      }
      if (enemy.boss) {
        bossKilled = true;
        objective = "THE FAMILY IS AVENGED";
        audio.echo();
        window.setTimeout(onWin, 2100);
      }
      updateHud();
    };

    const shoot = () => {
      const now = performance.now();
      if (
        now - lastShot < 96 ||
        reloading ||
        !activeRef.current ||
        document.pointerLockElement !== renderer.domElement ||
        sprint
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

    const activateEcho = () => {
      if (echoCharge < 0.98 || echoActive || !activeRef.current) return;
      echoActive = true;
      echoCharge = 0;
      echoTime = 0;
      echoRing.position.copy(camera.position);
      echoRing.scale.setScalar(0.2);
      echoMat.opacity = 0.85;
      audio.echo();
      renderer.toneMappingExposure = 1.32;
      camera.getWorldDirection(forward);
      for (const enemy of enemies) {
        if (enemy.dead) continue;
        tmp.copy(enemy.group.position).sub(camera.position);
        const distance = tmp.length();
        const alignment = tmp.normalize().dot(forward);
        if (distance > 42 || alignment < 0.08) continue;
        enemy.material.emissive.set(enemy.boss ? 0xff3311 : 0xff6a22);
        enemy.material.emissiveIntensity = 1.6;
        enemy.velocity
          .addScaledVector(forward, enemy.boss ? 8 : 15)
          .setY(enemy.boss ? 6 : 11);
        enemy.health -= enemy.boss ? 12 : 18;
        if (enemy.health <= 0) killEnemy(enemy, true);
      }
      for (const piece of debris) {
        const distance = piece.mesh.position.distanceTo(camera.position);
        tmp.copy(piece.mesh.position).sub(camera.position).normalize();
        if (distance < 46 && tmp.dot(forward) > -0.12) {
          piece.velocity
            .copy(piece.mesh.position)
            .sub(camera.position)
            .normalize()
            .multiplyScalar(-8)
            .addScaledVector(forward, 20)
            .setY(11 + Math.random() * 6);
        }
      }
      updateHud();
    };

    const onPointerLock = () => {
      const locked = document.pointerLockElement === renderer.domElement;
      if (!locked) {
        keys.clear();
        fireHeld = false;
        ads = false;
      }
      onLocked(locked);
    };
    const onMouseMove = (event: MouseEvent) => {
      if (document.pointerLockElement !== renderer.domElement) return;
      yaw -= event.movementX * 0.00175;
      pitch -= event.movementY * 0.00155;
      pitch = THREE.MathUtils.clamp(pitch, -1.35, 1.25);
    };
    const onMouseDown = (event: MouseEvent) => {
      if (document.pointerLockElement !== renderer.domElement) return;
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
      keys.add(event.code);
      if (event.code === "KeyR") reload();
      if (event.code === "KeyQ") activateEcho();
      if (event.code === "Space" && grounded) {
        verticalVelocity = 7.2;
        grounded = false;
      }
    };
    const onKeyUp = (event: KeyboardEvent) => keys.delete(event.code);
    const onContext = (event: MouseEvent) => event.preventDefault();
    const onBlur = () => {
      keys.clear();
      fireHeld = false;
      ads = false;
    };
    const onCanvasClick = () => {
      if (activeRef.current && document.pointerLockElement !== renderer.domElement) {
        const request = renderer.domElement.requestPointerLock();
        if (request) void request.catch(() => {});
        audio.start();
      }
    };
    const onAudioStart = () => audio.start();
    const onPlayerStart = () => {
      camera.position.set(0, ridgeHeight(0, 28) + 1.68, 28);
      yaw = 0;
      pitch = -0.04;
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

      const locked = document.pointerLockElement === renderer.domElement && activeRef.current;
      if (locked) {
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
          const speed = ads ? 3.4 : sprint ? 8.4 : 5.4;
          camera.position.addScaledVector(movement, speed * dt);
          bobTime += dt * (sprint ? 13 : 8.5);
        }
        if (fireHeld) shoot();
        camera.position.x = THREE.MathUtils.clamp(camera.position.x, -11.5, 11.5);
        camera.position.z = THREE.MathUtils.clamp(camera.position.z, -91, 34);
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
      const bob = locked && movement.lengthSq() ? Math.sin(bobTime) : 0;
      const adsX = ads ? 0 : 0.42;
      const adsY = ads ? -0.27 : -0.43;
      const adsZ = ads ? -0.91 : -0.72;
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

      if (echoActive) {
        echoTime += dt;
        const scale = 0.2 + echoTime * 46;
        echoRing.scale.setScalar(scale);
        echoMat.opacity = Math.max(0, 0.72 - echoTime * 0.62);
        if (echoTime > 1.25) {
          echoActive = false;
          echoMat.opacity = 0;
          renderer.toneMappingExposure = 1.05;
          for (const enemy of enemies) {
            enemy.material.emissiveIntensity = enemy.boss ? 0.26 : 0;
          }
        }
      } else {
        echoCharge = Math.min(1, echoCharge + dt / 8.5);
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

      if (locked) {
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
          const desired = enemy.boss ? 15 : 18 + Math.sin(enemy.phase) * 5;
          if (distance > desired) {
            tmp.normalize();
            enemy.velocity.x = THREE.MathUtils.damp(enemy.velocity.x, tmp.x * enemy.speed, 3, dt);
            enemy.velocity.z = THREE.MathUtils.damp(enemy.velocity.z, tmp.z * enemy.speed, 3, dt);
          } else {
            tmp.normalize();
            const strafeX = -tmp.z * Math.sin(enemy.phase * 1.8);
            const strafeZ = tmp.x * Math.sin(enemy.phase * 1.8);
            enemy.velocity.x = THREE.MathUtils.damp(enemy.velocity.x, strafeX * enemy.speed, 3, dt);
            enemy.velocity.z = THREE.MathUtils.damp(enemy.velocity.z, strafeZ * enemy.speed, 3, dt);
          }
          enemy.velocity.y -= 16 * dt;
          enemy.group.position.addScaledVector(enemy.velocity, dt);
          const enemyFloor = ridgeHeight(enemy.group.position.x, enemy.group.position.z);
          if (enemy.group.position.y < enemyFloor) {
            enemy.group.position.y = enemyFloor;
            enemy.velocity.y = 0;
          }
          enemy.group.lookAt(camera.position.x, enemy.group.position.y + 1.4, camera.position.z);
          enemy.body.rotation.z = Math.sin(enemy.phase * 4) * 0.025;
          if (enemy.cooldown <= 0 && distance < (enemy.boss ? 54 : 39)) {
            enemy.cooldown = enemy.boss ? 0.48 + Math.random() * 0.5 : 1.1 + Math.random() * 1.5;
            audio.enemyShot();
            tmp.copy(camera.position).sub(enemy.group.position);
            const shotDistance = tmp.length();
            raycaster.set(
              enemy.group.position.clone().add(new THREE.Vector3(0, 1.5, 0)),
              tmp.normalize(),
            );
            raycaster.far = shotDistance;
            const coverHit = raycaster.intersectObjects(worldTargets, true)[0];
            const accuracy = enemy.boss ? 0.74 : 0.45;
            if (!coverHit && Math.random() < accuracy) {
              const damage = enemy.boss ? 8 + Math.random() * 7 : 5 + Math.random() * 8;
              health -= damage;
              damageFlash = 1;
              audio.hurt();
              if (health <= 0) {
                health = 100;
                ammo = Math.max(ammo, 12);
                camera.position.set(0, ridgeHeight(0, 24) + 1.68, 24);
                objective = "The mountain remembers. Try again.";
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
      prompt = bellDistance < 8 && kills < 3 ? "The cracked bell remembers them" : "";
      if (camera.position.z < 12 && kills < 3) objective = "Survive the homestead ambush";
      if (frame % 12 === 0) {
        audio.setWind(sprint ? 0.14 : health < 32 ? 0.045 : 0.075);
        updateHud();
      }
      composer.render();
    };
    animate();

    return () => {
      disposed = true;
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
      renderer.dispose();
      composer.dispose();
      snowTex.dispose();
      rockTex.dispose();
      mount.removeChild(renderer.domElement);
    };
  }, [onHud, onLocked, onWin]);

  return <div ref={mountRef} className="game-canvas" aria-hidden="true" />;
}

function StartScreen({ onStart }: { onStart: () => void }) {
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
      <button className="deploy-button" onClick={onStart} data-testid="deploy">
        <span>DEPLOY</span>
        <small>ENTER THE RAVINE</small>
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
  const [won, setWon] = useState(false);
  const [hud, setHud] = useState<HudState>(initialHud);
  const hudCallback = useRef(setHud);
  const lockCallback = useRef(setLocked);
  const winCallback = useRef(() => setWon(true));
  const enterGame = () => {
    window.dispatchEvent(new Event("goat-audio-start"));
    window.dispatchEvent(new Event("goat-player-start"));
    if (new URLSearchParams(window.location.search).has("qa")) {
      setLocked(true);
      setStarted(true);
      return;
    }
    const canvas = document.querySelector<HTMLCanvasElement>("canvas");
    const request = canvas?.requestPointerLock();
    if (request) void request.catch(() => {});
    setStarted(true);
  };

  return (
    <main className={`game-shell ${hud.lowHealth ? "is-hurt" : ""}`}>
      <GameCanvas
        active={started && !won}
        onHud={hudCallback.current}
        onLocked={lockCallback.current}
        onWin={winCallback.current}
      />
      {!started && <StartScreen onStart={enterGame} />}

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
              onClick={() => {
                window.dispatchEvent(new Event("goat-audio-start"));
                const request =
                  document.querySelector<HTMLCanvasElement>("canvas")?.requestPointerLock();
                if (request) void request.catch(() => {});
              }}
            >
              <span>FIELD PAUSED</span>
              CLICK TO RE-ENTER
            </button>
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
