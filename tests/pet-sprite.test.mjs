import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const moduleUrl = source => 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source));
const wire = moduleUrl(await readFile(new URL('dsh/DshWire.ets', root), 'utf8'));
const { parsePetPack, petAnimation, petArtScale, petFrameAt } = await import(moduleUrl(
  (await readFile(new URL('pets/PetData.ets', root), 'utf8'))
    .replace(', WireObject', '').replace("'../dsh/DshWire'", JSON.stringify(wire))));
const component = await readFile(new URL('pets/PetSprite.ets', root), 'utf8');
// Execute the component's real constructor and paint method, without ArkUI's
// declarative build block. No rendering algorithm is copied into the fixture.
const executable = stripTypeScriptTypes(component.slice(0, component.indexOf(' build(){'))
  .replace(/^import .*\n/gm, '')
  .replace(/@(?:Component|Prop|State)\b/g, '')
  .replace(/@Watch\('[^']+'\)/g, '')
  .replace('export struct PetSprite', 'class PetSprite') + '\n}\nPetSprite');

function renderer(density, apiVersion = 18) {
  let now = 0;
  class Canvas {
    constructor(_settings, unit = 0) { this.unit = unit; this.draws = []; this.clears = []; this.transforms = []; this.scales = []; }
    clearRect(...rect) { this.clears.push(rect.map(n => n * (this.unit === 1 ? 1 : density))); }
    save() {}
    restore() {}
    translate(x, y) { this.transforms.push([x, y].map(n => n * (this.unit === 1 ? 1 : density))); }
    scale(x, y) { this.scales.push([x, y]); }
    drawImage(_image, sx, sy, sw, sh, dx, dy, dw, dh) {
      // SDK canvas.d.ts: PixelMap crop coordinates changed from px to vp in
      // API 18. Explicit PX contexts keep physical pixels on either version.
      const sourceUnit = this.unit === 1 || apiVersion < 18 ? 1 : density;
      const destinationUnit = this.unit === 1 ? 1 : density;
      this.draws.push({ source: [sx, sy, sw, sh].map(n => n * sourceUnit),
        destination: [dx, dy, dw, dh].map(n => n * destinationUnit) });
    }
  }
  const PetSprite = vm.runInNewContext(executable, {
    CanvasRenderingContext2D: Canvas, RenderingContextSettings: class {},
    LengthMetricsUnit: { DEFAULT: 0, PX: 1 }, petFrameAt,
    Date: { now: () => now }
  });
  const sprite = new PetSprite();
  sprite.getUIContext = () => ({ vp2px: n => n * density });
  sprite.ready = true;
  sprite.pixels = {};
  return { sprite, at: elapsed => { now = elapsed; sprite.paint(); return sprite.canvas.draws.at(-1); } };
}

function near(actual, expected, description) {
  assert.equal(actual.length, expected.length, description);
  actual.forEach((n, i) => assert.ok(Math.abs(n - expected[i]) < 1e-7,
    `${description}[${i}]: got ${n}, expected ${expected[i]}`));
}

for (const density of [1, 2, 3.5]) {
  test(`real PetSprite.paint crops exactly one atlas cell at DPR ${density}`, async () => {
    for (const id of ['deepy-whale', 'whale-girl']) {
      const raw = JSON.parse(await readFile(new URL(`../entry/src/main/resources/rawfile/pets/${id}/pack.json`, import.meta.url)));
      const pack = parsePetPack(raw);
      for (const size of ['small', 'medium', 'large']) {
        const { sprite, at } = renderer(density);
        sprite.pack = pack;
        sprite.artScale = petArtScale(pack, size, density);
        sprite.spriteWidth = pack.width * sprite.artScale;
        sprite.spriteHeight = pack.height * sprite.artScale;
        for (const animation of pack.animations) {
          sprite.playing = animation;
          sprite.started = 0;
          let elapsed = 0;
          for (const frame of raw.animations[animation.name].frames) {
            const drawn = at(elapsed);
            near(drawn.source, [(frame.i % animation.cols) * animation.frameW,
              Math.floor(frame.i / animation.cols) * animation.frameH, animation.frameW, animation.frameH],
            `${id}/${animation.name}/${frame.i} crop in physical image pixels`);
            const scale = sprite.artScale * density;
            near(drawn.destination, [animation.box.x * scale, animation.box.y * scale,
              animation.box.w * scale, animation.box.h * scale], `${id}/${size} physical destination`);
            near(sprite.canvas.clears.at(-1), [0, 0, pack.width * scale, pack.height * scale], 'clear complete canvas');
            assert.equal(sprite.canvas.imageSmoothingEnabled, !pack.pixelArt);
            elapsed += frame.ms;
          }
        }
      }
    }
  });
}

test('pixel crop stays identical before/after API 18 and still mode holds the first frame', async () => {
  const pack = parsePetPack(JSON.parse(await readFile(new URL('../entry/src/main/resources/rawfile/pets/deepy-whale/pack.json', import.meta.url))));
  const outputs = [];
  for (const api of [17, 18, 23]) {
    const { sprite, at } = renderer(3.5, api);
    sprite.pack = pack;
    sprite.playing = petAnimation(pack, 'idle');
    sprite.artScale = petArtScale(pack, 'medium', 3.5);
    sprite.spriteWidth = pack.width * sprite.artScale;
    sprite.spriteHeight = pack.height * sprite.artScale;
    sprite.animations = false;
    outputs.push(at(1749));
  }
  assert.deepEqual(outputs[0], outputs[1]);
  assert.deepEqual(outputs[1], outputs[2]);
  assert.deepEqual(outputs[0].source, [0, 0, 180, 120]);
});

test('flipping and clearing retain the same physical extent after choosing pixel units', async () => {
  const pack = parsePetPack(JSON.parse(await readFile(new URL('../entry/src/main/resources/rawfile/pets/deepy-whale/pack.json', import.meta.url))));
  for (const density of [1, 2, 3.5]) {
    const { sprite, at } = renderer(density);
    sprite.pack = pack;
    sprite.playing = petAnimation(pack, 'idle');
    sprite.artScale = petArtScale(pack, 'medium', density);
    sprite.spriteWidth = pack.width * sprite.artScale;
    sprite.spriteHeight = pack.height * sprite.artScale;
    const normal = at(1250);
    sprite.flipped = true;
    assert.deepEqual(at(1250), normal, 'mirroring does not select a different atlas cell');
    near(sprite.canvas.transforms.at(-1), [sprite.spriteWidth * density, 0], 'mirror translation');
    assert.deepEqual(sprite.canvas.scales.at(-1), [-1, 1]);
    sprite.pixels = undefined;
    const count = sprite.canvas.draws.length;
    at(1300);
    assert.equal(sprite.canvas.draws.length, count, 'an unloaded sheet only clears stale pixels');
    near(sprite.canvas.clears.at(-1), [0, 0, sprite.spriteWidth * density, sprite.spriteHeight * density], 'empty canvas');
  }
});
