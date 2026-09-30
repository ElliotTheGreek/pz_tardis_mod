"""Every object inside the TARDIS: the one list the art pipeline works from.

INTERIOR.md is the prose; this is the data. Each entry says what the object
is, how it gets made, how big it is, which ways it faces and what the game
should make of it.

kind
  model   a Gemini concept, turned into a mesh by fal (TRELLIS), rendered into
          tiles by tools/isorender.py from each facing
  flat    a Gemini picture laid on a wall face, like the scanner -- anything
          that is a picture on a wall needs no depth

size, in squares and world units (a storey is 2.449)
  w  along the wall it backs onto      d  out from that wall      h  height
  For something free-standing (a stool, a table), w and d are just its size.

facings
  "WN"    backs onto a west or a north wall -- the walls the camera sees, as
          vanilla's beds and wardrobes do
  "WNES"  all four, for things that turn (chairs, counters, tables)
  "1"     looks the same every way (the console, a globe, a plant)

use: what the tile definitions say (tools/gen_tardis_pack.py) and what the
runtime does with it (TARDIS_Build.lua): container type, bed, seat, stove,
water, light.

**New pieces go at the end of the list.** The furniture sheet numbers its
tiles in this list's order, and a tile's number is its sprite name in every
save that has one standing.
"""

STYLE = (
    "Product render of a single piece of furniture from inside the TARDIS in "
    "Doctor Who, in the style of its real console rooms and interiors: warm "
    "ivory roundel panels, polished brass and copper fittings, dark walnut "
    "wood, deep TARDIS-blue accents, small soft amber lights. Clean geometric "
    "design with square flat edges, crisp straight bevels and flat panels. "
    "Front view, seen straight on and slightly from above, the whole object "
    "in frame and centred, isolated on a plain flat light-grey background, "
    "soft even studio lighting, no cast shadow, no floor. No text, no "
    "numbers, no logos, no people. "
)

FLAT_STYLE = (
    "A perfectly flat, front-on, evenly lit image, orthographic, no "
    "perspective, no wall around it, no shadow, no people, no text, no "
    "numbers, no logos; the object fills the whole image edge to edge. "
)


def m(name, area, prompt, w, d, h, facings="WN", use=None, **fit):
    """`fit` passes render options through: stretch=True, yaw=degrees
    (tools/gen_tardis_furniture.py, place)."""
    return dict(name=name, area=area, kind="model", prompt=STYLE + prompt,
                w=w, d=d, h=h, facings=facings, use=use or {}, **fit)


def flat(name, area, prompt, u=(0.15, 0.85), v=(0.15, 0.6), use=None, split=None, round=False):
    """A picture on a wall. `split` = (k, n): this tile shows the k-th of n
    vertical slices of the concept, for a picture wider than one wall section."""
    return dict(name=name, area=area, kind="flat", prompt=FLAT_STYLE + prompt, u=u, v=v,
                use=use or {}, split=split, round=round)


