import 'dart:math';
import 'package:flutter/painting.dart';

String generateThemeName(Color accent) {
  int bestIdx = 0;
  int bestDist = 0x7fffffff;
  final r = accent.red, g = accent.green, b = accent.blue;
  for (int i = 0; i < _colors.length; i++) {
    final c = _colors[i];
    final dr = r - c.r;
    final dg = g - c.g;
    final db = b - c.b;
    final rMean = (r + c.r) >> 1;
    final dist =
        (((512 + rMean) * dr * dr) >> 8) + (4 * dg * dg) + (((767 - rMean) * db * db) >> 8);
    if (dist < bestDist) {
      bestDist = dist;
      bestIdx = i;
    }
  }
  final colorName = _colors[bestIdx].name;
  final rng = Random();
  if (rng.nextBool()) {
    final adj = _adjectives[rng.nextInt(_adjectives.length)];
    return '$adj $colorName';
  } else {
    final noun = _nouns[rng.nextInt(_nouns.length)];
    return '$colorName $noun';
  }
}

class _ColorEntry {
  final String name;
  final int r, g, b;
  const _ColorEntry(this.name, this.r, this.g, this.b);
}

const _colors = <_ColorEntry>[
  _ColorEntry('Berry', 142, 68, 173),
  _ColorEntry('Coral', 255, 127, 80),
  _ColorEntry('Emerald', 46, 204, 113),
  _ColorEntry('Azure', 0, 127, 255),
  _ColorEntry('Amethyst', 153, 102, 204),
  _ColorEntry('Bronze', 205, 127, 50),
  _ColorEntry('Crimson', 220, 20, 60),
  _ColorEntry('Denim', 21, 96, 189),
  _ColorEntry('Fern', 79, 121, 66),
  _ColorEntry('Gold', 255, 215, 0),
  _ColorEntry('Honey', 235, 150, 5),
  _ColorEntry('Indigo', 75, 0, 130),
  _ColorEntry('Ivory', 255, 255, 240),
  _ColorEntry('Jade', 0, 168, 107),
  _ColorEntry('Khaki', 195, 176, 145),
  _ColorEntry('Lavender', 181, 126, 220),
  _ColorEntry('Lemon', 255, 247, 0),
  _ColorEntry('Lilac', 200, 162, 200),
  _ColorEntry('Lime', 191, 255, 0),
  _ColorEntry('Magenta', 255, 0, 255),
  _ColorEntry('Mahogany', 192, 64, 0),
  _ColorEntry('Mango', 255, 130, 67),
  _ColorEntry('Maple', 196, 98, 16),
  _ColorEntry('Mauve', 224, 176, 255),
  _ColorEntry('Mint', 62, 180, 137),
  _ColorEntry('Mocha', 131, 106, 91),
  _ColorEntry('Moss', 138, 154, 91),
  _ColorEntry('Mustard', 255, 219, 88),
  _ColorEntry('Navy', 0, 0, 128),
  _ColorEntry('Oat', 223, 209, 167),
  _ColorEntry('Obsidian', 56, 56, 56),
  _ColorEntry('Olive', 128, 128, 0),
  _ColorEntry('Onyx', 53, 56, 57),
  _ColorEntry('Opal', 168, 195, 188),
  _ColorEntry('Orange', 255, 165, 0),
  _ColorEntry('Orchid', 218, 112, 214),
  _ColorEntry('Papaya', 255, 164, 119),
  _ColorEntry('Peach', 255, 218, 185),
  _ColorEntry('Pearl', 234, 224, 200),
  _ColorEntry('Periwinkle', 204, 204, 255),
  _ColorEntry('Pine', 1, 121, 111),
  _ColorEntry('Pink', 255, 192, 203),
  _ColorEntry('Pistachio', 147, 197, 114),
  _ColorEntry('Plum', 142, 69, 133),
  _ColorEntry('Poppy', 227, 38, 54),
  _ColorEntry('Pumpkin', 255, 117, 24),
  _ColorEntry('Quartz', 209, 198, 195),
  _ColorEntry('Raspberry', 227, 11, 92),
  _ColorEntry('Rose', 255, 0, 127),
  _ColorEntry('Ruby', 224, 17, 95),
  _ColorEntry('Rust', 183, 65, 14),
  _ColorEntry('Saffron', 244, 196, 48),
  _ColorEntry('Sage', 188, 184, 138),
  _ColorEntry('Salmon', 250, 128, 114),
  _ColorEntry('Sand', 194, 178, 128),
  _ColorEntry('Sapphire', 15, 82, 186),
  _ColorEntry('Scarlet', 255, 36, 0),
  _ColorEntry('Seafoam', 159, 226, 191),
  _ColorEntry('Sepia', 112, 66, 20),
  _ColorEntry('Silver', 192, 192, 192),
  _ColorEntry('Sky', 135, 206, 235),
  _ColorEntry('Slate', 112, 128, 144),
  _ColorEntry('Snow', 255, 250, 250),
  _ColorEntry('Steel', 113, 121, 126),
  _ColorEntry('Storm', 89, 100, 110),
  _ColorEntry('Straw', 228, 217, 111),
  _ColorEntry('Sunset', 250, 128, 46),
  _ColorEntry('Tan', 210, 180, 140),
  _ColorEntry('Tangerine', 255, 153, 0),
  _ColorEntry('Teal', 0, 128, 128),
  _ColorEntry('Terracotta', 204, 78, 92),
  _ColorEntry('Thistle', 216, 191, 216),
  _ColorEntry('Tiger', 252, 109, 36),
  _ColorEntry('Topaz', 255, 200, 124),
  _ColorEntry('Turquoise', 64, 224, 208),
  _ColorEntry('Umber', 99, 81, 71),
  _ColorEntry('Vanilla', 243, 229, 171),
  _ColorEntry('Vermilion', 227, 66, 52),
  _ColorEntry('Violet', 127, 0, 255),
  _ColorEntry('Walnut', 119, 63, 26),
  _ColorEntry('Wheat', 245, 222, 179),
  _ColorEntry('Wine', 114, 47, 55),
  _ColorEntry('Wisteria', 201, 160, 220),
  _ColorEntry('Apricot', 251, 206, 177),
  _ColorEntry('Aqua', 0, 255, 255),
  _ColorEntry('Blush', 222, 93, 131),
  _ColorEntry('Burgundy', 128, 0, 32),
  _ColorEntry('Caramel', 255, 213, 113),
  _ColorEntry('Cerulean', 0, 123, 167),
  _ColorEntry('Charcoal', 54, 69, 79),
  _ColorEntry('Cherry', 222, 49, 99),
  _ColorEntry('Cinnamon', 210, 105, 30),
  _ColorEntry('Clay', 183, 110, 73),
  _ColorEntry('Cobalt', 0, 71, 171),
  _ColorEntry('Copper', 184, 115, 51),
  _ColorEntry('Cream', 255, 253, 208),
  _ColorEntry('Cyan', 0, 188, 212),
  _ColorEntry('Dusk', 78, 81, 128),
  _ColorEntry('Fuchsia', 255, 0, 128),
  _ColorEntry('Garnet', 120, 47, 64),
  _ColorEntry('Glacier', 128, 181, 201),
];

