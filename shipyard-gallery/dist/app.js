import * as THREE from "three";
import { GLTFExporter } from "./vendor/three/GLTFExporter.js";
import { OrbitControls } from "./vendor/three/OrbitControls.js";
import { createShipModel, disposeShip, vesselCatalog } from "./ship-models.js";
import { CannonSmoke, FIRE_COOLDOWN } from "./cannon-smoke.js";
import { shipFrame } from "./viewer-framing.js";

const state = { type: "sloop", wind: 45, heading: 0, speed: 38, motion: !matchMedia("(prefers-reduced-motion: reduce)").matches };
const stage = document.querySelector(".ship-stage");
const canvas = stage.querySelector("canvas");
const status = document.querySelector("#status");
const fireButton = document.querySelector("#fire-cannons");
const downloadButton = document.querySelector("#model-download");
const root = document.documentElement;
let viewer;
let rafId = 0;
let exportBusy = false;

const signedAngle = (degrees) => ((degrees + 180) % 360 + 360) % 360 - 180;
const sailTrim = (degrees) => {
  const relative = signedAngle(degrees);
  return (Math.sign(relative) || 1) * Math.min(68, Math.min(Math.abs(relative), 180 - Math.abs(relative)) * 0.68);
};

function makeViewer() {
  const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true, powerPreference: "high-performance" });
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 1.65));
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.08;
  const scene = new THREE.Scene();
  const headingGroup = new THREE.Group();
  const motionGroup = new THREE.Group();
  headingGroup.add(motionGroup);
  scene.add(headingGroup);
  scene.add(new THREE.HemisphereLight(0xd6eaf1, 0x123645, 2.15));
  for (const [color, intensity, position] of [[0xffdfaa, 3.2, [7, 11, 9]], [0x5cc4cf, 1.25, [-8, 4, -9]]]) {
    const light = new THREE.DirectionalLight(color, intensity);
    light.position.set(...position);
    scene.add(light);
  }
  const largest = createShipModel("galleon");
  const center = largest.bounds.getCenter(new THREE.Vector3());
  const largestBounds = largest.bounds.clone();
  disposeShip(largest.object);
  const camera = new THREE.OrthographicCamera(-12, 12, 8, -8, 0.1, 100);
  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true;
  controls.enablePan = false;
  controls.minZoom = 0.65;
  controls.maxZoom = 5;
  controls.minPolarAngle = 0.08;
  controls.maxPolarAngle = Math.PI * 0.88;
  controls.zoomSpeed = 0.8;
  const smoke = new CannonSmoke();
  scene.add(smoke.object);
  return { renderer, scene, camera, controls, headingGroup, motionGroup, smoke, center, largestBounds, fitHeading: null, width: 0, height: 0, ship: null, contextLost: false, frames: 0, sampledAt: performance.now() };
}

function resizeViewer(force = false) {
  if (!viewer) return;
  const width = Math.max(1, stage.clientWidth);
  const height = Math.max(1, stage.clientHeight);
  if (!force && viewer.width === width && viewer.height === height && viewer.fitHeading === state.heading) return;
  if (viewer.width !== width || viewer.height !== height) viewer.renderer.setSize(width, height, false);
  viewer.width = width;
  viewer.height = height;
  viewer.fitHeading = state.heading;
  const aspect = width / height;
  const { halfHeight } = shipFrame(viewer.largestBounds, state.heading, aspect, viewer.camera.quaternion);
  Object.assign(viewer.camera, { left: -halfHeight * aspect, right: halfHeight * aspect, top: halfHeight, bottom: -halfHeight });
  viewer.camera.updateProjectionMatrix();
}

