import * as THREE from "three";
import { mergeGeometries } from "./vendor/three/BufferGeometryUtils.js";

export const vesselCatalog = {
  sloop: {
    name: "Sloop",
    kicker: "QUICK · ONE MAST",
    note: "Honey-oak hull, navy trim, and a compact open deck under a gaff sail and jib.",
    fitHeight: 7.2,
    ships: [
      {
        id: "sunfish-runner",
        name: "Sunfish Runner",
        role: "Long, bright merchant-runner",
        scale: { length: 1.05, beam: 0.92, depth: 0.96 },
        guns: 2,
        palette: { hull: 0xb87932, deck: 0xd6a45c, trim: 0x173a63, accent: 0xc79a42, iron: 0x202a31, sail: 0xefe2c1, rope: 0x7c5432 }
      },
      {
        id: "mango-jack",
        name: "Mango Jack",
        role: "Full-bodied coastal privateer",
        scale: { length: 0.96, beam: 1.08, depth: 1.05 },
        guns: 3,
        patched: true,
        palette: { hull: 0x2c7b72, deck: 0xb78655, trim: 0xd35d4b, accent: 0xc39345, iron: 0x29343a, sail: 0xe6d7b7, rope: 0x6f4f36 }
      },
      {
        id: "nightjar",
        name: "Nightjar",
        role: "Low-profile indigo smuggler",
        scale: { length: 1.02, beam: 0.97, depth: 0.9 },
        guns: 2,
        lowProfile: true,
        palette: { hull: 0x18283f, deck: 0x574a3c, trim: 0x9b654a, accent: 0x3f766b, iron: 0x111821, sail: 0xd8cfb8, rope: 0x544336 }
      }
    ]
  },
  brig: {
    name: "Brig",
    kicker: "BALANCED · TWO MASTS",
    note: "Deep walnut hull, royal blue bands, square sails, and brass-fitted stern cabin.",
    fitHeight: 9.1,
    ships: [
      {
        id: "crown-and-compass",
        name: "Crown & Compass",
        role: "Orderly high-freeboard naval brig",
        scale: { length: 1, beam: 0.97, depth: 1.04 },
        guns: 5,
        cabin: 0.68,
        twinLanterns: true,
        palette: { hull: 0x6b3f22, deck: 0xa87545, trim: 0x173f78, accent: 0xd4a941, iron: 0x222831, sail: 0xe8dcbd, rope: 0x66503a }
      },
      {
        id: "red-wake",
        name: "Red Wake",
        role: "Long, low and aggressive corsair",
        scale: { length: 1.04, beam: 0.9, depth: 0.98 },
        guns: 6,
        lowProfile: true,
        patched: true,
        palette: { hull: 0x3a1d18, deck: 0x694430, trim: 0x9d2530, accent: 0xb17c32, iron: 0x17191e, sail: 0xd6c6a4, rope: 0x554238 }
      },
      {
        id: "la-estrella",
        name: "La Estrella",
        role: "Broad, ornate Caribbean trader",
        scale: { length: 0.97, beam: 1.1, depth: 1.1 },
        guns: 4,
        cabin: 0.82,
        ornate: true,
        palette: { hull: 0xc18b54, deck: 0xd8b67d, trim: 0x15999b, accent: 0xe0b94f, iron: 0x564536, sail: 0xeee1bc, rope: 0x826044 }
      }
    ]
  },
  frigate: {
    name: "Frigate",
    kicker: "HEAVY · THREE MASTS",
    note: "Long blackened oak hull, cream gunport band, and a substantial stern gallery.",
    fitHeight: 10.8,
    ships: [
      {
        id: "resolute",
        name: "Resolute",
        role: "Tall, disciplined navy frigate",
        scale: { length: 1.03, beam: 1, depth: 1.08 },
        guns: 8,
        upperGuns: 6,
        cabin: 0.98,
        palette: { hull: 0x202b34, deck: 0x8a6947, trim: 0xd8c79d, accent: 0xc39a4a, iron: 0x171a1c, sail: 0xe5d8b8, rope: 0x66513c }
      },
      {
        id: "santa-brigida",
        name: "Santa Brígida",
        role: "Gilded broad-beamed warship",
        scale: { length: 1, beam: 1.06, depth: 1.04 },
        guns: 8,
        upperGuns: 6,
        cabin: 1.15,
        ornate: true,
        palette: { hull: 0x6f351f, deck: 0xa36f3f, trim: 0xb52e22, accent: 0xd4a33c, iron: 0x252225, sail: 0xefe0bd, rope: 0x71492f }
      },
      {
        id: "sea-wraith",
        name: "Sea Wraith",
        role: "Lean, weathered pirate-hunter",
        scale: { length: 1.05, beam: 0.92, depth: 0.94 },
        guns: 7,
        upperGuns: 5,
        cabin: 0.72,
        lowProfile: true,
        patched: true,
        palette: { hull: 0x252b2b, deck: 0x625243, trim: 0x6fa79c, accent: 0x8b7b50, iron: 0x151a1b, sail: 0xd7d0ba, rope: 0x4d463e }
      }
    ]
  },
  galleon: {
    name: "Galleon",
    kicker: "COMMANDING · THREE MASTS · TWO GUN DECKS",
    note: "Broad chestnut hull, crimson and gold, raised forecastle, and a stepped sterncastle beneath a lateen mizzen.",
    fitHeight: 14,
    ships: [{
      id: "galleon", name: "Galleon", role: "Grand two-deck treasure ship",
      scale: { length: 1, beam: 1, depth: 1 }, guns: 8, upperGuns: 8,
      cabin: 1.5, ornate: true,
      palette: { hull: 0x743e28, deck: 0xb7814f, trim: 0x9f2634, accent: 0xd9b35c, iron: 0x202124, sail: 0xf0e0bd, rope: 0x71553b }
    }]
  }
};

const Y_AXIS = new THREE.Vector3(0, 1, 0);

function material(color, options = {}) {
  return new THREE.MeshStandardMaterial({
    color,
    roughness: options.roughness ?? 0.82,
    metalness: options.metalness ?? 0.02,
    flatShading: options.flatShading ?? false,
    side: options.side ?? THREE.FrontSide,
    vertexColors: options.vertexColors ?? false
  });
}

function meshWithEdges(geometry, fill, edgeColor = 0x172329, threshold = 32) {
  const mesh = new THREE.Mesh(geometry, fill);
  const outline = new THREE.LineSegments(
    new THREE.EdgesGeometry(geometry, threshold),
    new THREE.LineBasicMaterial({ color: edgeColor, transparent: true, opacity: 0.55 })
  );
  outline.name = "ink outline";
  mesh.add(outline);
  return mesh;
}

function cylinderBetween(start, end, radius, fill, radialSegments = 8, endRadius = radius) {
  const direction = new THREE.Vector3().subVectors(end, start);
  const geometry = new THREE.CylinderGeometry(endRadius, radius, direction.length(), radialSegments, 1, false);
  const mesh = new THREE.Mesh(geometry, fill);
  mesh.position.copy(start).add(end).multiplyScalar(0.5);
  mesh.quaternion.setFromUnitVectors(Y_AXIS, direction.clone().normalize());
  return mesh;
}

function tubeAlong(points, radius, fill) {
  const curve = new THREE.CatmullRomCurve3(points, false, "centripetal");
  return new THREE.Mesh(new THREE.TubeGeometry(curve, Math.max(12, points.length * 4), radius, 6, false), fill);
}

function makeLine(points, fill) {
  const geometry = new THREE.BufferGeometry().setFromPoints(points);
  return new THREE.Line(geometry, fill);
}

function colorizeGeometry(geometry, baseColor, strength = 0.045) {
  const position = geometry.getAttribute("position");
  if (!position) return geometry;
  const base = new THREE.Color(baseColor);
  const shifted = new THREE.Color();
  const colors = new Float32Array(position.count * 3);
  for (let index = 0; index < position.count; index += 1) {
    const x = position.getX(index);
    const y = position.getY(index);
    const z = position.getZ(index);
    const grain = Math.sin(x * 3.17 + y * 6.13 + z * 1.73) * strength;
    const verticalShade = THREE.MathUtils.clamp(y * 0.012, -0.025, 0.025);
    shifted.copy(base).offsetHSL(0, 0, grain + verticalShade);
    colors[index * 3] = shifted.r;
    colors[index * 3 + 1] = shifted.g;
    colors[index * 3 + 2] = shifted.b;
  }
  geometry.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  return geometry;
}

function addLineSegments(parent, segments, fill, name) {
  const points = [];
  segments.forEach(([start, end]) => points.push(start, end));
  const lines = new THREE.LineSegments(new THREE.BufferGeometry().setFromPoints(points), fill);
  lines.name = name;
  parent.add(lines);
  return lines;
}

function dimensionsFor(type, variant) {
  const bases = {
    sloop: { length: 8.2, beam: 1.18, depth: 1.08, deck: 0.58, mast: 4.95 },
    brig: { length: 10.4, beam: 1.48, depth: 1.35, deck: 0.76, mast: 6.45 },
    frigate: { length: 12.1, beam: 1.67, depth: 1.55, deck: 0.93, mast: 7.15 },
    galleon: { length: 12.1 * 1.03 * 1.3, beam: 1.67 * 1.35, depth: 1.55 * 1.08 * 1.3, deck: 1.22, mast: 7.15 * 1.25 / 1.04 }
  };
  const base = bases[type];
  return {
    length: base.length * variant.scale.length,
    beam: base.beam * variant.scale.beam,
    depth: base.depth * variant.scale.depth,
    deck: base.deck + (variant.lowProfile ? -0.1 : 0),
    mast: base.mast * (variant.lowProfile ? 0.94 : variant.ornate ? 1.04 : 1)
  };
}

function buildStations(dims, type, variant) {
  const positions = [-0.5, -0.43, -0.29, -0.08, 0.16, 0.34, 0.46, 0.5];
  const widths = [0.68, 0.91, 1, 1.02, 0.98, 0.78, 0.39, 0.035];
  const sheer = [0.36, 0.14, 0.03, 0, 0.03, 0.13, 0.3, 0.49];
  const keelRise = [0.42, 0.14, 0.02, 0, 0.04, 0.19, 0.52, 0.86];
  return positions.map((position, index) => {
    const sternFullness = variant.ornate && index < 2 ? 1.08 : 1;
    const bowSharpness = variant.id === "red-wake" && index > 5 ? 0.8 : 1;
    const typeFullness = (type === "frigate" || type === "galleon") && index < 4 ? 1.04 : 1;
    const deckY = dims.deck + sheer[index] * (type === "frigate" ? 0.88 : 0.65);
    return {
      x: position * dims.length,
      width: dims.beam * widths[index] * sternFullness * bowSharpness * typeFullness,
      deckY,
      keelY: deckY - dims.depth + keelRise[index] * dims.depth
    };
  });
}