const _adjectives = <String>[
  'Ancient', 'Blazing', 'Cosmic', 'Enchanted', 'Vibrant',
  'Sparkling', 'Mystic', 'Radiant', 'Luminous', 'Vivid',
  'Eternal', 'Frozen', 'Hidden', 'Silent', 'Twilight',
  'Crystal', 'Gentle', 'Serene', 'Bold', 'Brilliant',
  'Celestial', 'Dancing', 'Dreamy', 'Electric', 'Ethereal',
  'Fading', 'Gleaming', 'Glowing', 'Golden', 'Graceful',
  'Iridescent', 'Kindled', 'Lush', 'Mellow', 'Midnight',
  'Noble', 'Opulent', 'Pastel', 'Primal', 'Pristine',
  'Royal', 'Rustic', 'Sacred', 'Shimmering', 'Silken',
  'Smoky', 'Soft', 'Starlit', 'Stormy', 'Subtle',
  'Summer', 'Sunlit', 'Sunset', 'Tender', 'Tranquil',
  'Tropical', 'Twilit', 'Veiled', 'Velvet', 'Warm',
  'Whispered', 'Wild', 'Winter', 'Woven', 'Painted',
  'Polished', 'Poetic', 'Distant', 'Fleeting', 'Fragrant',
  'Infinite', 'Ivory', 'Lavish', 'Living', 'Lunar',
  'Marble', 'Moonlit', 'Mosaic', 'Northern', 'Organic',
  'Phantom', 'Regal', 'Scenic', 'Spring', 'Timeless',
  'Urban', 'Vintage', 'Weathered', 'Zephyr', 'Alpine',
  'Autumn', 'Baroque', 'Boreal', 'Coastal', 'Dappled',
  'Dusted', 'Earthy',
];

const _nouns = <String>[
  'Ambrosia', 'Comet', 'Flame', 'Jewel', 'Wonder',
  'Dream', 'Horizon', 'Aurora', 'Cascade', 'Echo',
  'Galaxy', 'Haven', 'Mirage', 'Nebula', 'Oasis',
  'Phoenix', 'Prism', 'Realm', 'Shadow', 'Solstice',
  'Spirit', 'Tempest', 'Veil', 'Whisper', 'Zenith',
  'Bloom', 'Breeze', 'Canyon', 'Dawn', 'Dusk',
  'Ember', 'Fable', 'Frost', 'Garden', 'Glacier',
  'Glow', 'Harbor', 'Haze', 'Isle', 'Lagoon',
  'Meadow', 'Mist', 'Moonrise', 'Petal', 'Rain',
  'Ridge', 'Ripple', 'River', 'Shore', 'Sky',
  'Spark', 'Starfall', 'Stone', 'Stream', 'Sunset',
  'Thunder', 'Tide', 'Trail', 'Twilight', 'Vale',
  'Vista', 'Voyage', 'Wave', 'Wind', 'Bliss',
  'Charm', 'Crest', 'Crystal', 'Dewdrop', 'Feather',
  'Forest', 'Harmony', 'Journey', 'Lotus', 'Marble',
  'Orchard', 'Passage', 'Serenity', 'Shimmer', 'Silk',
  'Tundra',
];