function resetView() {
  if (!viewer) return;
  const { camera, controls } = viewer;
  viewer.ship?.object.updateWorldMatrix(true, false);
  const center = viewer.ship ? viewer.ship.object.localToWorld(viewer.ship.bounds.getCenter(new THREE.Vector3())) : viewer.center;
  // Flush damped orbit deltas before setting the new default pose.
  controls.enableDamping = false;
  controls.update();
  controls.enableDamping = true;
  controls.target.copy(center);
  camera.position.copy(center).add(new THREE.Vector3(0, 10, 18));
  camera.zoom = 1;
  camera.updateProjectionMatrix();
  camera.lookAt(center);
  controls.saveState();
  controls.reset();
  controls.update();
  resizeViewer(true);
}

function syncTransforms() {
  if (!viewer?.ship) return;
  const trim = sailTrim(state.wind - state.heading);
  viewer.headingGroup.rotation.y = THREE.MathUtils.degToRad(state.heading);
  viewer.ship.sailPivots.forEach((pivot) => { pivot.rotation.y = THREE.MathUtils.degToRad(trim) * (pivot.userData.trimFactor ?? 1); });
  stage.dataset.sailTrimDegrees = trim.toFixed(2);
  // Recenter heading changes without disturbing the orbit angle or zoom.
  viewer.ship.object.updateWorldMatrix(true, false);
  const center = viewer.ship.object.localToWorld(viewer.ship.bounds.getCenter(new THREE.Vector3()));
  if (viewer.fitHeading !== state.heading) {
    const delta = center.clone().sub(viewer.controls.target);
    viewer.controls.target.copy(center);
    viewer.camera.position.add(delta);
  }
  resizeViewer();
}

function syncControls(announce = false) {
  for (const key of ["wind", "heading", "speed"]) document.querySelector(`#${key}-range`).value = String(state[key]);
  const degreeLabel = (degrees) => `${String(Math.round(degrees)).padStart(3, "0")}°`;
  document.querySelector("#wind-output").textContent = `${degreeLabel(state.wind)} · ${["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(state.wind / 45) % 8]}`;
  document.querySelector("#heading-output").textContent = degreeLabel(state.heading);
  document.querySelector("#speed-output").textContent = `${Math.round(state.speed)}%`;
  document.querySelector(".card-heading").textContent = degreeLabel(state.heading);
  root.style.setProperty("--wind-angle", `${state.wind}deg`);
  root.dataset.motion = state.motion ? "on" : "off";
  const toggle = document.querySelector("#motion-toggle");
  toggle.setAttribute("aria-pressed", String(state.motion));
  toggle.querySelector(".motion-label").textContent = state.motion ? "Motion on" : "Motion off";
  if (!state.motion && viewer) { viewer.motionGroup.rotation.set(0, 0, 0); viewer.motionGroup.position.y = 0; }
  syncTransforms();
  if (announce && viewer?.ship && !viewer.contextLost) status.textContent = `Heading ${Math.round(state.heading)} degrees, wind ${Math.round(state.wind)} degrees, speed ${Math.round(state.speed)} percent.`;
}

function setType(type) {
  if (!vesselCatalog[type]) throw new RangeError("Unknown vessel class");
  state.type = type;
  document.querySelectorAll(".tab").forEach((tab) => {
    const active = tab.dataset.type === type;
    tab.classList.toggle("is-active", active);
    tab.setAttribute("aria-selected", String(active));
    tab.tabIndex = active ? 0 : -1;
  });
  document.querySelector("#gallery").setAttribute("aria-labelledby", `tab-${type}`);
  const data = vesselCatalog[type];
  const variant = data.ships[0];
  document.querySelector("#class-name").textContent = variant.name;
  document.querySelector("#class-kicker").textContent = `${data.name.toUpperCase()} · ${data.kicker}`;
  document.querySelector("#class-note").textContent = data.note;
  canvas.setAttribute("aria-label", `Three-dimensional ${type}, ${variant.name}. Drag to rotate; use arrows to orbit and plus or minus to zoom.`);
  if (!viewer) { document.querySelector("#gun-count").textContent = "3D preview unavailable"; return; }
  viewer.smoke.clear();
  const replacement = createShipModel(type);
  if (viewer.ship) { viewer.ship.object.removeFromParent(); disposeShip(viewer.ship.object); }
  viewer.ship = replacement;
  viewer.motionGroup.rotation.set(0, 0, 0);
  viewer.motionGroup.position.set(0, 0, 0);
  viewer.motionGroup.add(replacement.object);
  const perSide = replacement.cannons.filter((cannon) => cannon.side === "port").length;
  document.querySelector("#gun-count").textContent = `${replacement.cannons.length} cannons · ${perSide} per side`;
  fireButton.disabled = viewer.contextLost;
  downloadButton.disabled = exportBusy || viewer.contextLost;
  downloadButton.setAttribute("aria-label", `Download ${variant.name} ship as GLB`);
  syncTransforms();
  resizeViewer();
  resetView();
  if (!viewer.contextLost) status.textContent = `Showing ${variant.name}, ${replacement.cannons.length} cannons. Drag to rotate and scroll or pinch to zoom.`;
}