function hullGeometry(stations) {
  const positions = [];
  const indices = [];
  const ringSize = 8;
  stations.forEach((station) => {
    const height = station.deckY - station.keelY;
    const ring = [
      [station.width * 0.88, station.deckY],
      [station.width, station.deckY - height * 0.22],
      [station.width * 0.78, station.deckY - height * 0.64],
      [station.width * 0.16, station.keelY + height * 0.03],
      [-station.width * 0.16, station.keelY + height * 0.03],
      [-station.width * 0.78, station.deckY - height * 0.64],
      [-station.width, station.deckY - height * 0.22],
      [-station.width * 0.88, station.deckY]
    ];
    ring.forEach(([z, y]) => positions.push(station.x, y, z));
  });
  for (let stationIndex = 0; stationIndex < stations.length - 1; stationIndex += 1) {
    for (let ringIndex = 0; ringIndex < ringSize; ringIndex += 1) {
      const nextRing = (ringIndex + 1) % ringSize;
      const a = stationIndex * ringSize + ringIndex;
      const b = (stationIndex + 1) * ringSize + ringIndex;
      const c = (stationIndex + 1) * ringSize + nextRing;
      const d = stationIndex * ringSize + nextRing;
      indices.push(a, d, b, b, d, c);
    }
  }
  [0, stations.length - 1].forEach((stationIndex, capIndex) => {
    const station = stations[stationIndex];
    const centerIndex = positions.length / 3;
    positions.push(station.x, (station.deckY + station.keelY) * 0.5, 0);
    for (let ringIndex = 0; ringIndex < ringSize; ringIndex += 1) {
      const a = stationIndex * ringSize + ringIndex;
      const b = stationIndex * ringSize + ((ringIndex + 1) % ringSize);
      if (capIndex === 0) indices.push(centerIndex, a, b);
      else indices.push(centerIndex, b, a);
    }
  });
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return geometry;
}

function deckGeometry(stations) {
  const positions = [];
  const indices = [];
  stations.forEach((station) => {
    const edge = station.width * 0.87;
    positions.push(station.x, station.deckY + 0.025, edge);
    positions.push(station.x, station.deckY + 0.09, 0);
    positions.push(station.x, station.deckY + 0.025, -edge);
  });
  for (let stationIndex = 0; stationIndex < stations.length - 1; stationIndex += 1) {
    for (let strip = 0; strip < 2; strip += 1) {
      const a = stationIndex * 3 + strip;
      const b = (stationIndex + 1) * 3 + strip;
      const c = (stationIndex + 1) * 3 + strip + 1;
      const d = stationIndex * 3 + strip + 1;
      indices.push(a, b, d, b, c, d);
    }
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return geometry;
}

function widthAt(stations, x) {
  for (let index = 0; index < stations.length - 1; index += 1) {
    const left = stations[index];
    const right = stations[index + 1];
    if (x >= left.x && x <= right.x) {
      const t = (x - left.x) / (right.x - left.x);
      return THREE.MathUtils.lerp(left.width, right.width, t);
    }
  }
  return stations[0].width;
}

function deckAt(stations, x) {
  for (let index = 0; index < stations.length - 1; index += 1) {
    const left = stations[index];
    const right = stations[index + 1];
    if (x >= left.x && x <= right.x) {
      const t = (x - left.x) / (right.x - left.x);
      return THREE.MathUtils.lerp(left.deckY, right.deckY, t);
    }
  }
  return stations[0].deckY;
}

function sideWidthAtDepth(station, depthFraction) {
  if (depthFraction <= 0.22) return THREE.MathUtils.lerp(station.width * 0.88, station.width, depthFraction / 0.22);
  if (depthFraction <= 0.64) return THREE.MathUtils.lerp(station.width, station.width * 0.78, (depthFraction - 0.22) / 0.42);
  return THREE.MathUtils.lerp(station.width * 0.78, station.width * 0.16, (depthFraction - 0.64) / 0.36);
}

function addSurfaceDetails(ship, stations, dims, type, variant, materials) {
  const usableStations = stations.slice(0, -1);
  const plankLevels = [0.12, 0.24, 0.36, 0.48, 0.6, 0.72, 0.84];
  [-1, 1].forEach((side) => {
    plankLevels.forEach((depthFraction, index) => {
      const points = usableStations.map((station) => {
        const height = station.deckY - station.keelY;
        return new THREE.Vector3(
          station.x,
          station.deckY - height * depthFraction,
          side * (sideWidthAtDepth(station, depthFraction) + 0.012)
        );
      });
      const seam = tubeAlong(points, index === 0 ? 0.014 : 0.009, index === 0 ? materials.plankBold : materials.plank);
      seam.name = `${side > 0 ? "starboard" : "port"} hull plank seam`;
      ship.add(seam);
    });
  });

  const plankCount = type === "sloop" ? 12 : 16;
  const deckFractions = Array.from({ length: plankCount - 1 }, (_, index) => (index + 1) / plankCount * 2 - 1);
  deckFractions.forEach((fraction) => {
    const points = usableStations.map((station) => new THREE.Vector3(
      station.x,
      station.deckY + 0.096 - Math.abs(fraction) * 0.065,
      station.width * 0.87 * fraction
    ));
    const seam = tubeAlong(points, 0.007, materials.plank);
    seam.name = "deck plank seam";
    ship.add(seam);
  });

  const jointCount = type === "sloop" ? 14 : type === "brig" ? 18 : 22;
  for (let index = 1; index < jointCount; index += 1) {
    const x = THREE.MathUtils.lerp(-dims.length * 0.4, dims.length * 0.4, index / jointCount);
    const fraction = ((index * 5) % plankCount) / plankCount * 2 - 1;
    const width = widthAt(stations, x) * 0.87;
    const z0 = width * fraction;
    const z1 = width * (fraction + 2 / plankCount);
    const y0 = deckAt(stations, x) + 0.096 - Math.abs(fraction) * 0.065;
    const y1 = deckAt(stations, x) + 0.096 - Math.abs(fraction + 2 / plankCount) * 0.065;
    const joint = cylinderBetween(new THREE.Vector3(x, y0, z0), new THREE.Vector3(x, y1, z1), 0.007, materials.plank, 5);
    joint.name = "staggered deck plank butt";
    ship.add(joint);
  }

  const keelPoints = usableStations.map((station) => new THREE.Vector3(station.x, station.keelY + 0.03, 0));
  const keel = tubeAlong(keelPoints, type === "frigate" ? 0.07 : 0.05, variant.id === "nightjar" ? materials.accent : materials.wood);
  keel.name = "reinforced keel";
  ship.add(keel);
}

function makeBarrel(materials, scale = 1) {
  const group = new THREE.Group();
  group.name = "banded cargo barrel";
  const height = 0.44 * scale;
  const radius = 0.18 * scale;
  const body = new THREE.Mesh(new THREE.CylinderGeometry(radius * 0.86, radius * 0.9, height, 10), materials.wood);
  body.position.y = height * 0.5;
  group.add(body);
  [-0.3, 0.3].forEach((fraction) => {
    const band = new THREE.Mesh(new THREE.TorusGeometry(radius * 0.88, 0.018 * scale, 5, 12), materials.iron);
    band.rotation.x = Math.PI * 0.5;
    band.position.y = height * (0.5 + fraction);
    group.add(band);
  });
  return group;
}

function makeCrate(materials, scale = 1) {
  const size = 0.46 * scale;
  const crate = meshWithEdges(new THREE.BoxGeometry(size, size, size), materials.deck, 0x37281d, 8);
  crate.name = "rope-bound cargo crate";
  const bands = new THREE.Group();
  [-0.15, 0.15].forEach((offset) => {
    const band = new THREE.Mesh(new THREE.BoxGeometry(0.025 * scale, size * 1.015, size * 1.025), materials.rope);
    band.position.x = offset * scale;
    bands.add(band);
  });
  crate.add(bands);
  return crate;
}

function makeRopeCoil(materials, scale = 1) {
  const group = new THREE.Group();
  group.name = "coiled running rigging";
  [0.18, 0.125, 0.075].forEach((radius) => {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(radius * scale, 0.018 * scale, 5, 18), materials.rope);
    ring.rotation.x = Math.PI * 0.5;
    group.add(ring);
  });
  return group;
}

function addHelm(ship, stations, dims, type, materials) {
  const x = type === "sloop" ? -dims.length * 0.29 : -dims.length * 0.18;
  const deckY = deckAt(stations, x);
  const radius = type === "frigate" ? 0.31 : 0.25;
  const z = dims.beam * 0.34;
  const wheel = new THREE.Group();
  wheel.name = type === "sloop" ? "carved tiller wheel" : "ship's wheel and pedestal";
  wheel.position.set(x, deckY + radius + 0.2, z);
  const rim = new THREE.Mesh(new THREE.TorusGeometry(radius, 0.028, 6, 20), materials.wood);
  wheel.add(rim);
  const spokes = [];
  for (let index = 0; index < 8; index += 1) {
    const angle = index * Math.PI / 4;
    spokes.push([
      new THREE.Vector3(0, 0, 0.015),
      new THREE.Vector3(Math.cos(angle) * radius * 0.88, Math.sin(angle) * radius * 0.88, 0.015)
    ]);
  }
  addLineSegments(wheel, spokes, materials.riggingBold, "helm spokes");
  const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.055, 0.055, 0.16, 8), materials.accent);
  hub.rotation.x = Math.PI * 0.5;
  wheel.add(hub);
  const pedestal = new THREE.Mesh(new THREE.BoxGeometry(0.13, radius * 1.4, 0.18), materials.wood);
  pedestal.position.y = -radius * 0.72;
  wheel.add(pedestal);
  ship.add(wheel);
}

function addAnchor(ship, stations, dims, side, materials) {
  const x = dims.length * 0.34;
  const width = widthAt(stations, x);
  const centerY = deckAt(stations, x) - 0.34;
  const z = side * (width + 0.045);
  const anchor = new THREE.Group();
  anchor.name = `${side > 0 ? "starboard" : "port"} stocked anchor`;
  anchor.position.set(x, centerY, z);
  const shank = cylinderBetween(new THREE.Vector3(0, -0.32, 0), new THREE.Vector3(0, 0.31, 0), 0.028, materials.iron, 7, 0.022);
  anchor.add(shank);
  anchor.add(cylinderBetween(new THREE.Vector3(-0.24, 0.2, 0), new THREE.Vector3(0.24, 0.2, 0), 0.026, materials.wood, 7));
  anchor.add(cylinderBetween(new THREE.Vector3(0, -0.3, 0), new THREE.Vector3(-0.2, -0.45, 0), 0.03, materials.iron, 7, 0.018));
  anchor.add(cylinderBetween(new THREE.Vector3(0, -0.3, 0), new THREE.Vector3(0.2, -0.45, 0), 0.03, materials.iron, 7, 0.018));
  const ring = new THREE.Mesh(new THREE.TorusGeometry(0.09, 0.018, 5, 14), materials.iron);
  ring.position.y = 0.38;
  anchor.add(ring);
  ship.add(anchor);
}

