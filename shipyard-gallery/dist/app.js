import * as THREE from "three";
import { GLTFExporter } from "./vendor/three/GLTFExporter.js";
import { createShipModel, disposeShip, vesselCatalog } from "./ship-models.js";

const conceptAssets = {
  sloop: [
    "./assets/sloop-sunfish-runner-hull.png",
    "./assets/sloop-mango-jack-hull.png",
    "./assets/sloop-nightjar-hull.png"
  ],
  brig: [
    "./assets/brig-crown-and-compass-hull.png",
    "./assets/brig-red-wake-hull.png",
    "./assets/brig-la-estrella-hull.png"
  ],
  frigate: [
    "./assets/frigate-resolute-hull.png",
    "./assets/frigate-santa-brigida-hull.png",
    "./assets/frigate-sea-wraith-hull.png"
  ]
};

const state = { type: "sloop", wind: 45, heading: 0, speed: 38, motion: true };
const gallery = document.querySelector("#gallery");
const windRange = document.querySelector("#wind-range");
const speedRange = document.querySelector("#speed-range");
const headingRange = document.querySelector("#heading-range");
const windOutput = document.querySelector("#wind-output");
const speedOutput = document.querySelector("#speed-output");
const headingOutput = document.querySelector("#heading-output");
const motionToggle = document.querySelector("#motion-toggle");
const status = document.querySelector("#status");
const root = document.documentElement;
const previews = [];
let rafId = 0;
let startTime = performance.now();

const compassName = (degrees) => {
    const names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
    return names[Math.round(degrees / 45) % 8];
};

const signedAngle = (degrees) => ((degrees + 180) % 360) - 180;
const sailTrim = (degrees) => {
    const relative = signedAngle(degrees);
    const sign = relative === 0 ? 1 : Math.sign(relative);
    const folded = Math.min(Math.abs(relative), 180 - Math.abs(relative));
    return sign * Math.min(68, folded * 0.68);
};

const headingName = (degrees) => {
    const normalized = ((degrees % 360) + 360) % 360;
    if (normalized < 23 || normalized >= 337) return "BROADSIDE";
    if (normalized < 68) return "TURNING BOW";
    if (normalized < 113) return "BOW-ON";
    if (normalized < 158) return "TURNING PORT";
    if (normalized < 203) return "PORT SIDE";
    if (normalized < 248) return "TURNING STERN";
    if (normalized < 293) return "STERN-ON";
    return "TURNING STARBOARD";
};

function disposePreviews() {
  while (previews.length) {
    const preview = previews.pop();
    preview.resizeObserver.disconnect();
    disposeShip(preview.ship.object);
    preview.shadow.geometry.dispose();
    preview.shadow.material.dispose();
    preview.renderer.dispose();
    preview.renderer.forceContextLoss();
  }
}

function resizePreview(preview) {
  const width = Math.max(1, preview.stage.clientWidth);
  const height = Math.max(1, preview.stage.clientHeight);
  if (preview.width === width && preview.height === height) return;
  preview.width = width;
  preview.height = height;
  preview.renderer.setSize(width, height, false);
  const aspect = width / height;
  const halfHeight = preview.ship.fitHeight * 0.5;
  preview.camera.left = -halfHeight * aspect;
  preview.camera.right = halfHeight * aspect;
  preview.camera.top = halfHeight;
  preview.camera.bottom = -halfHeight;
  preview.camera.updateProjectionMatrix();
}