function zoomBy(factor) {
  if (!viewer) return;
  viewer.camera.zoom = THREE.MathUtils.clamp(viewer.camera.zoom * factor, viewer.controls.minZoom, viewer.controls.maxZoom);
  viewer.camera.updateProjectionMatrix();
}

function fireCannons() {
  if (!viewer?.ship || viewer.contextLost) return false;
  syncTransforms();
  viewer.scene.updateMatrixWorld(true);
  if (!viewer.smoke.fire(viewer.ship.cannons, performance.now() / 1000)) return false;
  fireButton.disabled = true;
  status.textContent = `${viewer.ship.variant.name} fired all ${viewer.ship.cannons.length} cannons.`;
  return true;
}

function animate(now) {
  if (document.hidden || viewer?.contextLost) { rafId = 0; return; }
  if (viewer?.ship) {
    const strength = state.motion ? state.speed / 100 : 0;
    const amplitude = state.motion ? 0.09 + strength * 0.58 : 0;
    const wave = now / 1000 * (0.24 + strength * 0.25) * Math.PI * 2;
    viewer.motionGroup.rotation.x = THREE.MathUtils.degToRad(Math.sin(wave) * amplitude);
    viewer.motionGroup.rotation.z = THREE.MathUtils.degToRad(Math.sin(wave * 0.58 + 0.8) * amplitude * 0.38);
    viewer.motionGroup.position.y = state.motion ? Math.sin(wave * 0.54) * (0.008 + strength * 0.038) : 0;
    stage.dataset.motionAmplitudeDegrees = amplitude.toFixed(3);
    stage.dataset.rollDegrees = THREE.MathUtils.radToDeg(viewer.motionGroup.rotation.x).toFixed(3);
    stage.dataset.heave = viewer.motionGroup.position.y.toFixed(4);
    viewer.smoke.update(now / 1000);
    fireButton.disabled = now / 1000 - viewer.smoke.lastFire < FIRE_COOLDOWN;
    viewer.controls.update();
    resizeViewer();
    viewer.renderer.render(viewer.scene, viewer.camera);
    viewer.frames += 1;
    if (now - viewer.sampledAt >= 1000) {
      stage.dataset.fps = (viewer.frames * 1000 / (now - viewer.sampledAt)).toFixed(1);
      stage.dataset.renderCalls = String(viewer.renderer.info.render.calls);
      stage.dataset.triangles = String(viewer.renderer.info.render.triangles);
      stage.dataset.smokeActiveCount = String(viewer.smoke.activeCount);
      viewer.sampledAt = now;
      viewer.frames = 0;
    }
  }
  rafId = requestAnimationFrame(animate);
}