function addDeckFittings(ship, stations, dims, type, variant, materials) {
  addHelm(ship, stations, dims, type, materials);
  addAnchor(ship, stations, dims, 1, materials);
  addAnchor(ship, stations, dims, -1, materials);

  const propCount = type === "sloop" ? 2 : type === "brig" ? 3 : 4;
  for (let index = 0; index < propCount; index += 1) {
    const x = THREE.MathUtils.lerp(-dims.length * 0.05, dims.length * 0.22, propCount === 1 ? 0.5 : index / (propCount - 1));
    const side = index % 2 === 0 ? -1 : 1;
    const z = side * dims.beam * (0.22 + index * 0.04);
    const prop = index % 3 === 1 ? makeCrate(materials, type === "frigate" ? 0.9 : 0.78) : makeBarrel(materials, type === "frigate" ? 0.92 : 0.78);
    prop.position.set(x, deckAt(stations, x) + 0.11, z);
    prop.rotation.y = index * 0.42;
    ship.add(prop);
  }

  const coilCount = variant.ornate ? 3 : 2;
  for (let index = 0; index < coilCount; index += 1) {
    const x = THREE.MathUtils.lerp(-dims.length * 0.12, dims.length * 0.18, index / Math.max(1, coilCount - 1));
    const coil = makeRopeCoil(materials, 0.72);
    coil.position.set(x, deckAt(stations, x) + 0.13, dims.beam * 0.58 * (index % 2 ? 1 : -1));
    ship.add(coil);
  }

  const bollardCount = type === "sloop" ? 4 : type === "brig" ? 6 : 8;
  for (let index = 0; index < bollardCount; index += 1) {
    const x = THREE.MathUtils.lerp(-dims.length * 0.34, dims.length * 0.34, index / (bollardCount - 1));
    const side = index % 2 === 0 ? -1 : 1;
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.055, 0.18, 7), materials.wood);
    post.position.set(x, deckAt(stations, x) + 0.18, side * widthAt(stations, x) * 0.69);
    post.name = "mooring bollard";
    ship.add(post);
  }
}

function addSideMedallion(ship, stations, x, y, radius, materials, name = "carved hull medallion") {
  const width = widthAt(stations, x);
  [-1, 1].forEach((side) => {
    const disc = new THREE.Mesh(new THREE.CircleGeometry(radius, 10), materials.accent);
    disc.position.set(x, y, side * (width + 0.035));
    disc.rotation.y = side < 0 ? Math.PI : 0;
    disc.name = name;
    ship.add(disc);
    const spokes = [];
    for (let index = 0; index < 8; index += 1) {
      const angle = index * Math.PI / 4;
      spokes.push([
        new THREE.Vector3(x, y, side * (width + 0.045)),
        new THREE.Vector3(x + Math.cos(angle) * radius * 1.35, y + Math.sin(angle) * radius * 1.35, side * (width + 0.045))
      ]);
    }
    addLineSegments(ship, spokes, materials.riggingBold, `${name} rays`);
  });
}

function addRepairPlates(ship, stations, dims, materials, count = 3) {
  const placements = [
    [-0.22, 0.49, 0.08],
    [0.02, 0.61, -0.05],
    [0.23, 0.43, 0.11],
    [-0.05, 0.34, -0.09]
  ];
  [-1, 1].forEach((side) => {
    placements.slice(0, count).forEach(([xFraction, depthFraction, tilt]) => {
      const x = dims.length * xFraction;
      const stationWidth = widthAt(stations, x);
      const y = deckAt(stations, x) - dims.depth * depthFraction;
      const plate = meshWithEdges(new THREE.BoxGeometry(0.48, 0.13, 0.035), materials.deck, 0x30231b, 10);
      plate.position.set(x, y, side * (stationWidth + 0.025));
      plate.rotation.z = tilt;
      plate.name = "nailed hull repair board";
      ship.add(plate);
      [-0.19, 0.19].forEach((offset) => {
        const rivet = new THREE.Mesh(new THREE.SphereGeometry(0.025, 6, 4), materials.iron);
        rivet.position.set(x + offset, y, side * (stationWidth + 0.055));
        ship.add(rivet);
      });
    });
  });
}

function addVariantDetails(ship, stations, dims, type, variant, materials) {
  if (variant.id === "sunfish-runner") {
    const x = dims.length * 0.37;
    addSideMedallion(ship, stations, x, deckAt(stations, x) - 0.25, 0.11, materials, "sunburst bow medallion");
  }
  if (variant.id === "mango-jack" || variant.id === "red-wake") addRepairPlates(ship, stations, dims, materials, variant.id === "red-wake" ? 4 : 3);
  if (variant.id === "nightjar") {
    const hatchX = -dims.length * 0.18;
    const locker = meshWithEdges(new THREE.BoxGeometry(0.72, 0.055, dims.beam * 0.55), materials.hull, 0x0e151c, 12);
    locker.position.set(hatchX, deckAt(stations, hatchX) + 0.12, 0);
    locker.name = "flush smuggler locker";
    ship.add(locker);
    const cutwater = new THREE.Mesh(new THREE.ConeGeometry(0.11, 0.42, 7), materials.accent);
    cutwater.rotation.z = -Math.PI * 0.5;
    cutwater.position.set(dims.length * 0.52, deckAt(stations, dims.length * 0.45) - 0.2, 0);
    cutwater.name = "copper cutwater";
    ship.add(cutwater);
  }
  if (variant.id === "crown-and-compass") {
    const x = -dims.length * 0.43;
    addSideMedallion(ship, stations, x, deckAt(stations, x) + 0.42, 0.16, materials, "compass rose badge");
    const bellX = -dims.length * 0.03;
    const bell = new THREE.Mesh(new THREE.ConeGeometry(0.09, 0.16, 10), materials.accent);
    bell.position.set(bellX, deckAt(stations, bellX) + 0.42, dims.beam * 0.25);
    bell.name = "brass watch bell";
    ship.add(bell);
  }
  if (variant.id === "la-estrella" || variant.id === "santa-brigida") {
    const x = -dims.length * 0.43;
    addSideMedallion(ship, stations, x, deckAt(stations, x) + (type === "frigate" ? 0.62 : 0.48), type === "frigate" ? 0.2 : 0.17, materials, "gilded stern sunburst");
  }
  if (variant.id === "resolute") {
    const x = -dims.length * 0.42;
    const shield = meshWithEdges(new THREE.CylinderGeometry(0.16, 0.2, 0.06, 8), materials.accent, 0x332b20, 20);
    shield.rotation.x = Math.PI * 0.5;
    shield.position.set(x, deckAt(stations, x) + 0.66, dims.beam * 0.86);
    shield.name = "naval stern crest";
    ship.add(shield);
  }
  if (variant.id === "sea-wraith") addRepairPlates(ship, stations, dims, materials, 3);
}

function addShrouds(ship, mastX, baseY, height, halfBeam, materials, scale = 1) {
  [-1, 1].forEach((side) => {
    const top = new THREE.Vector3(mastX, baseY + height * 0.76, side * 0.025);
    const left = new THREE.Vector3(mastX - 0.48 * scale, baseY + 0.08, side * halfBeam * 0.86);
    const center = new THREE.Vector3(mastX, baseY + 0.08, side * halfBeam * 0.9);
    const right = new THREE.Vector3(mastX + 0.48 * scale, baseY + 0.08, side * halfBeam * 0.86);
    addLineSegments(ship, [[top, left], [top, center], [top, right]], materials.riggingBold, "standing shrouds");
    const rungs = [];
    for (let rung = 1; rung <= 14; rung += 1) {
      const t = 0.15 + rung * 0.055;
      rungs.push([
        top.clone().lerp(left, t),
        top.clone().lerp(right, t)
      ]);
    }
    addLineSegments(ship, rungs, materials.riggingFine, "ratlines");
  });
}

function addMastHardware(ship, x, baseY, height, radius, materials, type) {
  const levels = type === "sloop" ? [0.12, 0.72] : [0.12, 0.58, 0.79];
  levels.forEach((fraction) => {
    const band = new THREE.Mesh(new THREE.TorusGeometry(radius * 1.12, 0.017, 5, 12), materials.iron);
    band.rotation.x = Math.PI * 0.5;
    band.position.set(x, baseY + height * fraction, 0);
    band.name = "mast iron band";
    ship.add(band);
  });
  if (type !== "sloop") {
    const platform = meshWithEdges(new THREE.BoxGeometry(0.48, 0.06, 0.78), materials.wood, 0x2e2118, 20);
    platform.position.set(x, baseY + height * 0.61, 0);
    platform.name = "mast fighting top";
    ship.add(platform);
    const topCap = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.08, 0.34), materials.accent);
    topCap.position.set(x, baseY + height * 0.82, 0);
    topCap.name = "topmast cap";
    ship.add(topCap);
  }
}