function makePreview(stage, type, index) {
  const canvas = stage.querySelector("canvas");
  const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true, powerPreference: "high-performance" });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.65));
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.08;

  const scene = new THREE.Scene();
  const ship = createShipModel(type, index);
  const headingGroup = new THREE.Group();
  headingGroup.name = "controlled heading";
  const motionGroup = new THREE.Group();
  motionGroup.name = "gentle ship motion";
  motionGroup.add(ship.object);
  headingGroup.add(motionGroup);
  scene.add(headingGroup);

  const center = ship.bounds.getCenter(new THREE.Vector3());
  const size = ship.bounds.getSize(new THREE.Vector3());
  const targetY = center.y - size.y * 0.05;
  const camera = new THREE.OrthographicCamera(-6, 6, 5, -5, 0.1, 60);
  camera.position.set(0, targetY + 8.1, 14);
  camera.lookAt(0, targetY, 0);
  camera.updateProjectionMatrix();

  const skyLight = new THREE.HemisphereLight(0xd6eaf1, 0x123645, 2.15);
  scene.add(skyLight);
  const sun = new THREE.DirectionalLight(0xffdfaa, 3.2);
  sun.position.set(7, 11, 9);
  scene.add(sun);
  const rim = new THREE.DirectionalLight(0x5cc4cf, 1.25);
  rim.position.set(-8, 4, -9);
  scene.add(rim);

  const shadow = new THREE.Mesh(
    new THREE.CircleGeometry(Math.max(size.x, size.z) * 0.33, 48),
    new THREE.MeshBasicMaterial({ color: 0x011921, transparent: true, opacity: 0.24, depthWrite: false })
  );
  shadow.scale.set(1, 0.3, 1);
  shadow.rotation.x = -Math.PI * 0.5;
  shadow.position.y = ship.bounds.min.y - 0.06;
  shadow.name = "water shadow";
  scene.add(shadow);

  const preview = {
    stage,
    renderer,
    scene,
    camera,
    ship,
    headingGroup,
    motionGroup,
    shadow,
    phase: Number(stage.dataset.phase || index),
    width: 0,
    height: 0
  };
  const resizeObserver = new ResizeObserver(() => resizePreview(preview));
  preview.resizeObserver = resizeObserver;
  resizeObserver.observe(stage);
  resizePreview(preview);
  previews.push(preview);
  return preview;
}

function renderGallery() {
    disposePreviews();
    const data = vesselCatalog[state.type];
    document.querySelector("#class-name").textContent = data.name;
    document.querySelector("#class-kicker").textContent = data.kicker;
    document.querySelector("#class-note").textContent = data.note;
    gallery.setAttribute("aria-labelledby", `tab-${state.type}`);
    gallery.innerHTML = data.ships.map((ship, index) => {
      return `<article class="ship-card">
        <div class="sea-window">
          <span class="ship-index">0${index + 1}</span>
          <span class="camera-mark">CAMERA · FIXED 30°</span>
          <div class="ship-stage" data-phase="${index * 1.9}">
            <canvas class="model-canvas" role="img" aria-label="Interactive three-dimensional ${state.type} model for ${ship.name}"></canvas>
            <p class="webgl-fallback" hidden>WebGL is needed to display this 3D ship.</p>
          </div>
          <span class="model-mark">TRUE 3D · DETAIL II</span>
          <span class="bearing-mark">HEADING · <b class="card-heading">${String(Math.round(state.heading)).padStart(3, "0")}°</b></span>
        </div>
        <div class="card-copy">
          <div><h4 class="ship-name">${ship.name}</h4><p class="ship-role">${ship.role}</p></div>
          <div class="asset-actions">
            <button class="asset-link model-download" type="button" data-index="${index}" aria-label="Download ${ship.name} 3D model as GLB">GLB ↓</button>
            <a class="asset-link" href="${conceptAssets[state.type][index]}" download aria-label="Download ${ship.name} painted concept reference">Concept ↓</a>
          </div>
        </div>
      </article>`;
    }).join("");
    gallery.querySelectorAll(".ship-stage").forEach((stage, index) => {
      try {
        makePreview(stage, state.type, index);
      } catch (error) {
        console.error("Unable to build 3D preview", error);
        stage.querySelector(".model-canvas").hidden = true;
        stage.querySelector(".webgl-fallback").hidden = false;
      }
    });
    gallery.querySelectorAll(".model-download").forEach((button) => {
      button.addEventListener("click", () => downloadModel(Number(button.dataset.index), button));
    });
    syncPreviewTransforms();
    status.textContent = `Showing ${data.ships.length} true 3D ${state.type} models.`;
}