async function downloadModel() {
  if (!viewer?.ship || viewer.contextLost || exportBusy) return;
  exportBusy = true;
  downloadButton.disabled = true;
  const variant = viewer.ship.variant;
  // Clone only the ship: motion groups, smoke, lighting, and scenery cannot leak.
  const exportRoot = viewer.ship.object.clone(true);
  exportRoot.userData = { ...exportRoot.userData, windDegrees: state.wind, note: "Named wind-trimming rig pivots support sail animation." };
  status.textContent = `Building ${variant.name} GLB…`;
  try {
    const result = await new GLTFExporter().parseAsync(exportRoot, { binary: true, onlyVisible: true, trs: true });
    const url = URL.createObjectURL(new Blob([result], { type: "model/gltf-binary" }));
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `${variant.id}.glb`;
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    status.textContent = `${variant.name} GLB download requested.`;
  } catch (error) {
    console.error("GLB export failed", error);
    status.textContent = `Could not export ${variant.name}. Please try again.`;
  } finally { exportBusy = false; downloadButton.disabled = !viewer?.ship || viewer.contextLost; }
}

for (const tab of document.querySelectorAll(".tab")) {
  tab.addEventListener("click", () => setType(tab.dataset.type));
  tab.addEventListener("keydown", (event) => {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const types = Object.keys(vesselCatalog);
    const nextIndex = event.key === "Home" ? 0 : event.key === "End" ? types.length - 1 : (types.indexOf(state.type) + (event.key === "ArrowRight" ? 1 : -1) + types.length) % types.length;
    setType(types[nextIndex]);
    document.querySelector(`#tab-${state.type}`).focus();
  });
}
for (const key of ["wind", "heading", "speed"]) {
  const slider = document.querySelector(`#${key}-range`);
  slider.addEventListener("input", () => { state[key] = Number(slider.value); syncControls(); });
  slider.addEventListener("change", () => syncControls(true));
}
document.querySelector("#motion-toggle").addEventListener("click", () => { state.motion = !state.motion; syncControls(true); });
document.querySelector("#zoom-in").addEventListener("click", () => zoomBy(1.25));
document.querySelector("#zoom-out").addEventListener("click", () => zoomBy(0.8));
document.querySelector("#reset-view").addEventListener("click", () => { resetView(); if (viewer && !viewer.contextLost) status.textContent = "View reset. Drag to rotate and scroll or pinch to zoom."; });
fireButton.addEventListener("click", fireCannons);
downloadButton.addEventListener("click", downloadModel);
canvas.addEventListener("keydown", (event) => {
  if (!viewer) return;
  const arrows = { ArrowLeft: [-0.12, 0], ArrowRight: [0.12, 0], ArrowUp: [0, -0.1], ArrowDown: [0, 0.1] };
  if (arrows[event.key]) {
    event.preventDefault();
    const spherical = new THREE.Spherical().setFromVector3(viewer.camera.position.clone().sub(viewer.controls.target));
    spherical.theta += arrows[event.key][0];
    spherical.phi = THREE.MathUtils.clamp(spherical.phi + arrows[event.key][1], viewer.controls.minPolarAngle, viewer.controls.maxPolarAngle);
    viewer.camera.position.copy(viewer.controls.target).add(new THREE.Vector3().setFromSpherical(spherical));
    viewer.controls.update();
  } else if (["+", "=", "-"].includes(event.key)) { event.preventDefault(); zoomBy(event.key === "-" ? 0.8 : 1.25); }
  else if (event.key.toLowerCase() === "r") { event.preventDefault(); resetView(); }
});
document.addEventListener("visibilitychange", () => {
  if (document.hidden) { cancelAnimationFrame(rafId); rafId = 0; }
  else if (!rafId && viewer && !viewer.contextLost) { viewer.frames = 0; viewer.sampledAt = performance.now(); rafId = requestAnimationFrame(animate); }
});
canvas.addEventListener("webglcontextlost", (event) => {
  event.preventDefault(); cancelAnimationFrame(rafId); rafId = 0;
  if (viewer) { viewer.contextLost = true; viewer.controls.enabled = false; }
  fireButton.disabled = downloadButton.disabled = true;
  status.textContent = "The 3D display lost its graphics context. Waiting for recovery; reload if it does not return.";
});
canvas.addEventListener("webglcontextrestored", () => {
  if (!viewer) return;
  viewer.contextLost = false;
  viewer.controls.enabled = true;
  fireButton.disabled = false;
  downloadButton.disabled = exportBusy;
  status.textContent = "The 3D display has recovered.";
  if (!document.hidden && !rafId) { viewer.frames = 0; viewer.sampledAt = performance.now(); rafId = requestAnimationFrame(animate); }
});

