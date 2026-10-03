import * as THREE from "three";

// Project the largest ship's heading into the current camera orientation.
// All classes share this world scale; inspection zoom stays independent.
export function shipFrame(bounds, headingDegrees, aspect, cameraQuaternion) {
  const heading = new THREE.Matrix4().makeRotationY(THREE.MathUtils.degToRad(headingDegrees));
  const inverseView = cameraQuaternion.clone().invert();
  const projected = new THREE.Box3();
  for (const x of [bounds.min.x, bounds.max.x]) {
    for (const y of [bounds.min.y, bounds.max.y]) {
      for (const z of [bounds.min.z, bounds.max.z]) {
        projected.expandByPoint(new THREE.Vector3(x, y, z).applyMatrix4(heading).applyQuaternion(inverseView));
      }
    }
  }
  const size = projected.getSize(new THREE.Vector3());
  return { halfHeight: Math.max(size.y, size.x / aspect) * 1.15 / 2 };
}