function syncPreviewTransforms() {
  const trimDegrees = sailTrim(state.wind - state.heading);
  const trimRadians = THREE.MathUtils.degToRad(trimDegrees);
  const headingRadians = THREE.MathUtils.degToRad(state.heading);
  previews.forEach((preview) => {
    preview.stage.dataset.sailTrimDegrees = trimDegrees.toFixed(2);
    preview.headingGroup.rotation.y = headingRadians;
    preview.ship.sailPivots.forEach((pivot) => {
      pivot.rotation.y = trimRadians * (pivot.userData.trimFactor || 1);
    });
  });
}

function syncControls(announce = false) {
    windRange.value = String(state.wind);
    headingRange.value = String(state.heading);
    speedRange.value = String(state.speed);
    windOutput.textContent = `${String(Math.round(state.wind)).padStart(3, "0")}° · ${compassName(state.wind)}`;
    speedOutput.textContent = `${Math.round(state.speed)}%`;
    headingOutput.textContent = `${String(Math.round(state.heading)).padStart(3, "0")}° · ${headingName(state.heading)}`;
    root.style.setProperty("--wind-angle", `${state.wind}deg`);
    root.dataset.motion = state.motion ? "on" : "off";
    syncPreviewTransforms();
    document.querySelectorAll(".card-heading").forEach((label) => {
      label.textContent = `${String(Math.round(state.heading)).padStart(3, "0")}°`;
    });
    motionToggle.setAttribute("aria-pressed", String(state.motion));
    motionToggle.lastChild.textContent = state.motion ? " Motion on" : " Motion off";
    if (announce) status.textContent = `Heading ${Math.round(state.heading)} degrees, wind ${Math.round(state.wind)} degrees, speed ${Math.round(state.speed)} percent.`;
}

function setType(type) {
    if (!vesselCatalog[type]) throw new Error("Unknown vessel class");
    state.type = type;
    document.querySelectorAll(".tab").forEach((tab) => {
      const active = tab.dataset.type === type;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-selected", String(active));
      tab.tabIndex = active ? 0 : -1;
    });
    renderGallery();
}

function animate(now) {
    const elapsed = (now - startTime) / 1000;
    const strength = state.motion ? state.speed / 100 : 0;
    const amplitude = state.motion ? 0.09 + strength * 0.58 : 0;
    const rate = 0.24 + strength * 0.25;
    previews.forEach((preview) => {
      const phase = preview.phase;
      const wave = elapsed * rate * Math.PI * 2 + phase;
      const rollDegrees = Math.sin(wave) * amplitude;
      const pitchDegrees = Math.sin(wave * 0.58 + 0.8) * amplitude * 0.38;
      const heave = state.motion ? Math.sin(wave * 0.54) * (0.008 + strength * 0.038) : 0;
      preview.motionGroup.rotation.x = THREE.MathUtils.degToRad(rollDegrees);
      preview.motionGroup.rotation.z = THREE.MathUtils.degToRad(pitchDegrees);
      preview.motionGroup.position.y = heave;
      preview.stage.dataset.motionAmplitudeDegrees = amplitude.toFixed(3);
      preview.stage.dataset.rollDegrees = rollDegrees.toFixed(3);
      preview.stage.dataset.heave = heave.toFixed(4);
      resizePreview(preview);
      preview.renderer.render(preview.scene, preview.camera);
    });
    rafId = requestAnimationFrame(animate);
}

function downloadModel(index, button) {
  const preview = previews[index];
  if (!preview) return;
  const previousText = button.textContent;
  button.disabled = true;
  button.textContent = "Building…";
  status.textContent = `Building ${preview.ship.variant.name} GLB…`;
  const exportRoot = preview.headingGroup.clone(true);
  exportRoot.name = `${preview.ship.variant.name} — heading ${Math.round(state.heading)}°`;
  exportRoot.userData = {
    ...exportRoot.userData,
    windDegrees: state.wind,
    headingDegrees: state.heading,
    note: "Sail pivots are named wind-trimming mast/rig for runtime animation."
  };
  const exportedMotion = exportRoot.children[0];
  exportedMotion.rotation.set(0, 0, 0);
  exportedMotion.position.set(0, 0, 0);
  const exporter = new GLTFExporter();
  exporter.parse(
    exportRoot,
    (result) => {
      const blob = new Blob([result], { type: "model/gltf-binary" });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = `${preview.ship.variant.id}.glb`;
      anchor.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      button.disabled = false;
      button.textContent = previousText;
      status.textContent = `${preview.ship.variant.name} GLB downloaded.`;
    },
    (error) => {
      console.error("GLB export failed", error);
      button.disabled = false;
      button.textContent = previousText;
      status.textContent = `Could not export ${preview.ship.variant.name}.`;
    },
    { binary: true, onlyVisible: true, trs: false }
  );
}

