const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const script = fs.readFileSync(path.join(__dirname, "web/web_music.js"), "utf8");
const tick = () => new Promise(resolve => setImmediate(resolve));

function fixture() {
  const decodes = [];
  const node = () => ({
    gain: {}, frequency: {}, Q: {}, connect() {}, disconnect() {},
    start() {}, stop() {}, getFloatTimeDomainData() {}
  });
  const context = {
    currentTime: 0, state: "running", sampleRate: 24000,
    decodeAudioData(bytes, done) { decodes.push(done); },
    createBufferSource: node, createGain: node, createBiquadFilter: node, createAnalyser: node
  };
  const window = { __syAudioCtx: [context] };
  vm.runInNewContext(script, {
    window, performance, URLSearchParams, location: { search: "" },
    fetch: async () => ({ ok: true, arrayBuffer: async () => new ArrayBuffer(1) })
  });
  return {
    music: window.__syMus,
    async finish() {
      await tick();
      assert.equal(decodes.length, 1, "pending requests should share a decode");
      decodes.shift()({ length: 24000, numberOfChannels: 1, duration: 1 });
      await tick();
    }
  };
}

test("a preload released before decode completes leaves no cached PCM", async () => {
  const { music, finish } = fixture();
  music.preload(["title"]);
  music.free(["title"]);
  await finish();
  assert.equal(music.mb(), 0);
});

test("a fresh preload can reclaim the pending decode", async () => {
  const { music, finish } = fixture();
  music.preload(["title"]);
  music.free(["title"]);
  music.preload(["title"]);
  await finish();
  assert.equal(music.mb(), 96000 / 1048576);
  music.free(["title"]);
  assert.equal(music.mb(), 0);
});

test("a replacement player reuses the decode and holds PCM until its last stop", async () => {
  const { music, finish } = fixture();
  music.play([[1, "battle", 0, 0, 1, 1]]);
  music.stop([1]);
  music.free(["battle"]);
  music.play([[2, "battle", 0, 0, 1, 1]]);
  music.free(["battle"]);
  await finish();
  assert.equal(JSON.parse(music.state()).on, 1);
  assert.equal(music.mb(), 96000 / 1048576);
  music.stop([2]);
  assert.equal(music.mb(), 0);
});