function addHullDetails(ship, stations, dims, type, variant, materials) {
  const detailedDeckGeometry = colorizeGeometry(deckGeometry(stations), variant.palette.deck, 0.035);
  const deck = meshWithEdges(detailedDeckGeometry, materials.deckSurface, 0x273235, 38);
  deck.name = "cambered deck";
  ship.add(deck);

  [-1, 1].forEach((side) => {
    if (type !== "sloop") {
      const bandLevels = type === "galleon" ? [[0.11, 0.26], [0.41, 0.56]] : type === "frigate" ? [[0.23, 0.46]] : [[0.21, 0.4]];
      bandLevels.forEach(([upper, lower]) => {
        const positions = [];
        const indices = [];
        stations.forEach((station, index) => {
          const height = station.deckY - station.keelY;
          for (const fraction of [upper, lower]) positions.push(station.x, station.deckY - height * fraction, side * (sideWidthAtDepth(station, fraction) + 0.018));
          if (index < stations.length - 1) {
            const a = index * 2;
            if (side > 0) indices.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
            else indices.push(a, a + 2, a + 1, a + 1, a + 2, a + 3);
          }
        });
        const geometry = new THREE.BufferGeometry();
        geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
        geometry.setIndex(indices);
        geometry.computeVertexNormals();
        const band = new THREE.Mesh(geometry, materials.trim);
        band.name = `${side > 0 ? "starboard" : "port"} painted gun deck band`;
        ship.add(band);
      });
    }
    const gunwalePoints = stations.slice(0, -1).map((station) => new THREE.Vector3(station.x, station.deckY + 0.1, side * station.width * 0.9));
    const stripePoints = stations.slice(0, -1).map((station) => {
      const height = station.deckY - station.keelY;
      return new THREE.Vector3(station.x, station.deckY - height * 0.31, side * station.width * 1.002);
    });
    const gunwale = tubeAlong(gunwalePoints, type === "frigate" ? 0.075 : 0.06, materials.accent);
    gunwale.name = `${side > 0 ? "starboard" : "port"} gunwale`;
    ship.add(gunwale);
    const stripe = tubeAlong(stripePoints, type === "frigate" ? 0.085 : 0.065, materials.trim);
    stripe.name = `${side > 0 ? "starboard" : "port"} color stripe`;
    ship.add(stripe);

    const postCount = type === "sloop" ? 13 : type === "brig" ? 17 : 21;
    const railPoints = [];
    for (let index = 0; index < postCount; index += 1) {
      const x = THREE.MathUtils.lerp(-dims.length * 0.4, dims.length * 0.4, index / (postCount - 1));
      const y = deckAt(stations, x);
      const z = side * widthAt(stations, x) * 0.9;
      const post = cylinderBetween(new THREE.Vector3(x, y + 0.08, z), new THREE.Vector3(x, y + 0.37, z), 0.027, materials.accent, 6);
      ship.add(post);
      railPoints.push(new THREE.Vector3(x, y + 0.37, z));
    }
    ship.add(tubeAlong(railPoints, 0.035, materials.accent));
  });

  const bowspritStart = new THREE.Vector3(dims.length * 0.41, deckAt(stations, dims.length * 0.41) + 0.18, 0);
  const bowspritEnd = new THREE.Vector3(dims.length * (type === "sloop" ? 0.7 : 0.66), bowspritStart.y + (type === "sloop" ? 0.42 : 0.55), 0);
  const bowsprit = cylinderBetween(bowspritStart, bowspritEnd, type === "frigate" ? 0.11 : 0.085, materials.wood, 8, 0.035);
  bowsprit.name = "bowsprit";
  ship.add(bowsprit);

  const rudder = meshWithEdges(new THREE.BoxGeometry(type === "sloop" ? 0.42 : 0.5, dims.depth * 0.68, 0.1), materials.trim, 0x182329, 28);
  rudder.position.set(-dims.length * 0.515, -dims.depth * 0.22, 0);
  rudder.rotation.z = -0.08;
  rudder.name = "rudder";
  ship.add(rudder);

  const hatchCount = type === "sloop" ? 1 : 2;
  for (let index = 0; index < hatchCount; index += 1) {
    const x = (index - (hatchCount - 1) * 0.5) * dims.length * 0.18;
    const hatch = meshWithEdges(new THREE.BoxGeometry(type === "frigate" ? 1.05 : 0.82, 0.13, dims.beam * 0.72), materials.wood, 0x2a211b, 20);
    hatch.position.set(x, deckAt(stations, x) + 0.16, 0);
    hatch.name = "grated cargo hatch";
    ship.add(hatch);
    for (let slat = -2; slat <= 2; slat += 1) {
      const bar = new THREE.Mesh(new THREE.BoxGeometry(0.035, 0.025, dims.beam * 0.66), materials.rope);
      bar.position.set(x + slat * 0.13, hatch.position.y + 0.08, 0);
      ship.add(bar);
    }
  }

  const capstanX = dims.length * 0.19;
  const capstanY = deckAt(stations, capstanX);
  const capstan = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.2, 0.38, 8), materials.wood);
  capstan.position.set(capstanX, capstanY + 0.25, 0);
  capstan.name = "capstan";
  ship.add(capstan);

  if (variant.ornate) {
    const figurehead = new THREE.Mesh(new THREE.SphereGeometry(0.18, 10, 8), materials.accent);
    figurehead.scale.set(1.45, 0.8, 0.8);
    figurehead.position.set(dims.length * 0.505, deckAt(stations, dims.length * 0.48) - 0.25, 0);
    figurehead.name = "gilded figurehead";
    ship.add(figurehead);
  }
}

function addCabin(ship, stations, dims, type, variant, materials) {
  if (type === "sloop") return;
  const height = variant.cabin || (type === "frigate" ? 0.9 : 0.62);
  const length = dims.length * (type === "frigate" ? 0.22 : 0.18);
  const x = -dims.length * 0.34;
  const y = deckAt(stations, x);
  const width = widthAt(stations, x) * 1.38;
  const cabin = meshWithEdges(new THREE.BoxGeometry(length, height, width), materials.hull, 0x172026, 24);
  cabin.position.set(x, y + height * 0.52, 0);
  cabin.name = "raised stern gallery";
  ship.add(cabin);

  const roof = meshWithEdges(new THREE.BoxGeometry(length * 1.06, 0.11, width * 1.07), materials.deck, 0x32271d, 28);
  roof.position.set(x, y + height + 0.08, 0);
  ship.add(roof);

  const windowCount = type === "frigate" ? 4 : 3;
  [-1, 1].forEach((side) => {
    for (let index = 0; index < windowCount; index += 1) {
      const window = new THREE.Mesh(new THREE.BoxGeometry(length * 0.12, height * 0.34, 0.035), materials.window);
      window.position.set(x - length * 0.34 + index * (length * 0.68 / (windowCount - 1)), y + height * 0.57, side * (width * 0.505));
      window.name = "stern gallery window";
      ship.add(window);
    }
  });

  const transomWindowCount = type === "frigate" ? 5 : 3;
  for (let index = 0; index < transomWindowCount; index += 1) {
    const transomWindow = new THREE.Mesh(new THREE.BoxGeometry(0.04, height * 0.3, width * 0.11), materials.window);
    transomWindow.position.set(
      x - length * 0.505,
      y + height * 0.57,
      THREE.MathUtils.lerp(-width * 0.34, width * 0.34, transomWindowCount === 1 ? 0.5 : index / (transomWindowCount - 1))
    );
    transomWindow.name = "glazed transom window";
    ship.add(transomWindow);
  }
  const galleryLedge = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.08, width * 1.08), materials.accent);
  galleryLedge.position.set(x - length * 0.54, y + height * 0.25, 0);
  galleryLedge.name = "stern gallery ledge";
  ship.add(galleryLedge);
  const galleryRail = cylinderBetween(
    new THREE.Vector3(x - length * 0.58, y + height * 0.76, -width * 0.52),
    new THREE.Vector3(x - length * 0.58, y + height * 0.76, width * 0.52),
    0.026,
    materials.accent,
    7
  );
  galleryRail.name = "stern balcony rail";
  ship.add(galleryRail);

  const lanternCount = variant.ornate || variant.twinLanterns ? 2 : 1;
  for (let index = 0; index < lanternCount; index += 1) {
    const z = lanternCount === 1 ? 0 : (index === 0 ? -1 : 1) * width * 0.36;
    const lantern = new THREE.Mesh(new THREE.OctahedronGeometry(0.12, 0), materials.accent);
    lantern.position.set(x - length * 0.54, y + height + 0.34, z);
    lantern.name = "stern lantern";
    ship.add(lantern);
  }
}

function addCastles(ship, stations, dims, variant, materials) {
  const sternX = -dims.length * 0.37;
  const sternY = deckAt(stations, -dims.length * 0.34) + variant.cabin + 0.14;
  const sternWidth = widthAt(stations, -dims.length * 0.34) * 1.14;
  const sternLength = dims.length * 0.13;
  const foreX = dims.length * 0.35;
  const foreY = deckAt(stations, foreX);
  const foreWidth = widthAt(stations, foreX) * 1.4;
  const foreLength = dims.length * 0.16;
  for (const [name, x, y, length, width, height] of [
    ["stepped upper sterncastle", sternX, sternY, sternLength, sternWidth, 0.58],
    ["raised forecastle", foreX, foreY, foreLength, foreWidth, 0.62]
  ]) {
    const castle = meshWithEdges(new THREE.BoxGeometry(length, height, width), materials.hull);
    castle.name = name;
    castle.position.set(x, y + height / 2, 0);
    ship.add(castle);
    const top = new THREE.Mesh(new THREE.BoxGeometry(length * 1.03, 0.09, width * 1.03), materials.deck);
    top.name = `${name} deck`;
    top.position.set(x, y + height, 0);
    ship.add(top);
    [-1, 1].forEach((side) => {
      const z = side * width * 0.51;
      const railY = y + height + 0.3;
      const rail = cylinderBetween(new THREE.Vector3(x - length / 2, railY, z), new THREE.Vector3(x + length / 2, railY, z), 0.035, materials.accent);
      rail.name = "castle balustrade";
      ship.add(rail);
      for (let index = 0; index <= 5; index += 1) {
        const postX = x - length / 2 + index * length / 5;
        ship.add(cylinderBetween(new THREE.Vector3(postX, y + height, z), new THREE.Vector3(postX, railY, z), 0.025, materials.accent));
      }
      if (name.includes("stern")) for (let index = 0; index < 3; index += 1) {
        const window = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.25, 0.035), materials.window);
        window.name = "upper sterncastle window";
        window.position.set(x - length * 0.3 + index * length * 0.3, y + height * 0.55, z);
        ship.add(window);
      }
    });
    const forward = x < 0 ? 1 : -1;
    for (let index = 0; index < 5; index += 1) {
      const stepHeight = (index + 1) * height / 5;
      const step = new THREE.Mesh(new THREE.BoxGeometry(0.18, stepHeight, 0.6), materials.deck);
      step.name = "castle stair tread";
      step.position.set(x + forward * (length / 2 + (5 - index) * 0.15), y + stepHeight / 2, 0);
      ship.add(step);
    }
  }
}

