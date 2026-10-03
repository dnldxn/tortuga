import * as THREE from "three";

export const SMOKE_LIFETIME = 4;
export const FIRE_COOLDOWN = 1;
export const PARTICLES_PER_CANNON = 3;
export const SMOKE_POOL_LIMIT = 480;

// A tiny procedural alpha map keeps smoke soft without a downloaded texture.
function smokeTexture() {
  const size = 64;
  const pixels = new Uint8Array(size * size * 4);
  for (let y = 0; y < size; y += 1) for (let x = 0; x < size; x += 1) {
    const u = (x + 0.5) / size * 2 - 1;
    const v = (y + 0.5) / size * 2 - 1;
    const radius = Math.hypot(u, v);
    const offset = (y * size + x) * 4;
    pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = 255;
    pixels[offset + 3] = Math.round(Math.max(0, 1 - radius) ** 2 * 255);
  }
  const texture = new THREE.DataTexture(pixels, size, size);
  texture.needsUpdate = true;
  texture.magFilter = texture.minFilter = THREE.LinearFilter;
  return texture;
}

export class CannonSmoke {
  constructor() {
    this.object = new THREE.Group();
    this.object.name = "cannon smoke effects";
    this.texture = smokeTexture();
    this.particles = [];
    this.lastFire = -Infinity;
  }

  get activeCount() { return this.particles.filter((particle) => particle.sprite.visible).length; }

  fire(cannons, now) {
    this.update(now);
    if (now - this.lastFire < FIRE_COOLDOWN) return false;
    this.lastFire = now;
    for (const { muzzle } of cannons) {
      muzzle.updateWorldMatrix(true, false);
      const origin = muzzle.getWorldPosition(new THREE.Vector3());
      const direction = new THREE.Vector3(0, 0, 1).transformDirection(muzzle.matrixWorld);
      for (let puff = 0; puff < PARTICLES_PER_CANNON; puff += 1) {
        let particle = this.particles.find((item) => !item.sprite.visible);
        if (!particle && this.particles.length < SMOKE_POOL_LIMIT) {
          const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.texture, color: 0xffffff, transparent: true, depthWrite: false, opacity: 0 }));
          sprite.name = "soft white cannon smoke";
          this.object.add(sprite);
          particle = { sprite, origin: new THREE.Vector3(), velocity: new THREE.Vector3(), born: now, puff };
          this.particles.push(particle);
        }
        if (!particle) continue;
        particle.born = now;
        particle.puff = puff;
        particle.origin.copy(origin);
        particle.velocity.copy(direction).multiplyScalar(0.45 + puff * 0.17);
        particle.velocity.y += 0.24 + puff * 0.09;
        particle.velocity.x += (puff - 1) * 0.09;
        particle.sprite.visible = true;
        particle.sprite.position.copy(origin);
        particle.sprite.scale.setScalar(0.22 + puff * 0.07);
        particle.sprite.material.opacity = 0.7;
      }
    }
    return true;
  }

  update(now) {
    for (const particle of this.particles) {
      if (!particle.sprite.visible) continue;
      const age = Math.max(0, now - particle.born);
      if (age >= SMOKE_LIFETIME) {
        particle.sprite.visible = false;
        particle.sprite.material.opacity = 0;
        continue;
      }
      particle.sprite.position.copy(particle.origin).addScaledVector(particle.velocity, age);
      particle.sprite.scale.setScalar(0.22 + particle.puff * 0.07 + age * 0.55);
      particle.sprite.material.opacity = 0.7 * (1 - age / SMOKE_LIFETIME) ** 1.4;
    }
  }

  clear() {
    this.lastFire = -Infinity;
    for (const { sprite } of this.particles) { sprite.visible = false; sprite.material.opacity = 0; }
  }

  dispose() {
    this.clear();
    this.particles.forEach(({ sprite }) => sprite.material.dispose());
    this.particles.length = 0;
    this.object.clear();
    this.object.removeFromParent();
    this.texture.dispose();
  }
}