OBJECTS = [
    # --- the console room -----------------------------------------------------
    m("console", "console", "The TARDIS control console: a hexagonal console "
      "desk on a square-edged plinth, six sloping control panels crowded with "
      "brass levers, switches, dials and small glowing buttons, and rising "
      "from its centre a tall glass time rotor column with glowing blue-white "
      "crystal rods inside and a brass collar at top and bottom.",
      2, 2, 2.449, facings="1", use={"container": "crate", "hold": True}),
    m("hold_locker", "console", "A tall storage cabinet: dark walnut carcass "
      "with square edges, two ivory doors each with three circular roundel "
      "recesses, polished brass hinges and handles, a thin amber light strip "
      "along the top.", 1, 1, 2.0, use={"container": "crate", "hold": True}),
    m("sonic_case", "console", "A waist-high display cabinet: a square walnut "
      "plinth with a glass box on top, lit from inside, holding three sonic "
      "screwdrivers (slim silver and brass wands with a glowing blue tip) laid "
      "on dark blue velvet.", 1, 1, 1.1, use={"container": "displaycase"}),
    m("wingback_chair", "console", "A leather wingback armchair with square "
      "edges and a tall flat back, deep oxblood leather, rows of brass studs, "
      "short square walnut legs.", 1, 1, 1.2, facings="WNES", use={"seat": True}),
    m("chesterfield", "console", "A two-seat Chesterfield sofa with a flat "
      "square back and square arms, buttoned oxblood leather, brass studs, "
      "short walnut legs.", 2, 1, 0.9, facings="WNES", use={"seat": True}),
    m("side_table", "console", "A small square walnut side table with a brass "
      "rim and a squat brass reading lamp with a green glass shade on it.",
      1, 1, 0.95, facings="1"),
    m("hat_stand", "console", "A tall walnut coat and hat stand with brass "
      "hooks on a square base, a long multicoloured striped scarf and a brown "
      "tweed coat hanging from it and a fez on top.", 1, 1, 1.9, facings="1"),
    m("bookcase", "library", "A tall square-edged walnut bookcase with five "
      "shelves full of old leather-bound books in reds, browns and blues, a "
      "brass rail along the top shelf.", 1, 1, 2.1, use={"container": "shelves"}),

    # --- the armoury ------------------------------------------------------------
    m("gun_cabinet", "armoury", "A tall walnut gun cabinet with square edges "
      "and two glass doors, behind them a rack of rifles and shotguns standing "
      "upright and a shelf of pistols, polished brass lock and hinges.",
      1, 1, 2.0, use={"container": "locker"}),
    m("steamer_trunk", "armoury", "A heavy square campaign trunk: dark "
      "blue-painted wood bound with polished brass corner plates and straps, "
      "a brass hasp and two side handles.", 1, 1, 0.8, facings="WNES",
      use={"container": "crate"}),

    # --- the galley -------------------------------------------------------------
    m("kitchen_counter", "galley", "A square-edged kitchen base cabinet: ivory "
      "painted doors with flat square panels, a thick walnut worktop, small "
      "brass knobs.", 2, 1, 0.95, facings="WNES", use={"container": "counter"}),
    m("kitchen_sink", "galley", "A square-edged kitchen base cabinet with a "
      "deep white ceramic butler sink set into its walnut worktop and a tall "
      "brass swan-neck tap; ivory painted doors below.", 1, 1, 0.95,
      facings="WNES", use={"container": "counter", "water": True}),
    m("kitchen_range", "galley", "A Victorian kitchen range cooker: square "
      "cream enamel body, a black cast-iron hob with four burners on top, two "
      "oven doors with brass handles, a brass rail along the front.",
      1, 1, 0.95, facings="WNES", use={"stove": True}),
    m("fridge", "galley", "A tall square-edged retro refrigerator in cream "
      "enamel with a chrome lever handle and a thin brass trim line.", 1, 1, 2.0,
      use={"container": "fridge"}),
    m("dining_table", "galley", "A long rectangular dining table in dark "
      "walnut with square legs and a brass inlay line round the top.",
      2, 1, 0.78, facings="WNES"),
    m("dining_chair", "galley", "A dining chair with a tall square back of "
      "walnut slats, a deep blue upholstered seat, square legs.", 1, 1, 1.0,
      facings="WNES", use={"seat": True}),
    m("pantry_dresser", "galley", "A tall walnut kitchen dresser: a cupboard "
      "base with ivory doors, open shelves above holding rows of glass jars, "
      "tins and plates.", 1, 1, 2.0, use={"container": "shelves"}),

    # --- quarters ---------------------------------------------------------------
    m("bed_double", "quarters", "A double bed with a square polished brass "
      "frame, headboard of straight brass bars, white sheets, a deep blue "
      "quilt folded back, two white pillows.", 2, 2, 1.2, use={"bed": "goodBed"}),
    m("bed_single", "quarters", "A single bed with a square walnut frame and "
      "headboard, white sheets, a deep blue quilt, one white pillow.",
      1, 2, 1.0, use={"bed": "goodBed"}, stretch=True),
    m("nightstand", "quarters", "A small square walnut bedside cabinet with "
      "one drawer, a brass knob and a small brass candle lamp on top.",
      1, 1, 0.75, use={"container": "sidetable"}),
    m("wardrobe", "quarters", "A tall square-edged walnut wardrobe with two "
      "flat panelled doors and brass handles, a straight cornice on top.",
      1, 1, 2.1, use={"container": "wardrobe"}),
    m("writing_desk", "quarters", "A walnut writing desk with square legs, a "
      "green leather top, a small row of drawers, an inkwell, a brass lamp "
      "and a pile of old books on it.", 2, 1, 0.95, use={"container": "desk"}),
    m("bathtub", "quarters", "A deep white cast-iron roll-top bathtub with "
      "polished brass claw feet and tall brass taps.", 2, 1, 0.75,
      use={"water": True}),
    m("wash_basin", "quarters", "A white ceramic pedestal wash basin with "
      "brass taps and a square brass-framed mirror above it.", 1, 1, 1.6,
      use={"water": True}),
    m("toilet", "quarters", "A Victorian toilet: white porcelain bowl with a "
      "walnut seat, a walnut high-level cistern on the wall above with a long "
      "brass pipe and a pull chain.", 1, 1, 1.9),
    m("clothes_rail", "quarters", "A long free-standing brass clothes rail "
      "crowded with hanging costumes: long coats, a tweed jacket, a frock "
      "coat, cricket jumper, and a very long multicoloured striped scarf.",
      2, 1, 1.9, facings="WNES", use={"container": "wardrobe"}),
    m("spiral_stair", "quarters", "A wrought iron and brass spiral staircase "
      "with square treads winding up around a central brass pole.",
      1, 1, 2.449, facings="1"),

    # --- stores and infirmary ------------------------------------------------------
    m("store_shelf", "stores", "A square-edged gunmetal steel shelving unit "
      "with brass corner brackets, four shelves loaded with boxes, tins, rope "
      "and tools.", 1, 1, 2.0, use={"container": "shelves"}),
    m("workbench", "stores", "A heavy engineer's workbench: thick steel top on "
      "square legs, a vice at one end, a pegboard back panel hung with brass "
      "tools and gauges, drawers underneath.", 2, 1, 1.6, use={"container": "counter"}),
    m("tool_locker", "stores", "A tall square gunmetal steel locker with a "
      "brass vented door, a brass handle and a small round porthole.",
      1, 1, 2.0, use={"container": "locker"}),
    m("medical_cabinet", "stores", "A tall white enamel medical cabinet with "
      "glass doors, glass shelves of brown and blue bottles, bandages and "
      "instruments, brass handles.", 1, 1, 2.0, use={"container": "medicine"}),
    m("sickbay_bed", "stores", "An infirmary bed: square white-enamel steel "
      "frame, crisp white sheets and pillow, a folded blue blanket, a small "
      "brass scanner lamp arm over the head.", 1, 2, 1.3, use={"bed": "goodBed"},
      stretch=True),

    # --- the library ------------------------------------------------------------------
    m("globe", "library", "An antique celestial globe of the stars in a "
      "polished brass meridian ring on a square walnut stand.", 1, 1, 1.2,
      facings="1"),
    m("telescope", "library", "A long polished brass telescope on a tall "
      "walnut tripod, pointing up at an angle.", 1, 1, 1.9, facings="1"),
    m("gramophone", "library", "A square walnut gramophone cabinet with a "
      "turntable on top and a large flared brass horn, record sleeves in a "
      "rack underneath.", 1, 1, 1.5, use={"container": "shelves"}),

    # --- the gardens ------------------------------------------------------------------
    m("potted_fern", "garden", "A large leafy green fern in a square ivory "
      "ceramic planter with a brass band.", 1, 1, 1.3, facings="1"),
    m("potting_bench", "garden", "A walnut potting bench with square legs, a "
      "slatted shelf underneath holding clay pots, seed trays and a brass "
      "watering can on top.", 2, 1, 1.0, use={"container": "counter"}),
    m("seed_cabinet", "garden", "A tall walnut apothecary cabinet made of a "
      "grid of many small square drawers, each with a small brass label frame "
      "and brass pull.", 1, 1, 2.0, use={"container": "shelves"}),
    m("water_trough", "garden", "A long rectangular galvanised steel water "
      "trough on square walnut legs, full of clear water, a brass tap at one "
      "end.", 2, 1, 0.7, use={"water": True}),
    m("garden_bench", "garden", "A garden bench of straight walnut slats with "
      "a square back and square cast-brass arms and legs.", 2, 1, 0.95,
      facings="WNES", use={"seat": True}),

    # --- pictures on walls --------------------------------------------------------------
    flat("scanner", "console", "The TARDIS scanner screen: a square-edged "
         "rectangular monitor in a thick polished brass frame with four small "
         "rivets, the screen showing a swirling blue and orange time vortex.",
         u=(0.1, 0.9), v=(0.2, 0.5)),
    flat("main_doors_l", "console", "The inside of the police box doors "
         "(tools: main_doors_concept.jpg), left half.",
         u=(0.02, 0.98), v=(0.03, 1.0), split=(0, 2), use={"doors": True}),
    flat("main_doors_r", "console", "The inside of the police box doors "
         "(tools: main_doors_concept.jpg), right half.",
         u=(0.02, 0.98), v=(0.03, 1.0), split=(1, 2), use={"doors": True}),
    flat("roundel_light", "any", "A single circular wall light: a flat ivory "
         "roundel dish with a glowing warm white frosted-glass disc in its "
         "centre and a slim polished brass ring round it, square ivory mount.",
         u=(0.3, 0.7), v=(0.22, 0.45), use={"light": True}),
    flat("painting_gallifrey", "any", "A painting in a square-edged gilded "
         "frame: an orange-red world with silver-leafed trees under two suns, "
         "a glittering domed city in a glass dome on the horizon, painterly.",
         v=(0.18, 0.5)),
    flat("wall_clock", "any", "A circular wall clock of polished brass: "
         "several concentric rings engraved with abstract circle-and-dot "
         "glyphs, three ornate hands, no numbers.", u=(0.3, 0.7), v=(0.2, 0.42),
         round=True),
    flat("grow_lamp", "garden", "A long slim wall-mounted grow lamp panel in "
         "a brass frame, glowing soft pink-violet.", u=(0.1, 0.9), v=(0.2, 0.33),
         use={"light": True}),
]


def by_name():
    return {o["name"]: o for o in OBJECTS}


def concept_name(o):
    """Which concept image a piece is drawn from (the doors share one)."""
    if o["name"].startswith("main_doors"):
        return "main_doors"
    return o["name"]


if __name__ == "__main__":
    from collections import Counter
    print(len(OBJECTS), "objects;", dict(Counter(o["kind"] for o in OBJECTS)))
    for o in OBJECTS:
        print("%-20s %-10s %-6s %s" % (o["name"], o["area"], o["kind"],
              ("%sx%sx%s %s" % (o.get("w"), o.get("d"), o.get("h"), o.get("facings")))
              if o["kind"] != "flat" else ""))
