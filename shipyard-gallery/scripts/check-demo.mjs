import assert from "node:assert/strict";
import test from "node:test";
import { mkdir, writeFile } from "node:fs/promises";
import * as THREE from "three";
import { GLTFExporter } from "three/examples/jsm/exporters/GLTFExporter.js";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { createShipModel, disposeShip, vesselCatalog } from "../dist/ship-models.js";
import { CannonSmoke, SMOKE_LIFETIME, FIRE_COOLDOWN, PARTICLES_PER_CANNON, SMOKE_POOL_LIMIT } from "../dist/cannon-smoke.js";
import { shipFrame } from "../dist/viewer-framing.js";

// GLTFExporter needs only this small browser FileReader adapter for untextured GLB.
globalThis.FileReader ??= class {
  readAsArrayBuffer(blob) { blob.arrayBuffer().then((value) => { this.result = value; this.onloadend?.(); }); }
  readAsDataURL(blob) { blob.arrayBuffer().then((value) => { this.result = `data:${blob.type};base64,${Buffer.from(value).toString("base64")}`; this.onloadend?.(); }); }
};

const counts = { sloop: 8, brig: 12, frigate: 16, galleon: 32 };
const vector = () => new THREE.Vector3();
const nearVector = (actual, expected, label) => assert.ok(actual.distanceTo(expected) < 1e-6, label);
function inspectGeometry(object) {
  let meshes = 0;
  let triangles = 0;
  object.traverse((child) => {
    if (!child.geometry) return;
    for (const attribute of Object.values(child.geometry.attributes)) {
      for (const value of attribute.array) assert.ok(Number.isFinite(value), `${child.name}: finite geometry`);
    }
    if (child.isMesh) {
      meshes += 1;
      triangles += (child.geometry.index?.count ?? child.geometry.attributes.position.count) / 3;
    }
    const index = child.geometry.index;
    if (index) for (const value of index.array) assert.ok(value >= 0 && value < child.geometry.attributes.position.count);
  });
  return { meshes, triangles };
}
function glbDocument(glb) {
  const bytes = new DataView(glb);
  assert.equal(bytes.getUint32(0, true), 0x46546c67);
  assert.equal(bytes.getUint32(4, true), 2);
  assert.equal(bytes.getUint32(8, true), glb.byteLength);
  assert.equal(bytes.getUint32(16, true), 0x4e4f534a);
  return JSON.parse(new TextDecoder().decode(new Uint8Array(glb, 20, bytes.getUint32(12, true))));
}