function addCannons(ship, stations, dims, type, variant, materials, representative, cannons) {
  const rows = [{ count: representative ? { sloop: 4, brig: 6, frigate: 8, galleon: 8 }[type] : variant.guns, yOffset: type === "galleon" ? -1.03 : type === "frigate" ? -0.62 : -0.43 }];
  if (type === "galleon" || (!representative && variant.upperGuns)) rows.push({ count: variant.upperGuns, yOffset: type === "galleon" ? -0.4 : -0.04 });
  const frameSegments = [];
  rows.forEach((row, rowIndex) => {
    for (let index = 0; index < row.count; index += 1) {
      const x = THREE.MathUtils.lerp(dims.length * (representative ? 0.29 : -0.31), dims.length * (representative ? -0.31 : 0.29), row.count === 1 ? 0.5 : index / (row.count - 1));
      const y = deckAt(stations, x) + row.yOffset;
      const leftIndex = Math.max(0, stations.findIndex((station) => station.x >= x) - 1);
      const left = stations[leftIndex];
      const right = stations[leftIndex + 1];
      const t = (x - left.x) / (right.x - left.x);
      const width = THREE.MathUtils.lerp(
        sideWidthAtDepth(left, (left.deckY - y) / (left.deckY - left.keelY)),
        sideWidthAtDepth(right, (right.deckY - y) / (right.deckY - right.keelY)), t
      );
      [-1, 1].forEach((side) => {
        const portSize = representative ? 0.32 : rowIndex === 0 ? 0.24 : 0.2;
        const port = new THREE.Mesh(new THREE.BoxGeometry(portSize, portSize, 0.05), materials.port);
        port.position.set(x, y, side * width * 1.002);
        port.name = `${side > 0 ? "starboard" : "port"} gun port`;
        ship.add(port);
        const halfFrame = portSize * 0.63;
        const frameZ = side * (width + 0.035);
        frameSegments.push(
          [new THREE.Vector3(x - halfFrame, y - halfFrame, frameZ), new THREE.Vector3(x + halfFrame, y - halfFrame, frameZ)],
          [new THREE.Vector3(x + halfFrame, y - halfFrame, frameZ), new THREE.Vector3(x + halfFrame, y + halfFrame, frameZ)],
          [new THREE.Vector3(x + halfFrame, y + halfFrame, frameZ), new THREE.Vector3(x - halfFrame, y + halfFrame, frameZ)],
          [new THREE.Vector3(x - halfFrame, y + halfFrame, frameZ), new THREE.Vector3(x - halfFrame, y - halfFrame, frameZ)]
        );
        const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.07, rowIndex === 0 ? 0.42 : 0.34, 12), materials.iron);
        barrel.rotation.x = side * Math.PI * 0.5;
        barrel.position.set(x, y, side * (width + (rowIndex === 0 ? 0.18 : 0.14)));
        barrel.name = "cannon barrel";
        ship.add(barrel);
        {
          const sideName = side > 0 ? "starboard" : "port";
          // Empty transforms survive batching; cylinder tips are +/- half its length.
          const muzzle = new THREE.Object3D();
          muzzle.name = `Muzzle_${sideName}_${rowIndex * rows[0].count + index}`;
          muzzle.position.set(x, y, barrel.position.z + side * barrel.geometry.parameters.height / 2);
          muzzle.rotation.y = side < 0 ? Math.PI : 0;
          ship.add(muzzle);
          cannons.push({ side: sideName, barrel, muzzle });
          const opening = new THREE.Mesh(new THREE.CircleGeometry(0.037, 10), materials.port);
          opening.position.copy(muzzle.position);
          opening.position.z += side * 0.003;
          opening.rotation.y = side < 0 ? Math.PI : 0;
          opening.name = "dark cannon bore";
          ship.add(opening);
          const collar = new THREE.Mesh(new THREE.TorusGeometry(0.06, 0.018, 4, 8), materials.accent);
          collar.position.copy(muzzle.position);
          collar.position.z -= side * 0.025;
          collar.name = "brass muzzle collar";
          ship.add(collar);
          const sill = new THREE.Mesh(new THREE.BoxGeometry(0.39, 0.075, 0.09), materials.accent);
          sill.position.set(x, y - 0.18, side * (width + 0.055));
          sill.name = "reinforced gunport sill";
          ship.add(sill);
        }
        const lid = new THREE.Mesh(new THREE.BoxGeometry(portSize * 0.9, portSize * 0.5, 0.035), materials.hull);
        lid.position.set(x, y + portSize * 0.75, side * (width + 0.02));
        lid.rotation.x = side * 0.25;
        lid.name = "raised gunport lid";
        ship.add(lid);
      });
    }
  });
  addLineSegments(ship, frameSegments, materials.portFrame, "framed gun battery");
  if (representative) {
    [-1, 1].forEach((side) => {
      const points = stations.filter((station) => station.x >= -dims.length * 0.38 && station.x <= dims.length * 0.36)
        .map((station) => new THREE.Vector3(station.x, deckAt(stations, station.x) - 0.15, side * (widthAt(stations, station.x) + 0.055)));
      const wale = tubeAlong(points, 0.055, materials.accent);
      wale.name = "brass battery wale";
      ship.add(wale);
    });
  }
}

