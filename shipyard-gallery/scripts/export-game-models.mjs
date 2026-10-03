import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import * as THREE from "three";
import { GLTFExporter } from "three/examples/jsm/exporters/GLTFExporter.js";
import { mergeGeometries } from "three/examples/jsm/utils/BufferGeometryUtils.js";
import { createShipModel, disposeShip } from "../dist/ship-models.js";

// GLTFExporter targets browsers. Node supplies Blob, but not FileReader.
class NodeFileReader {
  result = null;
  error = null;
  onloadend = null;
  onerror = null;

  readAsArrayBuffer(blob) {
    blob.arrayBuffer().then((value) => this.#finish(value), (error) => this.#fail(error));
  }

  readAsDataURL(blob) {
    blob.arrayBuffer().then((value) => {
      const mime = blob.type || "application/octet-stream";
      this.#finish(`data:${mime};base64,${Buffer.from(value).toString("base64")}`);
    }, (error) => this.#fail(error));
  }

  #finish(value) {
    this.result = value;
    queueMicrotask(() => this.onloadend?.({ target: this }));
  }

  #fail(error) {
    this.error = error;
    queueMicrotask(() => this.onerror?.(error));
  }
}

globalThis.FileReader ??= NodeFileReader;

const here = path.dirname(fileURLToPath(import.meta.url));
const outputDirectory = path.resolve(here, "../../game/assets/ships/3d");
const representatives = {
  sloop: 0,   // Sunfish Runner
  brig: 0,    // Crown & Compass
  frigate: 0  // Resolute
};

function isRenderable(object) {
  return object.isMesh || object.isLine || object.isLineSegments;
}

function closestBatchRoot(object, modelRoot, protectedRoots) {
  for (let cursor = object; cursor && cursor !== modelRoot; cursor = cursor.parent) {
    if (protectedRoots.has(cursor)) return cursor;
  }
  return modelRoot;
}

function geometrySignature(object) {
  const attributes = Object.entries(object.geometry.attributes)
    .map(([name, attribute]) => `${name}:${attribute.itemSize}:${attribute.normalized}:${attribute.array.constructor.name}`)
    .sort()
    .join(",");
  const morphAttributes = Object.entries(object.geometry.morphAttributes)
    .map(([name, list]) => `${name}:${list.length}`)
    .sort()
    .join(",");
  const primitive = object.isMesh ? "mesh" : "lines";
  return [primitive, object.material.uuid, object.geometry.index ? "indexed" : "plain", attributes, morphAttributes].join("|");
}

function batchModel(modelRoot, sailPivots, sailSurfaces) {
  modelRoot.updateMatrixWorld(true);
  const protectedRoots = new Set([...sailPivots, ...sailSurfaces]);
  const batches = new Map();

  modelRoot.traverse((object) => {
    if (!isRenderable(object) || protectedRoots.has(object)) return;
    if (Array.isArray(object.material)) {
      throw new Error(`Cannot batch multi-material object ${object.name}`);
    }
    const scope = closestBatchRoot(object, modelRoot, protectedRoots);
    const key = `${scope.uuid}|${geometrySignature(object)}`;
    if (!batches.has(key)) batches.set(key, { scope, material: object.material, mesh: object.isMesh, objects: [] });
    batches.get(key).objects.push(object);
  });

  let batchIndex = 0;
  for (const batch of batches.values()) {
    const inverseScope = batch.scope.matrixWorld.clone().invert();
    const geometries = batch.objects.map((object) => {
      const geometry = object.geometry.clone();
      geometry.applyMatrix4(inverseScope.clone().multiply(object.matrixWorld));
      return geometry;
    });
    const merged = geometries.length === 1 ? geometries[0] : mergeGeometries(geometries, false);
    if (!merged) throw new Error(`Unable to batch ${batch.objects[0].name}`);
    for (const object of batch.objects) object.removeFromParent();
    const combined = batch.mesh
      ? new THREE.Mesh(merged, batch.material)
      : new THREE.LineSegments(merged, batch.material);
    combined.name = `${batch.mesh ? "Mesh" : "Lines"}_Batch_${batchIndex}`;
    batch.scope.add(combined);
    batchIndex += 1;
    if (geometries.length > 1) geometries.forEach((geometry) => geometry.dispose());
  }

  const keep = new Set([modelRoot, ...sailPivots, ...sailSurfaces]);
  modelRoot.traverse((object) => {
    if (object.name.startsWith("Muzzle_")) keep.add(object);
  });
  const prune = (object) => {
    [...object.children].forEach(prune);
    if (object !== modelRoot && object.isGroup && object.children.length === 0 && !keep.has(object)) {
      object.removeFromParent();
    }
  };
  prune(modelRoot);
  modelRoot.updateMatrixWorld(true);
  return batchIndex + sailSurfaces.length;
}

await mkdir(outputDirectory, { recursive: true });

for (const [vesselClass, variantIndex] of Object.entries(representatives)) {
  const model = createShipModel(vesselClass, variantIndex);

  // Stable names let the Godot presentation animate the exported rig without
  // depending on the display names used by the web gallery.
  model.sailPivots.forEach((pivot, index) => {
    pivot.name = `SailPivot_${index}`;
  });
  let sailIndex = 0;
  const sailSurfaces = [];
  model.object.traverse((child) => {
    if (child.isMesh && /sail|jib|spanker/i.test(child.name)) {
      child.userData.originalName = child.name;
      child.name = `SailSurface_${sailIndex}`;
      sailSurfaces.push(child);
      sailIndex += 1;
    }
  });
  // Fail before exporting if a barrel tip lacks its stable gameplay mapping.
  const expectedGuns = { sloop: 4, brig: 6, frigate: 8 }[vesselClass];
  const barrels = [];
  model.object.traverse((child) => { if (child.name === "cannon barrel") barrels.push(child); });
  if (barrels.length !== expectedGuns * 2) throw new Error(`${vesselClass}: incorrect barrel count`);
  for (const side of ["port", "starboard"]) {
    let previousX = Infinity;
    for (let index = 0; index < expectedGuns; index += 1) {
      const marker = model.object.getObjectByName(`Muzzle_${side}_${index}`);
      if (!marker || marker.position.x >= previousX) throw new Error(`${vesselClass}: missing or unordered muzzle`);
      const sign = side === "starboard" ? 1 : -1;
      const barrel = barrels.find((item) => item.position.x === marker.position.x && Math.sign(item.position.z) === sign);
      const tip = barrel.position.clone();
      tip.z += sign * barrel.geometry.parameters.height / 2;
      if (tip.distanceTo(marker.position) > 1e-6) throw new Error(`${vesselClass}: muzzle misses barrel tip`);
      previousX = marker.position.x;
    }
  }
  const renderableCount = batchModel(model.object, model.sailPivots, sailSurfaces);
  model.object.userData.fitHeight = model.fitHeight;
  model.object.userData.sailPivotCount = model.sailPivots.length;
  model.object.userData.sailSurfaceCount = sailIndex;
  model.object.userData.renderableCount = renderableCount;
  model.object.updateMatrixWorld(true);

  const glb = await new GLTFExporter().parseAsync(model.object, {
    binary: true,
    onlyVisible: true,
    trs: true
  });
  const target = path.join(outputDirectory, `${vesselClass}.glb`);
  await writeFile(target, Buffer.from(glb));
  console.log(`${vesselClass}: ${model.variant.name}, ${model.sailPivots.length} rig pivots, ${sailIndex} sail surfaces, ${renderableCount} batched renderables, ${glb.byteLength} bytes`);
  disposeShip(model.object);
}