for (const [type, total] of Object.entries(counts)) {
  test(`${type}: mounted cannons, finite geometry, rig, and GLB round trip`, async () => {
    const model = createShipModel(type);
    assert.equal(model.cannons.length, total);
    const barrels = [];
    const markers = [];
    model.object.traverse((child) => {
      if (child.name === "cannon barrel") barrels.push(child);
      if (child.name.startsWith("Muzzle_")) markers.push(child);
    });
    assert.equal(barrels.length, total);
    assert.equal(markers.length, total);
    assert.equal(new Set(markers.map((marker) => marker.name)).size, total);
    for (const side of ["port", "starboard"]) {
      const battery = model.cannons.filter((cannon) => cannon.side === side);
      assert.equal(battery.length, total / 2);
      battery.forEach(({ barrel, muzzle }, index) => {
        assert.equal(muzzle.name, `Muzzle_${side}_${index}`);
        assert.ok(barrels.includes(barrel));
        const sign = side === "starboard" ? 1 : -1;
        const localTip = barrel.position.clone();
        localTip.z += sign * barrel.geometry.parameters.height / 2;
        nearVector(muzzle.position, localTip, `${type}: marker touches barrel tip`);
        nearVector(new THREE.Vector3(0, 0, 1).transformDirection(muzzle.matrixWorld), new THREE.Vector3(0, 0, sign), `${type}: muzzle points outward`);
        if (index > 0 && !(type === "galleon" && index === 8)) assert.ok(muzzle.position.x < battery[index - 1].muzzle.position.x, "bow-to-stern order");
      });
      if (type === "galleon") {
        assert.equal(battery.slice(0, 8).length, 8);
        for (let index = 0; index < 8; index += 1) assert.ok(battery[index + 8].muzzle.position.y - battery[index].muzzle.position.y > 0.5, "two separate gun decks");
      }
    }
    const hullGeometry = model.object.getObjectByName("lofted three-dimensional hull").geometry;
    assert.ok(hullGeometry.attributes.normal.getZ(25) > 0.9, "starboard hull normals face outward");
    assert.ok(hullGeometry.attributes.normal.getZ(30) < -0.9, "port hull normals face outward");
    const deckNormals = model.object.getObjectByName("cambered deck").geometry.attributes.normal;
    for (let index = 0; index < deckNormals.count; index += 1) assert.ok(deckNormals.getY(index) > 0, "deck normals face up");
    const stats = inspectGeometry(model.object);
    assert.ok(stats.meshes > 100 && stats.triangles > 5000);
    assert.equal(model.sailPivots.length, type === "sloop" ? 1 : 3);
    assert.ok(model.sailPivots.every((pivot) => pivot.parent === model.object && Number.isFinite(pivot.userData.trimFactor)));
    const pivotPoint = new THREE.Vector3(1, 1, 0.5);
    const oldSailPoint = model.sailPivots[0].localToWorld(pivotPoint.clone());
    const hull = model.object.getObjectByName("lofted three-dimensional hull");
    const oldHullMatrix = hull.matrixWorld.clone();
    model.sailPivots[0].rotation.y = 0.4;
    model.object.updateMatrixWorld(true);
    assert.ok(oldSailPoint.distanceTo(model.sailPivots[0].localToWorld(pivotPoint.clone())) > 0.1, "sails trim independently");
    assert.ok(hull.matrixWorld.equals(oldHullMatrix), "sail trim does not rotate the hull");
    model.sailPivots[0].rotation.y = 0;
    model.object.updateMatrixWorld(true);
    if (type === "galleon") {
      assert.ok(model.object.getObjectByName("raised forecastle"));
      assert.ok(model.object.getObjectByName("stepped upper sterncastle"));
      assert.ok(model.object.getObjectByName("triangular lateen mizzen sail"));
      assert.equal(model.object.getObjectByName("wind-trimming lateen mizzen").children.filter((child) => child.name.startsWith("square sail")).length, 0);
    }
    const glb = await new GLTFExporter().parseAsync(model.object, { binary: true, onlyVisible: true, trs: true });
    const json = glbDocument(glb);
    assert.equal(json.nodes.filter((node) => node.name === "cannon barrel").length, total);
    assert.equal(json.nodes.filter((node) => node.name?.startsWith("Muzzle_")).length, total);
    assert.ok(json.nodes.every((node) => !/smoke|scenery|water shadow|controlled heading|gentle ship motion|light/i.test(node.name ?? "")));
    assert.ok((json.images?.length ?? 0) === 0, "no textures or network assets exported");
    const imported = await new GLTFLoader().parseAsync(glb, "");
    const reloadedStats = inspectGeometry(imported.scene);
    assert.equal(reloadedStats.meshes, stats.meshes);
    assert.equal(reloadedStats.triangles, stats.triangles);
    const importedMarkers = [];
    imported.scene.traverse((child) => { if (child.name.startsWith("Muzzle_")) importedMarkers.push(child); });
    assert.equal(importedMarkers.length, total);
    for (const { muzzle } of model.cannons) {
      const importedMarker = imported.scene.getObjectByName(muzzle.name);
      assert.ok(importedMarker);
      nearVector(importedMarker.getWorldPosition(vector()), muzzle.getWorldPosition(vector()), "GLB preserves mounted muzzle position");
    }
    await mkdir("/tmp/tortuga-shipyard-demo", { recursive: true });
    await writeFile(`/tmp/tortuga-shipyard-demo/${type}.glb`, Buffer.from(glb));
    console.log(`${type}: ${total} cannons, ${model.sailPivots.length} sail pivots, ${stats.meshes} meshes, ${stats.triangles} triangles, ${glb.byteLength} GLB bytes`);
    disposeShip(imported.scene);
    disposeShip(model.object);
  });
}

