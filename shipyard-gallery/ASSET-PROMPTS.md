# Tortuga ship concept prompt set

Generation mode: built-in image generator. Use case: `stylized-concept`.

The generated PNGs are retained as painted concept references. The interactive gallery itself now uses the procedural 3D models in `dist/ship-models.js`: lofted two-sided hulls, cambered decks, fittings, cannons, masts, yards, and wind-trimming sails. Each model can be exported from the gallery as a binary glTF (`.glb`) asset.

## Shared hull specification

> Create one original late-17th-century **[VESSEL TYPE]** hull as a transparent 2D strategy-game sprite. Show the complete ship in a consistent low-elevated starboard broadside view from a fixed camera approximately 30 degrees above horizontal, with some deck visible, bow pointing right/east, and stern left/west. Center it on a wide 2:1 canvas with generous transparent padding. Use a polished, cartoonish painterly nautical-game aesthetic, hand-painted texture, a chunky readable silhouette, and crisp edges that remain clear at small size. Include detailed deck planking, cannon ports and guns appropriate to the class, hatches, capstan, rope accents, aged metal fittings, bowsprit, stern details, and **[MAST COUNT] complete bare mast(s)** with restrained rigging. Preserve genuine alpha transparency. Absolutely no sail cloth, furled sails, people, water, wake, foam, scenery, cast shadow, text, logo, watermark, frame, or cropped parts. Keep camera angle, scale, and proportions cohesive across all three variants in the class.

Variant briefs used with that specification:

### Sloop — one mast

- **Sunfish Runner:** lively merchant-runner; honey-oak deck and hull, deep navy rails, tasteful brass; clean and quick.
- **Mango Jack:** scrappy privateer; weathered sea-green paint, coral-red trim, blackened iron, patched but sturdy deck.
- **Nightjar:** stealthy smuggler; deep indigo and blue-black timber, aged copper trim, restrained verdigris, discreet fittings.

### Brig — two masts

- **Crown & Compass:** disciplined naval brig; warm walnut, royal-blue bands, restrained antique gilt.
- **Red Wake:** aggressive corsair; dark mahogany, deep crimson rails, charcoal iron, small aged-brass accents.
- **La Estrella:** ornate Caribbean trader; pale honey teak, turquoise bands, elegant warm-gold carving.

### Frigate — three masts

- **Resolute:** imposing navy frigate; blackened oak, warm cream details, muted gold, paired broadside gunport rows.
- **Santa Brígida:** ornate Spanish frigate; rich chestnut, vermilion paint, aged gilding, carved stern decoration.
- **Sea Wraith:** hard-used pirate-hunter; charcoal timber, faded seafoam paint, tarnished brass, controlled salt weathering.

## Shared sail-overlay specification

> Create exactly one isolated late-17th-century **[RIG TYPE]** sail-and-yard assembly as a reusable transparent side-view game-sprite overlay matching the hulls' low 30-degree-elevated broadside camera. Center the vertical mast pivot on a square canvas where possible and keep the mast axis upright so the asset can use CSS `rotateY` to trim with the wind. Use warm ivory woven canvas, readable stitched panels and reinforced seams, restrained ochre weathering, dark aged wood, and small natural-rope ties. Match the hull set's polished cartoonish painterly style and keep the silhouette readable at small size. Preserve genuine alpha transparency and generous clear padding. No hull, deck, water, wake, scenery, shadow, text, insignia, logo, frame, cropping, extra detached sails, flags, or people.

Rig briefs used with that specification:

- **Sloop:** elongated fore-and-aft gaff/lateen sail, slightly full and curved, narrow red-ochre reinforced edge. The generated mast axis is at 58.65% of canvas width and is used as the runtime transform origin.
- **Brig:** broad square-rig canvas on a dark wooden yard, subtle panel seams and mild edge weathering.
- **Frigate:** substantial square-rig canvas with multiple stitched rectangular panels and a compact centered pivot collar.