function sailGrid(width, height, billow, fill, edgeFill) {
  const cols = 10;
  const rows = 8;
  const positions = [];
  const indices = [];
  for (let row = 0; row <= rows; row += 1) {
    const v = row / rows;
    for (let col = 0; col <= cols; col += 1) {
      const u = col / cols;
      const taper = 0.88 + v * 0.12;
      positions.push(
        billow * Math.sin(Math.PI * u) * Math.sin(Math.PI * v),
        (v - 0.5) * height,
        (u - 0.5) * width * taper
      );
    }
  }
  for (let row = 0; row < rows; row += 1) {
    for (let col = 0; col < cols; col += 1) {
      const a = row * (cols + 1) + col;
      const b = a + 1;
      const c = a + cols + 2;
      const d = a + cols + 1;
      indices.push(a, b, d, b, c, d);
    }
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  const sail = new THREE.Mesh(geometry, fill);
  sail.add(new THREE.LineSegments(new THREE.EdgesGeometry(geometry, 16), edgeFill));
  const pointAt = (u, v, offset = 0.012) => new THREE.Vector3(
    billow * Math.sin(Math.PI * u) * Math.sin(Math.PI * v) + offset,
    (v - 0.5) * height,
    (u - 0.5) * width * (0.88 + v * 0.12)
  );
  const seamSegments = [];
  for (const offset of [-0.012, 0.012]) {
    [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9].forEach((u) => {
      for (let row = 0; row < rows; row += 1) seamSegments.push([pointAt(u, row / rows, offset), pointAt(u, (row + 1) / rows, offset)]);
    });
    [0.25, 0.5, 0.75].forEach((v) => {
      for (let col = 0; col < cols; col += 1) seamSegments.push([pointAt(col / cols, v, offset), pointAt((col + 1) / cols, v, offset)]);
    });
  }
  addLineSegments(sail, seamSegments, edgeFill, "stitched sail panels");
  const reefSegments = [];
  for (const offset of [-0.016, 0.016]) {
    [0.14, 0.3, 0.46, 0.62, 0.78, 0.9].forEach((u) => {
      const center = pointAt(u, 0.34, offset);
      reefSegments.push([
        center.clone().add(new THREE.Vector3(0, -0.065, -0.018)),
        center.clone().add(new THREE.Vector3(0, 0.045, 0.018))
      ]);
    });
  }
  addLineSegments(sail, reefSegments, edgeFill, "reef points");
  return sail;
}

function flatSail(points, fill, edgeFill) {
  const shape = new THREE.Shape();
  shape.moveTo(points[0][0], points[0][1]);
  points.slice(1).forEach(([x, y]) => shape.lineTo(x, y));
  shape.closePath();
  const geometry = new THREE.ExtrudeGeometry(shape, { depth: 0.045, bevelEnabled: false, steps: 1 });
  geometry.translate(0, 0, -0.0225);
  const sail = new THREE.Mesh(geometry, fill);
  sail.add(new THREE.LineSegments(new THREE.EdgesGeometry(geometry, 14), edgeFill));
  const seams = [];
  const minX = Math.min(...points.map(([x]) => x));
  const maxX = Math.max(...points.map(([x]) => x));
  for (let panel = 1; panel < 10; panel += 1) {
    const x = THREE.MathUtils.lerp(minX, maxX, panel / 10);
    const crossings = [];
    points.forEach(([ax, ay], index) => {
      const [bx, by] = points[(index + 1) % points.length];
      if ((ax <= x && bx > x) || (bx <= x && ax > x)) crossings.push(ay + (by - ay) * (x - ax) / (bx - ax));
    });
    if (crossings.length !== 2) continue;
    const low = Math.min(...crossings);
    const high = Math.max(...crossings);
    for (const z of [-0.026, 0.026]) {
      seams.push([new THREE.Vector3(x, low, z), new THREE.Vector3(x, high, z)]);
      for (let y = low + 0.12; y < high - 0.12; y += 0.18) {
        seams.push([new THREE.Vector3(x - 0.015, y - 0.012, z), new THREE.Vector3(x + 0.015, y + 0.012, z)]);
      }
    }
  }
  addLineSegments(sail, seams, edgeFill, "hand-stitched canvas strips");
  return sail;
}

function addMast(ship, x, baseY, height, materials, radius = 0.095) {
  const mast = cylinderBetween(
    new THREE.Vector3(x, baseY - 0.05, 0),
    new THREE.Vector3(x, baseY + height, 0),
    radius,
    materials.wood,
    8,
    radius * 0.55
  );
  mast.name = "mast";
  ship.add(mast);
  return mast;
}

function addSloopRig(ship, stations, dims, variant, materials, sailPivots) {
  const mastX = dims.length * 0.07;
  const baseY = deckAt(stations, mastX);
  addMast(ship, mastX, baseY, dims.mast, materials, 0.09);
  addMastHardware(ship, mastX, baseY, dims.mast, 0.09, materials, "sloop");
  addShrouds(ship, mastX, baseY, dims.mast, dims.beam, materials, 1.05);
  const pivot = new THREE.Group();
  pivot.name = "wind-trimming gaff rig";
  pivot.position.set(mastX, baseY, 0);
  pivot.userData.trimFactor = 1;
  ship.add(pivot);
  sailPivots.push(pivot);

  const mainWidth = dims.length * 0.4;
  const mainHeight = dims.mast * (variant.lowProfile ? 0.66 : 0.72);
  const main = flatSail([
    [0.08, 0.72],
    [-mainWidth, 0.78],
    [-mainWidth * 0.73, mainHeight],
    [0.05, mainHeight * 0.78]
  ], materials.sail, materials.sailEdge);
  main.name = "gaff mainsail";
  pivot.add(main);

  const jib = flatSail([
    [0.08, mainHeight * 0.86],
    [dims.length * 0.46, 0.78],
    [dims.length * 0.08, 0.83]
  ], materials.sail, materials.sailEdge);
  jib.name = "jib";
  pivot.add(jib);

  const boom = cylinderBetween(new THREE.Vector3(0, 0.73, 0), new THREE.Vector3(-mainWidth * 1.05, 0.73, 0), 0.045, materials.wood, 8, 0.025);
  boom.name = "boom";
  pivot.add(boom);
  const gaff = cylinderBetween(new THREE.Vector3(0, mainHeight * 0.76, 0), new THREE.Vector3(-mainWidth * 0.77, mainHeight * 1.02, 0), 0.04, materials.wood, 8, 0.022);
  gaff.name = "gaff";
  pivot.add(gaff);

  const mainSeamBlueprint = [
    [new THREE.Vector3(-mainWidth * 0.22, 0.78, 0), new THREE.Vector3(-mainWidth * 0.14, mainHeight * 0.83, 0)],
    [new THREE.Vector3(-mainWidth * 0.48, 0.78, 0), new THREE.Vector3(-mainWidth * 0.4, mainHeight * 0.9, 0)],
    [new THREE.Vector3(-mainWidth * 0.72, 0.78, 0), new THREE.Vector3(-mainWidth * 0.63, mainHeight * 0.96, 0)],
    [new THREE.Vector3(-mainWidth * 0.79, mainHeight * 0.4, 0), new THREE.Vector3(-mainWidth * 0.04, mainHeight * 0.4, 0)]
  ];
  const mainSeamSegments = [];
  [-0.027, 0.027].forEach((z) => mainSeamBlueprint.forEach(([start, end]) => {
    mainSeamSegments.push([
      new THREE.Vector3(start.x, start.y, z),
      new THREE.Vector3(end.x, end.y, z)
    ]);
  }));
  addLineSegments(main, mainSeamSegments, materials.sailEdge, "stitched gaff sail panels");
  const jibSeamSegments = [];
  [-0.027, 0.027].forEach((z) => {
    jibSeamSegments.push([
      new THREE.Vector3(dims.length * 0.08, mainHeight * 0.83, z),
      new THREE.Vector3(dims.length * 0.3, 0.88, z)
    ]);
  });
  addLineSegments(jib, jibSeamSegments, materials.sailEdge, "stitched jib panels");
  const reefSegments = [];
  for (let index = 1; index <= 6; index += 1) {
    const x = -mainWidth * (0.12 + index * 0.105);
    reefSegments.push([
      new THREE.Vector3(x, mainHeight * 0.39 - 0.045, 0.03),
      new THREE.Vector3(x, mainHeight * 0.39 + 0.045, 0.03)
    ]);
  }
  addLineSegments(main, reefSegments, materials.sailEdge, "gaff sail reef points");

  const mastTop = new THREE.Vector3(mastX, baseY + dims.mast, 0);
  const rope = materials.rigging;
  ship.add(makeLine([mastTop, new THREE.Vector3(dims.length * 0.48, deckAt(stations, dims.length * 0.45), 0)], rope));
  ship.add(makeLine([mastTop, new THREE.Vector3(-dims.length * 0.44, deckAt(stations, -dims.length * 0.42), 0)], rope));
}

function addSquareRig(ship, stations, dims, type, variant, materials, sailPivots) {
  const mastFractions = type === "brig" ? [-0.17, 0.2] : [-0.31, -0.02, 0.29];
  const heightFactors = type === "brig" ? [1, 0.92] : [0.82, 1, 0.91];
  mastFractions.forEach((fraction, mastIndex) => {
    const x = dims.length * fraction;
    const baseY = deckAt(stations, x);
    const height = dims.mast * heightFactors[mastIndex];
    const mastRadius = type === "frigate" ? 0.115 : 0.1;
    addMast(ship, x, baseY, height, materials, mastRadius);
    addMastHardware(ship, x, baseY, height, mastRadius, materials, type);
    addShrouds(ship, x, baseY, height, widthAt(stations, x), materials, type === "frigate" ? 1.18 : 1.08);
    const pivot = new THREE.Group();
    pivot.name = `wind-trimming mast ${mastIndex + 1}`;
    pivot.position.set(x, baseY, 0);
    pivot.userData.trimFactor = mastIndex === 0 ? 0.92 : 1;
    ship.add(pivot);
    sailPivots.push(pivot);

    if (type === "galleon" && mastIndex === 0) {
      pivot.name = "wind-trimming lateen mizzen";
      pivot.userData.trimFactor = 0.65;
      const aft = -dims.length * 0.14;
      const fore = dims.length * 0.13;
      const lateen = flatSail([[aft, height * 0.74], [fore, height * 0.89], [aft * 0.65, height * 0.24]], materials.sail, materials.sailEdge);
      lateen.name = "triangular lateen mizzen sail";
      pivot.add(lateen);
      const yard = cylinderBetween(new THREE.Vector3(aft * 1.06, height * 0.73, 0), new THREE.Vector3(fore * 1.08, height * 0.9, 0), 0.055, materials.wood);
      yard.name = "sloping lateen yard";
      pivot.add(yard);
      addLineSegments(lateen, [[new THREE.Vector3(aft * 0.76, height * 0.75, 0.027), new THREE.Vector3(aft * 0.57, height * 0.35, 0.027)], [new THREE.Vector3(0, height * 0.82, 0.027), new THREE.Vector3(aft * 0.48, height * 0.47, 0.027)]], materials.sailEdge, "lateen sail seams");
      return;
    }
    const sailCount = type === "frigate" || type === "galleon" ? (mastIndex === 1 ? 3 : 2) : 2;
    for (let sailIndex = 0; sailIndex < sailCount; sailIndex += 1) {
      const normalized = sailIndex / Math.max(1, sailCount - 1);
      const widthBase = type === "frigate" || type === "galleon" ? dims.beam * 2.65 : dims.beam * 2.5;
      const width = widthBase * (1 - normalized * 0.34) * (mastIndex === 0 ? 0.88 : mastIndex === mastFractions.length - 1 ? 0.92 : 1);
      const sailHeight = height * (sailCount === 3 ? 0.2 : 0.245) * (1 - normalized * 0.15);
      const centerY = height * (sailCount === 3 ? 0.43 + sailIndex * 0.22 : 0.44 + sailIndex * 0.27);
      const sail = sailGrid(width, sailHeight, 0.16 + mastIndex * 0.02, materials.sail, materials.sailEdge);
      sail.position.y = centerY;
      sail.name = `square sail ${mastIndex + 1}.${sailIndex + 1}`;
      pivot.add(sail);
      const yardY = centerY + sailHeight * 0.52;
      const yard = cylinderBetween(new THREE.Vector3(0, yardY, -width * 0.58), new THREE.Vector3(0, yardY, width * 0.58), 0.04, materials.wood, 8, 0.025);
      yard.name = "yard";
      pivot.add(yard);
      const footrope = tubeAlong([
        new THREE.Vector3(0.08, yardY, -width * 0.55),
        new THREE.Vector3(0.1, yardY - 0.22, -width * 0.27),
        new THREE.Vector3(0.08, yardY - 0.13, 0),
        new THREE.Vector3(0.1, yardY - 0.22, width * 0.27),
        new THREE.Vector3(0.08, yardY, width * 0.55)
      ], 0.009, materials.rope);
      footrope.name = "yard footrope";
      pivot.add(footrope);
      const liftY = Math.min(height * 0.94, yardY + height * 0.14);
      pivot.add(makeLine([
        new THREE.Vector3(0, liftY, 0),
        new THREE.Vector3(0, yardY, -width * 0.56)
      ], materials.rigging));
      pivot.add(makeLine([
        new THREE.Vector3(0, liftY, 0),
        new THREE.Vector3(0, yardY, width * 0.56)
      ], materials.rigging));
    }
  });

  const foreX = dims.length * mastFractions[mastFractions.length - 1];
  const foreBase = deckAt(stations, foreX);
  const jibPivot = sailPivots[sailPivots.length - 1];
  const jib = flatSail([
    [0.08, dims.mast * 0.62],
    [dims.length * (0.49 - mastFractions[mastFractions.length - 1]), 0.78],
    [dims.length * 0.05, 0.84]
  ], materials.sail, materials.sailEdge);
  jib.name = "fore staysail";
  jibPivot.add(jib);

  if (type === "brig") {
    const outerJib = flatSail([
      [0.1, dims.mast * 0.5],
      [dims.length * 0.3, 0.95],
      [dims.length * 0.08, 1.02]
    ], materials.sail, materials.sailEdge);
    outerJib.position.set(dims.length * 0.08, 0.05, 0);
    outerJib.name = "outer jib";
    jibPivot.add(outerJib);

    const mainX = dims.length * mastFractions[0];
    const mainBase = deckAt(stations, mainX);
    const spankerPivot = new THREE.Group();
    spankerPivot.position.set(mainX, mainBase, 0);
    spankerPivot.name = "wind-trimming brig spanker";
    spankerPivot.userData.trimFactor = 0.62;
    const spankerWidth = dims.length * 0.22;
    const spankerHeight = dims.mast * 0.47;
    const spanker = flatSail([
      [0.03, dims.mast * 0.17],
      [-spankerWidth, dims.mast * 0.18],
      [-spankerWidth * 0.76, spankerHeight],
      [0.02, spankerHeight * 0.88]
    ], materials.sail, materials.sailEdge);
    spanker.name = "aft gaff spanker";
    spankerPivot.add(spanker);
    spankerPivot.add(cylinderBetween(
      new THREE.Vector3(0, dims.mast * 0.165, 0),
      new THREE.Vector3(-spankerWidth * 1.06, dims.mast * 0.165, 0),
      0.036,
      materials.wood,
      7,
      0.022
    ));
    spankerPivot.add(cylinderBetween(
      new THREE.Vector3(0, spankerHeight * 0.86, 0),
      new THREE.Vector3(-spankerWidth * 0.78, spankerHeight * 1.02, 0),
      0.032,
      materials.wood,
      7,
      0.02
    ));
    ship.add(spankerPivot);
    sailPivots.push(spankerPivot);
  }

  const mastPoints = mastFractions.map((fraction, index) => {
    const x = dims.length * fraction;
    return new THREE.Vector3(x, deckAt(stations, x) + dims.mast * heightFactors[index], 0);
  });
  const rigTargets = [
    new THREE.Vector3(-dims.length * 0.44, deckAt(stations, -dims.length * 0.43) + 0.05, 0),
    ...mastPoints,
    new THREE.Vector3(dims.length * 0.48, deckAt(stations, dims.length * 0.46) + 0.05, 0)
  ];
  for (let index = 0; index < rigTargets.length - 1; index += 1) {
    ship.add(makeLine([rigTargets[index], rigTargets[index + 1]], materials.rigging));
  }
  mastPoints.forEach((top, index) => {
    const mastX = dims.length * mastFractions[index];
    [-1, 1].forEach((side) => {
      ship.add(makeLine([top, new THREE.Vector3(mastX - 0.45, deckAt(stations, mastX) + 0.05, side * dims.beam * 0.88)], materials.rigging));
    });
  });
  void foreBase;
}

function addFlag(ship, stations, dims, type, materials) {
  const x = type === "sloop" ? dims.length * 0.07 : type === "brig" ? -dims.length * 0.17 : -dims.length * 0.02;
  const y = deckAt(stations, x) + dims.mast * (type === "frigate" ? 1.02 : 1.01);
  const shape = new THREE.Shape();
  shape.moveTo(0, 0);
  shape.lineTo(-0.75, -0.18);
  shape.lineTo(-0.58, -0.38);
  shape.lineTo(0, -0.46);
  shape.closePath();
  const flag = new THREE.Mesh(new THREE.ShapeGeometry(shape), materials.trim);
  flag.material.side = THREE.DoubleSide;
  flag.position.set(x, y, 0.02);
  flag.name = "house pennant";
  ship.add(flag);
}

function addCraftsmanship(ship, stations, dims, type, materials, cannons) {
  // Bake only the new fixed fittings together. Rig pivots and muzzle transforms
  // remain independent, and hundreds of small fittings cost a handful of draws.
  const parts = new Map();
  const add = (geometry, fill, position, rotation = new THREE.Euler()) => {
    geometry.applyMatrix4(new THREE.Matrix4().compose(
      new THREE.Vector3(...position), new THREE.Quaternion().setFromEuler(rotation), new THREE.Vector3(1, 1, 1)
    ));
    if (!parts.has(fill)) parts.set(fill, []);
    parts.get(fill).push(geometry);
  };
  const box = (size, at, fill = materials.accent, rotation) => add(new THREE.BoxGeometry(...size), fill, at, rotation);
  const rod = (from, to, radius, fill = materials.iron, segments = 6) => {
    const piece = cylinderBetween(new THREE.Vector3(...from), new THREE.Vector3(...to), radius, fill, segments);
    piece.updateMatrix();
    piece.geometry.applyMatrix4(piece.matrix);
    if (!parts.has(fill)) parts.set(fill, []);
    parts.get(fill).push(piece.geometry);
  };
  const ring = (at, radius, thickness, fill = materials.iron, rotation = new THREE.Euler()) => {
    add(new THREE.TorusGeometry(radius, thickness, 4, 12), fill, at, rotation);
  };
  const rope = (points, radius = 0.014) => {
    const piece = tubeAlong(points.map((point) => new THREE.Vector3(...point)), radius, materials.rope);
    if (!parts.has(materials.rope)) parts.set(materials.rope, []);
    parts.get(materials.rope).push(piece.geometry);
  };

  // Offset butt joints follow the hull's actual loft, with paired treenails.
  const shellPoint = (x, depth, side) => {
    const index = Math.max(0, stations.findIndex((station) => station.x >= x) - 1);
    const left = stations[index];
    const right = stations[index + 1];
    const t = (x - left.x) / (right.x - left.x);
    const y = THREE.MathUtils.lerp(left.deckY - (left.deckY - left.keelY) * depth, right.deckY - (right.deckY - right.keelY) * depth, t);
    const z = THREE.MathUtils.lerp(sideWidthAtDepth(left, depth), sideWidthAtDepth(right, depth), t);
    return [x, y, side * (z + 0.018)];
  };
  for (const side of [-1, 1]) {
    for (let course = 0; course < 6; course += 1) {
      const top = 0.12 + course * 0.12;
      for (let joint = 0; joint < 5; joint += 1) {
        const x = dims.length * (-0.37 + joint * 0.15 + (course % 2) * 0.065);
        rod(shellPoint(x, top + 0.015, side), shellPoint(x, top + 0.105, side), 0.005, materials.plank, 4);
        for (const dx of [-0.035, 0.035]) {
          add(new THREE.SphereGeometry(0.014, 5, 3), materials.wood, shellPoint(x + dx, top + 0.06, side));
        }
      }
    }
  }

  // Gunport hinges, trunnions, carriage cheeks and iron trucks. These never
  // extend ahead of the original muzzle, so smoke starts at the same opening.
  for (const { barrel, side: sideName } of cannons) {
    const side = sideName === "starboard" ? 1 : -1;
    const { x, y, z } = barrel.position;
    const innerZ = z - side * 0.2;
    rod([x - 0.14, y, innerZ], [x + 0.14, y, innerZ], 0.035);
    for (const offset of [-0.12, 0.12]) {
      box([0.055, 0.13, 0.29], [x + offset, y - 0.09, innerZ], materials.wood);
      for (const truck of [-0.095, 0.095]) {
        add(new THREE.CylinderGeometry(0.05, 0.05, 0.032, 8), materials.iron,
          [x + offset * 1.15, y - 0.17, innerZ + truck], new THREE.Euler(0, 0, Math.PI / 2));
      }
      box([0.026, 0.14, 0.02], [x + offset * 0.78, y + 0.24, innerZ + side * 0.04], materials.iron);
      rod([x + offset * 0.78 - 0.025, y + 0.17, innerZ + side * 0.055],
        [x + offset * 0.78 + 0.025, y + 0.17, innerZ + side * 0.055], 0.017);
    }
    ring([x, y, z - side * 0.06], 0.063, 0.01);
    ring([x, y + 0.28, innerZ + side * 0.06], 0.03, 0.008);
  }

  // Frames and cross-mullions sit on the actual window surface, including
  // transom glazing and the Galleon's upper gallery.
  ship.children.filter((part) => /window$/.test(part.name)).forEach((window) => {
    const { width: w, height: h, depth: d } = window.geometry.parameters;
    const { x, y, z } = window.position;
    const transom = w < d;
    const breadth = transom ? d : w;
    const outward = transom ? -1 : Math.sign(z);
    const at = (u, v) => transom ? [x - w / 2 - 0.018, y + v, z + u] : [x + u, y + v, z + outward * (d / 2 + 0.018)];
    for (const u of [-breadth / 2, 0, breadth / 2]) {
      box(transom ? [0.035, h + 0.04, 0.025] : [0.025, h + 0.04, 0.035], at(u, 0));
    }
    for (const v of [-h / 2, 0, h / 2]) {
      box(transom ? [0.035, 0.024, breadth + 0.045] : [breadth + 0.045, 0.024, 0.035], at(0, v));
    }
  });

  for (const cabin of ship.children.filter((part) => /raised stern gallery|stepped upper sterncastle|raised forecastle/.test(part.name) && !part.name.endsWith("deck"))) {
    const { width: length, height, depth: width } = cabin.geometry.parameters;
    const { x, y } = cabin.position;
    for (const side of [-1, 1]) {
      for (let row = 1; row < 5; row += 1) {
        box([length, 0.012, 0.018], [x, y - height / 2 + row * height / 5, side * (width / 2 + 0.011)], materials.plank);
      }
      for (const end of [-1, 1]) box([0.055, height, 0.045], [x + end * length * 0.47, y, side * width * 0.51]);
      box([length * 1.02, 0.07, 0.06], [x, y + height * 0.4, side * width * 0.51]);
    }
    const front = x > 0 ? -1 : 1;
    const doorX = x + front * (length / 2 + 0.025);
    const doorH = Math.min(0.65, height * 0.82);
    const doorY = y - height / 2 + doorH / 2;
    box([0.035, doorH, 0.38], [doorX, doorY, 0], materials.wood);
    for (const z of [-0.21, 0.21]) box([0.055, doorH + 0.05, 0.038], [doorX + front * 0.025, doorY, z]);
    box([0.055, 0.04, 0.46], [doorX, doorY + doorH / 2, 0]);
    for (const v of [-0.25, 0.25]) box([0.045, 0.025, 0.35], [doorX + front * 0.03, doorY + doorH * v, 0], materials.iron);
    ring([doorX + front * 0.055, doorY, 0.12], 0.035, 0.01, materials.accent, new THREE.Euler(0, Math.PI / 2, 0));
  }

  for (const hatch of ship.children.filter((part) => part.name === "grated cargo hatch")) {
    const { width, depth } = hatch.geometry.parameters;
    const { x, y, z } = hatch.position;
    box([width * 0.87, 0.012, depth * 0.88], [x, y + 0.071, z], materials.port);
    for (let bar = -4; bar <= 4; bar += 1) {
      box([0.022, 0.022, depth * 0.9], [x + bar * width * 0.1, y + 0.092, z], materials.deck);
      box([width * 0.9, 0.022, 0.025], [x, y + 0.094, z + bar * depth * 0.1], materials.deck);
    }
    for (const side of [-1, 1]) ring([x, y + 0.1, z + side * depth * 0.48], 0.05, 0.012, materials.iron, new THREE.Euler(Math.PI / 2, 0, 0));
  }

  const capstan = ship.getObjectByName("capstan");
  const { x: capX, y: capY } = capstan.position;
  ring([capX, capY + 0.15, 0], 0.17, 0.025, materials.iron, new THREE.Euler(Math.PI / 2, 0, 0));
  for (let index = 0; index < 4; index += 1) {
    const angle = index * Math.PI / 2;
    rod([capX + Math.cos(angle) * 0.12, capY + 0.13, Math.sin(angle) * 0.12],
      [capX + Math.cos(angle) * 0.47, capY + 0.13, Math.sin(angle) * 0.47], 0.025, materials.wood);
  }
  for (const post of ship.children.filter((part) => part.name === "mooring bollard")) {
    const { x, y, z } = post.position;
    box([0.14, 0.025, 0.14], [x, y - 0.078, z], materials.iron);
    rod([x - 0.11, y + 0.04, z], [x + 0.11, y + 0.04, z], 0.024, materials.wood);
  }
  for (const cargo of ship.children.filter((part) => part.name === "banded cargo barrel")) {
    const body = cargo.children[0];
    const { height, radiusTop } = body.geometry.parameters;
    const { x, y, z } = cargo.position;
    for (let stave = 0; stave < 12; stave += 1) {
      const angle = stave * Math.PI / 6;
      rod([x + Math.cos(angle) * radiusTop, y + height * 0.08, z + Math.sin(angle) * radiusTop],
        [x + Math.cos(angle) * radiusTop, y + height * 0.98, z + Math.sin(angle) * radiusTop], 0.005, materials.plank, 4);
    }
    box([radiusTop * 1.7, 0.012, 0.018], [x, y + height + 0.005, z], materials.plank);
    add(new THREE.CylinderGeometry(0.022, 0.022, 0.012, 6), materials.wood, [x, y + height + 0.01, z + radiusTop * 0.4]);
  }

  // The standing rig has paired deadeyes and lanyards at each shroud foot,
  // belaying pins, and rope bindings; all are fixed to their supporting mast.
  const masts = ship.children.filter((part) => part.name === "mast");
  for (const mast of masts) {
    const mastX = mast.position.x;
    const baseY = deckAt(stations, mastX);
    const halfBeam = widthAt(stations, mastX);
    for (const side of [-1, 1]) {
      for (let index = -1; index <= 1; index += 1) {
        const x = mastX + index * 0.48 * (type === "sloop" ? 1.05 : type === "frigate" ? 1.18 : 1.08);
        const z = side * halfBeam * (index === 0 ? 0.9 : 0.86);
        for (const level of [0.12, 0.3]) {
          add(new THREE.CylinderGeometry(0.06, 0.06, 0.042, 8), materials.wood, [x, baseY + level, z], new THREE.Euler(Math.PI / 2, 0, 0));
          for (const hole of [-0.025, 0.025]) add(new THREE.CircleGeometry(0.009, 5), materials.port,
            [x + hole, baseY + level, z + side * 0.025], new THREE.Euler(0, side < 0 ? Math.PI : 0, 0));
        }
        for (const offset of [-0.035, 0, 0.035]) rod([x + offset, baseY + 0.14, z + side * 0.025], [x + offset, baseY + 0.28, z + side * 0.025], 0.008, materials.rope, 4);
      }
      box([0.64, 0.06, 0.15], [mastX, baseY + 0.24, side * halfBeam * 0.67], materials.wood);
      for (let pin = -2; pin <= 2; pin += 1) {
        rod([mastX + pin * 0.12, baseY + 0.15, side * halfBeam * 0.67], [mastX + pin * 0.12, baseY + 0.34, side * halfBeam * 0.67], 0.017, materials.wood);
      }
    }
    for (const fraction of [0.06, 0.09, 0.3, 0.48]) {
      ring([mastX, baseY + mast.geometry.parameters.height * fraction, 0], 0.09, 0.017, materials.rope, new THREE.Euler(Math.PI / 2, 0, 0));
    }
  }

  // Roof guardrails and planking make the elevated decks convincing from above.
  for (const cabin of ship.children.filter((part) => part.name === "raised stern gallery")) {
    const { width: length, height, depth: width } = cabin.geometry.parameters;
    const { x, y } = cabin.position;
    const roofY = y + height / 2 + 0.13;
    for (let plank = -5; plank <= 5; plank += 1) box([length, 0.009, 0.009], [x, roofY, plank * width / 11], materials.plank);
    for (const side of [-1, 1]) {
      const z = side * width * 0.52;
      rod([x - length / 2, roofY + 0.24, z], [x + length / 2, roofY + 0.24, z], 0.026, materials.accent);
      for (let post = 0; post <= 8; post += 1) {
        const px = x - length / 2 + post * length / 8;
        rod([px, roofY, z], [px, roofY + 0.24, z], 0.017, materials.accent);
      }
    }
    const stairsZ = -width * 0.3;
    const deckY = y - height / 2;
    const rise = roofY - deckY;
    const run = 0.86;
    const startX = x + length / 2 + run;
    for (let step = 0; step < 8; step += 1) {
      box([0.14, 0.045, 0.42], [startX - step * run / 8, deckY + (step + 1) * rise / 8, stairsZ], materials.deck);
    }
    for (const side of [-1, 1]) {
      const z = stairsZ + side * 0.23;
      rod([startX + 0.03, deckY + 0.08, z], [x + length / 2, roofY, z], 0.035, materials.wood);
      rod([startX + 0.03, deckY + 0.35, z], [x + length / 2, roofY + 0.27, z], 0.02, materials.accent);
      rod([startX + 0.03, deckY + 0.08, z], [startX + 0.03, deckY + 0.35, z], 0.02, materials.accent);
    }
  }
  for (const deck of ship.children.filter((part) => /^(raised forecastle|stepped upper sterncastle) deck$/.test(part.name))) {
    const { width, height, depth } = deck.geometry.parameters;
    const { x, y, z } = deck.position;
    for (let plank = -6; plank <= 6; plank += 1) {
      box([width * 0.98, 0.008, 0.008], [x, y + height / 2 + 0.004, z + plank * depth / 14], materials.plank);
    }
  }
  for (const lantern of ship.children.filter((part) => part.name === "stern lantern")) {
    const { x, y, z } = lantern.position;
    lantern.geometry.dispose();
    lantern.geometry = new THREE.BoxGeometry(0.14, 0.19, 0.14);
    lantern.material = materials.window;
    for (const dx of [-0.08, 0.08]) for (const dz of [-0.08, 0.08]) box([0.018, 0.22, 0.018], [x + dx, y, z + dz], materials.iron);
    box([0.2, 0.028, 0.2], [x, y - 0.12, z]);
    add(new THREE.ConeGeometry(0.14, 0.12, 4), materials.accent, [x, y + 0.155, z], new THREE.Euler(0, Math.PI / 4, 0));
    rod([x + 0.16, y - 0.3, z], [x, y - 0.3, z], 0.022);
    rod([x, y - 0.3, z], [x, y - 0.13, z], 0.022);
  }
  const bowsprit = ship.getObjectByName("bowsprit");
  const end = new THREE.Vector3(0, bowsprit.geometry.parameters.height * 0.43, 0).applyQuaternion(bowsprit.quaternion).add(bowsprit.position);
  rope([[dims.length * 0.46, deckAt(stations, dims.length * 0.46) - 0.38, 0], [dims.length * 0.55, end.y - 0.32, 0], end.toArray()], 0.018);
  for (const side of [-1, 1]) {
    const x = dims.length * 0.34;
    const y = deckAt(stations, x);
    const z = side * (widthAt(stations, x) + 0.045);
    rod([x - 0.13, y + 0.16, side * widthAt(stations, x) * 0.7], [x - 0.13, y + 0.16, z], 0.045, materials.wood);
    rope([[x - 0.13, y + 0.16, z], [x - 0.1, y - 0.02, z + side * 0.03], [x, y + 0.04, z]], 0.018);
    for (const angle of [-0.7, 0.7]) {
      box([0.12, 0.12, 0.035], [x + Math.sign(angle) * 0.19, y - 0.74, z], materials.iron, new THREE.Euler(0, 0, angle));
    }
  }

  const details = new THREE.Group();
  details.name = "joined ship craftsmanship";
  for (const [fill, geometries] of parts) {
    const combined = new THREE.Mesh(mergeGeometries(geometries, false), fill);
    combined.name = `${Object.keys(materials).find((key) => materials[key] === fill)} fittings`;
    details.add(combined);
    geometries.forEach((geometry) => geometry.dispose());
  }
  ship.add(details);
}

export function createShipModel(type, variantIndex = 0) {
  const classData = vesselCatalog[type];
  if (!classData) throw new Error(`Unknown vessel class: ${type}`);
  const variant = classData.ships[variantIndex];
  if (!variant) throw new Error(`Unknown ${type} variant: ${variantIndex}`);
  const dims = dimensionsFor(type, variant);
  const stations = buildStations(dims, type, variant);
  const palette = variant.palette;
  const plankColor = new THREE.Color(palette.rope).multiplyScalar(0.72).getHex();
  const materials = {
    hull: material(palette.hull, { roughness: 0.78, flatShading: true }),
    hullSurface: material(0xffffff, { roughness: 0.78, flatShading: true, vertexColors: true }),
    deck: material(palette.deck, { roughness: 0.86 }),
    deckSurface: material(0xffffff, { roughness: 0.86, vertexColors: true }),
    trim: material(palette.trim, { roughness: 0.72 }),
    accent: material(palette.accent, { roughness: 0.48, metalness: 0.18 }),
    iron: material(palette.iron, { roughness: 0.5, metalness: 0.38 }),
    port: material(0x11191d, { roughness: 0.95 }),
    wood: material(0x684628, { roughness: 0.85 }),
    rope: material(palette.rope, { roughness: 1 }),
    plank: material(plankColor, { roughness: 1 }),
    plankBold: material(palette.rope, { roughness: 0.95 }),
    sail: material(palette.sail, { roughness: 0.94, side: THREE.DoubleSide }),
    sailEdge: new THREE.LineBasicMaterial({ color: type === "sloop" ? palette.trim : palette.rope, transparent: true, opacity: 0.8 }),
    rigging: new THREE.LineBasicMaterial({ color: palette.rope, transparent: true, opacity: 0.72 }),
    riggingBold: new THREE.LineBasicMaterial({ color: palette.rope, transparent: true, opacity: 0.88 }),
    riggingFine: new THREE.LineBasicMaterial({ color: palette.rope, transparent: true, opacity: 0.58 }),
    portFrame: new THREE.LineBasicMaterial({ color: palette.accent, transparent: true, opacity: 0.95 }),
    window: material(0x78b7b4, { roughness: 0.3, metalness: 0.05 })
  };

  const ship = new THREE.Group();
  ship.name = `${variant.name} — procedural ${type}`;
  ship.userData = {
    title: variant.name,
    vesselClass: type,
    variant: variant.id,
    coordinateSystem: "+x bow, +y up, +z starboard",
    generatedFor: "Tortuga"
  };
  const detailedHullGeometry = colorizeGeometry(hullGeometry(stations), palette.hull, variant.id === "sea-wraith" ? 0.07 : 0.045);
  const hull = meshWithEdges(detailedHullGeometry, materials.hullSurface, 0x101a20, 26);
  hull.name = "lofted three-dimensional hull";
  ship.add(hull);
  addHullDetails(ship, stations, dims, type, variant, materials);
  addSurfaceDetails(ship, stations, dims, type, variant, materials);
  addCabin(ship, stations, dims, type, variant, materials);
  addDeckFittings(ship, stations, dims, type, variant, materials);
  const cannons = [];
  addCannons(ship, stations, dims, type, variant, materials, variantIndex === 0, cannons);
  if (type === "galleon") addCastles(ship, stations, dims, variant, materials);
  if (variantIndex === 0) {
    // Broader contrasting coamings keep the existing cargo hatch readable at game scale.
    ship.children.filter((child) => child.name === "grated cargo hatch").forEach((hatch) => {
      const rim = new THREE.Mesh(new THREE.BoxGeometry(type === "frigate" ? 1.18 : 0.95, 0.08, dims.beam * 0.8), materials.accent);
      rim.position.copy(hatch.position);
      rim.position.y -= 0.065;
      rim.name = "brass hatch coaming";
      ship.add(rim);
    });
  }
  addVariantDetails(ship, stations, dims, type, variant, materials);
  const sailPivots = [];
  if (type === "sloop") addSloopRig(ship, stations, dims, variant, materials, sailPivots);
  else addSquareRig(ship, stations, dims, type, variant, materials, sailPivots);
  addFlag(ship, stations, dims, type, materials);
  addCraftsmanship(ship, stations, dims, type, materials, cannons);

  if (variant.patched) {
    sailPivots.forEach((pivot, index) => {
      const foreAndAft = type === "sloop" || pivot.name.includes("spanker");
      const patch = new THREE.Mesh(new THREE.PlaneGeometry(0.38, 0.3), materials.trim);
      patch.material.side = THREE.DoubleSide;
      patch.position.set(foreAndAft ? -0.9 : 0.03, dims.mast * (0.42 + index * 0.02), foreAndAft ? 0.05 : dims.beam * 0.3);
      patch.rotation.y = foreAndAft ? 0 : Math.PI * 0.5;
      patch.name = "sail repair patch";
      pivot.add(patch);
    });
  }

  const usedMaterials = new Set();
  ship.traverse((part) => { if (part.material) usedMaterials.add(part.material); });
  Object.values(materials).forEach((fill) => { if (!usedMaterials.has(fill)) fill.dispose(); });
  ship.updateMatrixWorld(true);
  const bounds = new THREE.Box3().setFromObject(ship);
  return { object: ship, sailPivots, cannons, bounds, dimensions: dims, variant, fitHeight: classData.fitHeight };
}

export function disposeShip(object) {
  const geometries = new Set();
  const materials = new Set();
  object.traverse((child) => {
    if (child.geometry) geometries.add(child.geometry);
    if (Array.isArray(child.material)) child.material.forEach((item) => materials.add(item));
    else if (child.material) materials.add(child.material);
  });
  geometries.forEach((geometry) => geometry.dispose());
  materials.forEach((fill) => fill.dispose());
}