test("Galleon is about 30% longer, 35% broader, and 25% taller than Frigate", () => {
  const frigate = createShipModel("frigate");
  const galleon = createShipModel("galleon");
  const small = frigate.bounds.getSize(vector());
  const large = galleon.bounds.getSize(vector());
  for (const [axis, target] of [["x", 1.3], ["z", 1.35], ["y", 1.25]]) assert.ok(Math.abs(large[axis] / small[axis] - target) < 0.06, `${axis}: appropriate scale`);
  console.log(`Galleon/Frigate bounds: length ${(large.x / small.x).toFixed(3)}, beam ${(large.z / small.z).toFixed(3)}, height ${(large.y / small.y).toFixed(3)}`);
  disposeShip(frigate.object);
  disposeShip(galleon.object);
});

test("smoke: transformed muzzle origins, cooldown, expansion, four-second fade, bounded reuse, clear and disposal", () => {
  const model = createShipModel("galleon");
  const heading = new THREE.Group();
  heading.rotation.set(0.13, 1.1, -0.07);
  heading.position.set(2, 0.7, -3);
  heading.add(model.object);
  heading.updateMatrixWorld(true);
  const smoke = new CannonSmoke();
  assert.ok(smoke.fire(model.cannons, 0));
  assert.equal(smoke.activeCount, 32 * PARTICLES_PER_CANNON);
  model.cannons.forEach(({ muzzle }, index) => {
    const direction = new THREE.Vector3(0, 0, 1).transformDirection(muzzle.matrixWorld);
    for (let puff = 0; puff < PARTICLES_PER_CANNON; puff += 1) {
      const particle = smoke.particles[index * PARTICLES_PER_CANNON + puff];
      nearVector(particle.origin, muzzle.getWorldPosition(vector()), "transformed smoke origin");
      nearVector(particle.sprite.position, particle.origin, "starts exactly at muzzle");
      assert.ok(particle.velocity.dot(direction) > 0.3, "smoke moves outward");
      assert.ok(particle.sprite.material.depthWrite === false && particle.sprite.material.color.getHex() === 0xffffff);
    }
  });
  assert.equal(smoke.fire(model.cannons, FIRE_COOLDOWN - 0.01), false);
  smoke.update(2);
  const first = smoke.particles[0];
  assert.ok(first.sprite.material.opacity > 0 && first.sprite.material.opacity < 0.7);
  assert.ok(first.sprite.scale.x > 1);
  assert.ok(first.sprite.position.y > first.origin.y, "smoke rises while model remains still");
  smoke.update(SMOKE_LIFETIME - 0.01);
  assert.equal(smoke.activeCount, 96);
  smoke.update(SMOKE_LIFETIME);
  assert.equal(smoke.activeCount, 0);
  assert.ok(smoke.particles.every(({ sprite }) => !sprite.visible && sprite.material.opacity === 0));
  smoke.clear();
  for (let seconds = 10; seconds < 110; seconds += FIRE_COOLDOWN) assert.ok(smoke.fire(model.cannons, seconds));
  assert.equal(smoke.particles.length, 384, "four volleys reuse expired sprites");
  assert.ok(smoke.particles.length <= SMOKE_POOL_LIMIT);
  const bounded = new CannonSmoke();
  assert.ok(bounded.fire(Array(300).fill(model.cannons[0]), 0));
  assert.equal(bounded.particles.length, SMOKE_POOL_LIMIT, "pool cannot grow past limit even with oversized input");
  bounded.dispose();
  smoke.clear();
  assert.equal(smoke.activeCount, 0);
  assert.ok(smoke.fire(model.cannons, 0), "class change resets cooldown");
  let materialDisposals = 0;
  let textureDisposals = 0;
  smoke.particles.forEach(({ sprite }) => sprite.material.addEventListener("dispose", () => { materialDisposals += 1; }));
  smoke.texture.addEventListener("dispose", () => { textureDisposals += 1; });
  const poolSize = smoke.particles.length;
  smoke.dispose();
  assert.equal(materialDisposals, poolSize);
  assert.equal(textureDisposals, 1);
  assert.equal(smoke.particles.length, 0);
  assert.equal(smoke.object.children.length, 0);
  disposeShip(model.object);
});