function registerWebMcp() {
  if (!document.modelContext?.registerTool) return;
  void Promise.resolve(document.modelContext.registerTool({
    name: "configure_shipyard_preview", title: "Configure shipyard preview",
    description: "Select Sloop, Brig, Frigate, or Galleon, set ship heading/wind/speed/motion, zoom or reset the orbit view, and fire all mounted cannons.",
    inputSchema: { type: "object", properties: {
      vesselClass: { type: "string", enum: Object.keys(vesselCatalog) },
      windDegrees: { type: "number", minimum: 0, maximum: 359 },
      headingDegrees: { type: "number", minimum: 0, maximum: 359 },
      speedPercent: { type: "number", minimum: 0, maximum: 100 },
      motion: { type: "boolean" }, zoom: { type: "number", minimum: 0.65, maximum: 5 },
      resetView: { type: "boolean" }, fireCannons: { type: "boolean" }
    }, additionalProperties: false },
    annotations: { readOnlyHint: false, untrustedContentHint: false },
    execute(input) {
      if (!input || typeof input !== "object") throw new TypeError("Input must be an object");
      if (input.vesselClass !== undefined && !Object.hasOwn(vesselCatalog, input.vesselClass)) throw new RangeError("Unknown vessel class");
      for (const [key, max] of [["windDegrees", 359], ["headingDegrees", 359], ["speedPercent", 100], ["zoom", 5]]) {
        if (input[key] !== undefined && (!Number.isFinite(input[key]) || input[key] < (key === "zoom" ? 0.65 : 0) || input[key] > max)) throw new RangeError(`Invalid ${key}`);
      }
      for (const key of ["motion", "resetView", "fireCannons"]) if (input[key] !== undefined && typeof input[key] !== "boolean") throw new TypeError(`${key} must be boolean`);
      if (input.vesselClass !== undefined && input.vesselClass !== state.type) setType(input.vesselClass);
      for (const [key, property] of [["windDegrees", "wind"], ["headingDegrees", "heading"], ["speedPercent", "speed"], ["motion", "motion"]]) if (input[key] !== undefined) state[property] = input[key];
      syncControls(true);
      if (input.resetView) resetView();
      if (input.zoom !== undefined && viewer) { viewer.camera.zoom = input.zoom; viewer.camera.updateProjectionMatrix(); }
      const fired = input.fireCannons ? fireCannons() : false;
      return { vesselClass: state.type, windDegrees: state.wind, headingDegrees: state.heading, speedPercent: state.speed, motion: state.motion, zoom: viewer?.camera.zoom ?? null, fired, cannonCount: viewer?.ship?.cannons.length ?? 0 };
    }
  })).catch((error) => console.warn("WebMCP registration failed", error));
}

try { viewer = makeViewer(); setType(state.type); syncControls(); if (!document.hidden) rafId = requestAnimationFrame(animate); }
catch (error) {
  console.error("Unable to build 3D viewer", error);
  canvas.hidden = true;
  stage.querySelector(".webgl-fallback").hidden = false;
  fireButton.disabled = downloadButton.disabled = true;
  document.querySelector("#gun-count").textContent = "3D preview unavailable";
  const webglError = /WebGL|context/i.test(error.message);
  stage.querySelector(".webgl-fallback").textContent = webglError ? "WebGL is needed to display this 3D ship." : "The 3D ship could not be loaded. Reload to try again.";
  for (const id of ["zoom-in", "zoom-out", "reset-view"]) document.querySelector(`#${id}`).disabled = true;
  status.textContent = webglError ? "The 3D viewer is unavailable. WebGL is required; try a browser with graphics acceleration enabled." : "The 3D ship could not be loaded. Reload to try again.";
}
registerWebMcp();