document.querySelectorAll(".tab").forEach((tab) => {
    tab.addEventListener("click", () => setType(tab.dataset.type));
    tab.addEventListener("keydown", (event) => {
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
      event.preventDefault();
      const types = Object.keys(vesselCatalog);
      const step = event.key === "ArrowRight" ? 1 : -1;
      const next = types[(types.indexOf(state.type) + step + types.length) % types.length];
      setType(next);
      document.querySelector(`#tab-${next}`).focus();
    });
});

windRange.addEventListener("input", () => { state.wind = Number(windRange.value); syncControls(); });
windRange.addEventListener("change", () => syncControls(true));
headingRange.addEventListener("input", () => { state.heading = Number(headingRange.value); syncControls(); });
headingRange.addEventListener("change", () => syncControls(true));
speedRange.addEventListener("input", () => { state.speed = Number(speedRange.value); syncControls(); });
speedRange.addEventListener("change", () => syncControls(true));
motionToggle.addEventListener("click", () => { state.motion = !state.motion; syncControls(true); });

function registerWebMcp() {
    const context = document.modelContext;
    if (!context?.registerTool) return;
    const report = (error) => console.warn("WebMCP registration failed", error);
    const registration = context.registerTool({
      name: "configure_shipyard_preview",
      title: "Configure shipyard preview",
      description: "Select a vessel class and set its fixed-camera heading, wind, speed, and motion in the visible Tortuga ship preview.",
      inputSchema: {
        type: "object",
        properties: {
          vesselClass: { type: "string", enum: ["sloop", "brig", "frigate"] },
          windDegrees: { type: "number", minimum: 0, maximum: 359 },
          headingDegrees: { type: "number", minimum: 0, maximum: 359 },
          speedPercent: { type: "number", minimum: 0, maximum: 100 },
          motion: { type: "boolean" }
        },
        additionalProperties: false
      },
      annotations: { readOnlyHint: false, untrustedContentHint: false },
      execute(input) {
        if (!input || typeof input !== "object") throw new TypeError("Input must be an object");
        if (input.vesselClass !== undefined && !vesselCatalog[input.vesselClass]) throw new RangeError("vesselClass must be sloop, brig, or frigate");
        if (input.windDegrees !== undefined && (!Number.isFinite(input.windDegrees) || input.windDegrees < 0 || input.windDegrees > 359)) throw new RangeError("windDegrees must be between 0 and 359");
        if (input.headingDegrees !== undefined && (!Number.isFinite(input.headingDegrees) || input.headingDegrees < 0 || input.headingDegrees > 359)) throw new RangeError("headingDegrees must be between 0 and 359");
        if (input.speedPercent !== undefined && (!Number.isFinite(input.speedPercent) || input.speedPercent < 0 || input.speedPercent > 100)) throw new RangeError("speedPercent must be between 0 and 100");
        if (input.vesselClass !== undefined && input.vesselClass !== state.type) setType(input.vesselClass);
        if (input.windDegrees !== undefined) state.wind = input.windDegrees;
        if (input.headingDegrees !== undefined) state.heading = input.headingDegrees;
        if (input.speedPercent !== undefined) state.speed = input.speedPercent;
        if (input.motion !== undefined) state.motion = input.motion;
        syncControls(true);
        return { vesselClass: state.type, windDegrees: state.wind, headingDegrees: state.heading, speedPercent: state.speed, motion: state.motion };
      }
    });
    void Promise.resolve(registration).catch(report);
}

renderGallery();
syncControls();
cancelAnimationFrame(rafId);
rafId = requestAnimationFrame(animate);
registerWebMcp();