test("all retained variants create matching cannon references and dispose shared resources once", () => {
  for (const [type, data] of Object.entries(vesselCatalog)) for (let index = 0; index < data.ships.length; index += 1) {
    const model = createShipModel(type, index);
    const uniqueMaterials = new Set();
    const uniqueGeometries = new Set();
    let barrels = 0;
    model.object.traverse((part) => {
      if (part.name === "cannon barrel") barrels += 1;
      if (part.material) uniqueMaterials.add(part.material);
      if (part.geometry) uniqueGeometries.add(part.geometry);
    });
    assert.equal(model.cannons.length, barrels);
    const disposed = [];
    [...uniqueMaterials, ...uniqueGeometries].forEach((resource) => resource.addEventListener("dispose", () => disposed.push(resource)));
    disposeShip(model.object);
    assert.equal(disposed.length, uniqueMaterials.size + uniqueGeometries.size);
    assert.equal(new Set(disposed).size, disposed.length);
  }
});


test("shared reset framing fits every class at headings 0/90/180/270 on desktop and narrow displays", () => {
  const largest = createShipModel("galleon");
  const camera = new THREE.OrthographicCamera(-12, 12, 8, -8, 0.1, 100);
  const halfHeights = {};
  for (const [width, height] of [[1238, 630], [294, 430], [366, 430]]) {
    const aspect = width / height;
    for (const degrees of [0, 90, 180, 270]) {
      const heading = new THREE.Matrix4().makeRotationY(THREE.MathUtils.degToRad(degrees));
      let sharedHalfHeight;
      for (const type of Object.keys(counts)) {
        const model = createShipModel(type);
        const center = model.bounds.getCenter(vector()).applyMatrix4(heading);
        camera.position.copy(center).add(new THREE.Vector3(0, 10, 18));
        camera.lookAt(center);
        const { halfHeight } = shipFrame(largest.bounds, degrees, aspect, camera.quaternion);
        if (sharedHalfHeight !== undefined) assert.ok(Math.abs(sharedHalfHeight - halfHeight) < 1e-10, "shared scale across classes");
        sharedHalfHeight = halfHeight;
        Object.assign(camera, { left: -halfHeight * aspect, right: halfHeight * aspect, top: halfHeight, bottom: -halfHeight });
        camera.zoom = 1;
        camera.updateProjectionMatrix();
        camera.updateMatrixWorld(true);
        for (const x of [model.bounds.min.x, model.bounds.max.x]) {
          for (const y of [model.bounds.min.y, model.bounds.max.y]) {
            for (const z of [model.bounds.min.z, model.bounds.max.z]) {
              const projected = new THREE.Vector3(x, y, z).applyMatrix4(heading).project(camera);
              assert.ok(Math.abs(projected.x) <= 1 && Math.abs(projected.y) <= 1, `${type} heading ${degrees} at ${width}x${height}: all bounds inside view`);
            }
          }
        }
        disposeShip(model.object);
      }
      if (width === 1238) halfHeights[degrees] = sharedHalfHeight;
    }
  }
  assert.ok(halfHeights[90] > halfHeights[0], "end-on views include hull length projected vertically");
  assert.ok(Math.abs(halfHeights[0] - halfHeights[180]) < 1e-10);
  assert.ok(Math.abs(halfHeights[90] - halfHeights[270]) < 1e-10);
  console.log(`Desktop half-heights: side ${halfHeights[0].toFixed(3)}, end ${halfHeights[90].toFixed(3)}`);
  disposeShip(largest.object);
});
