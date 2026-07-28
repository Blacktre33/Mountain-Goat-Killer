import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the Mountain Goat Killer entry screen", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Mountain Goat Killer — The Last Bell<\/title>/i);
  assert.match(html, /A cinematic first-person alpine revenge experience/i);
  assert.match(html, /MOUNTAIN/);
  assert.match(html, /GOAT KILLER/);
  assert.match(html, /THE LAST BELL/);
  assert.match(html, /PREPARING THE PASS/);
  assert.match(html, /data-testid="deploy" disabled/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
});

test("keeps Three.js browser-only and ships the core gameplay systems", async () => {
  const [page, layout, packageJson] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(page, /import type \* as THREE from "three"/);
  assert.match(page, /await Promise\.all\(\[\s*import\("three"\)/);
  assert.match(page, /function createWolverine/);
  assert.match(page, /const beginEcho/);
  assert.match(page, /const releaseEcho/);
  assert.match(page, /const worldTargets/);
  assert.match(page, /requestPointerLock/);
  assert.match(page, /fallbackControls/);
  assert.match(page, /onReady\(true\)/);
  assert.match(layout, /Mountain Goat Killer — The Last Bell/);
  assert.match(packageJson, /"three":/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
});
