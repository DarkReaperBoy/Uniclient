import 'dart:math';
import 'package:flutter/painting.dart';

// Theme name generator — 1:1 port of AyuGram / Telegram Desktop
// Window::Theme::GenerateName (window/themes/window_themes_generate_name.cpp).
// Picks the nearest [_colors] entry to the accent by redmean distance, then
// randomly (50/50) prefixes an adjective or suffixes a subjective.
// _colors / _adjectives / _subjectives are the exact kColors / kAdjectives /
// kSubjectives data from the AyuGram source.

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
    final subjective = _subjectives[rng.nextInt(_subjectives.length)];
    return '$colorName $subjective';
  }
}

class _ColorEntry {
  final String name;
  final int r, g, b;
  const _ColorEntry(this.name, this.r, this.g, this.b);
}

// kColors (window_themes_generate_name.cpp) — declaration order preserved.
const _colors = <_ColorEntry>[
  _ColorEntry('Berry', 142, 0, 0),
  _ColorEntry('Brandy', 222, 193, 150),
  _ColorEntry('Cherry', 128, 11, 71),
  _ColorEntry('Coral', 255, 127, 80),
  _ColorEntry('Cranberry', 219, 80, 121),
  _ColorEntry('Crimson', 220, 20, 60),
  _ColorEntry('Mauve', 224, 176, 255),
  _ColorEntry('Pink', 255, 192, 203),
  _ColorEntry('Red', 255, 0, 0),
  _ColorEntry('Rose', 255, 0, 127),
  _ColorEntry('Russet', 128, 70, 27),
  _ColorEntry('Scarlet', 255, 36, 0),
  _ColorEntry('Seashell', 241, 241, 241),
  _ColorEntry('Strawberry', 255, 51, 153),
  _ColorEntry('Amber', 255, 191, 0),
  _ColorEntry('Apricot', 235, 147, 115),
  _ColorEntry('Banana', 251, 231, 178),
  _ColorEntry('Citrus', 161, 197, 10),
  _ColorEntry('Ginger', 176, 101, 0),
  _ColorEntry('Gold', 255, 215, 0),
  _ColorEntry('Lemon', 253, 233, 16),
  _ColorEntry('Orange', 255, 165, 0),
  _ColorEntry('Peach', 255, 229, 180),
  _ColorEntry('Persimmon', 255, 107, 83),
  _ColorEntry('Sunflower', 228, 212, 34),
  _ColorEntry('Tangerine', 242, 133, 0),
  _ColorEntry('Topaz', 255, 200, 124),
  _ColorEntry('Yellow', 255, 255, 0),
  _ColorEntry('Clover', 56, 73, 16),
  _ColorEntry('Cucumber', 131, 170, 93),
  _ColorEntry('Emerald', 80, 200, 120),
  _ColorEntry('Olive', 181, 179, 92),
  _ColorEntry('Green', 0, 255, 0),
  _ColorEntry('Jade', 0, 168, 107),
  _ColorEntry('Jungle', 41, 171, 135),
  _ColorEntry('Lime', 191, 255, 0),
  _ColorEntry('Malachite', 11, 218, 81),
  _ColorEntry('Mint', 152, 255, 152),
  _ColorEntry('Moss', 173, 223, 173),
  _ColorEntry('Azure', 49, 91, 161),
  _ColorEntry('Blue', 0, 0, 255),
  _ColorEntry('Cobalt', 0, 71, 171),
  _ColorEntry('Indigo', 79, 105, 198),
  _ColorEntry('Lagoon', 1, 121, 135),
  _ColorEntry('Aquamarine', 113, 217, 226),
  _ColorEntry('Ultramarine', 18, 10, 143),
  _ColorEntry('Navy', 0, 0, 128),
  _ColorEntry('Sapphire', 47, 81, 158),
  _ColorEntry('Sky', 118, 215, 234),
  _ColorEntry('Teal', 0, 128, 128),
  _ColorEntry('Turquoise', 64, 224, 208),
  _ColorEntry('Amethyst', 153, 102, 204),
  _ColorEntry('Blackberry', 77, 1, 53),
  _ColorEntry('Eggplant', 97, 64, 81),
  _ColorEntry('Lilac', 200, 162, 200),
  _ColorEntry('Lavender', 181, 126, 220),
  _ColorEntry('Periwinkle', 204, 204, 255),
  _ColorEntry('Plum', 132, 49, 121),
  _ColorEntry('Purple', 102, 0, 153),
  _ColorEntry('Thistle', 216, 191, 216),
  _ColorEntry('Orchid', 218, 112, 214),
  _ColorEntry('Violet', 36, 10, 64),
  _ColorEntry('Bronze', 63, 33, 9),
  _ColorEntry('Chocolate', 55, 2, 2),
  _ColorEntry('Cinnamon', 123, 63, 0),
  _ColorEntry('Cocoa', 48, 31, 30),
  _ColorEntry('Coffee', 112, 101, 85),
  _ColorEntry('Rum', 121, 105, 137),
  _ColorEntry('Mahogany', 78, 6, 6),
  _ColorEntry('Mocha', 120, 45, 25),
  _ColorEntry('Sand', 194, 178, 128),
  _ColorEntry('Sienna', 136, 45, 23),
  _ColorEntry('Maple', 120, 1, 9),
  _ColorEntry('Khaki', 240, 230, 140),
  _ColorEntry('Copper', 184, 115, 51),
  _ColorEntry('Chestnut', 185, 78, 72),
  _ColorEntry('Almond', 238, 217, 196),
  _ColorEntry('Cream', 255, 253, 208),
  _ColorEntry('Diamond', 185, 242, 255),
  _ColorEntry('Honey', 169, 131, 7),
  _ColorEntry('Ivory', 255, 255, 240),
  _ColorEntry('Pearl', 234, 224, 200),
  _ColorEntry('Porcelain', 239, 242, 243),
  _ColorEntry('Vanilla', 209, 190, 168),
  _ColorEntry('White', 255, 255, 255),
  _ColorEntry('Gray', 128, 128, 128),
  _ColorEntry('Black', 0, 0, 0),
  _ColorEntry('Chrome', 232, 241, 212),
  _ColorEntry('Charcoal', 54, 69, 79),
  _ColorEntry('Ebony', 12, 11, 29),
  _ColorEntry('Silver', 192, 192, 192),
  _ColorEntry('Smoke', 245, 245, 245),
  _ColorEntry('Steel', 38, 35, 53),
  _ColorEntry('Apple', 79, 168, 61),
  _ColorEntry('Glacier', 128, 179, 196),
  _ColorEntry('Melon', 254, 186, 173),
  _ColorEntry('Mulberry', 197, 75, 140),
  _ColorEntry('Opal', 169, 198, 194),
  _ColorEntry('Blue', 84, 165, 248),
];

// kAdjectives (window_themes_generate_name.cpp).
const _adjectives = <String>[
  'Ancient', 'Antique', 'Autumn', 'Baby', 'Barely',
  'Baroque', 'Blazing', 'Blushing', 'Bohemian', 'Bubbly',
  'Burning', 'Buttered', 'Classic', 'Clear', 'Cool',
  'Cosmic', 'Cotton', 'Cozy', 'Crystal', 'Dark',
  'Daring', 'Darling', 'Dawn', 'Dazzling', 'Deep',
  'Deepest', 'Delicate', 'Delightful', 'Divine', 'Double',
  'Downtown', 'Dreamy', 'Dusky', 'Dusty', 'Electric',
  'Enchanted', 'Endless', 'Evening', 'Fantastic', 'Flirty',
  'Forever', 'Frigid', 'Frosty', 'Frozen', 'Gentle',
  'Heavenly', 'Hyper', 'Icy', 'Infinite', 'Innocent',
  'Instant', 'Luscious', 'Lunar', 'Lustrous', 'Magic',
  'Majestic', 'Mambo', 'Midnight', 'Millennium', 'Morning',
  'Mystic', 'Natural', 'Neon', 'Night', 'Opaque',
  'Paradise', 'Perfect', 'Perky', 'Polished', 'Powerful',
  'Rich', 'Royal', 'Sheer', 'Simply', 'Sizzling',
  'Solar', 'Sparkling', 'Splendid', 'Spicy', 'Spring',
  'Stellar', 'Sugared', 'Summer', 'Sunny', 'Super',
  'Sweet', 'Tender', 'Tenacious', 'Tidal', 'Toasted',
  'Totally', 'Tranquil', 'Tropical', 'True', 'Twilight',
  'Twinkling', 'Ultimate', 'Ultra', 'Velvety', 'Vibrant',
  'Vintage', 'Virtual', 'Warm', 'Warmest', 'Whipped',
  'Wild', 'Winsome',
];

// kSubjectives (window_themes_generate_name.cpp).
const _subjectives = <String>[
  'Ambrosia', 'Attack', 'Avalanche', 'Blast', 'Bliss',
  'Blossom', 'Blush', 'Burst', 'Butter', 'Candy',
  'Carnival', 'Charm', 'Chiffon', 'Cloud', 'Comet',
  'Delight', 'Dream', 'Dust', 'Fantasy', 'Flame',
  'Flash', 'Fire', 'Freeze', 'Frost', 'Glade',
  'Glaze', 'Gleam', 'Glimmer', 'Glitter', 'Glow',
  'Grande', 'Haze', 'Highlight', 'Ice', 'Illusion',
  'Intrigue', 'Jewel', 'Jubilee', 'Kiss', 'Lights',
  'Lollypop', 'Love', 'Luster', 'Madness', 'Matte',
  'Mirage', 'Mist', 'Moon', 'Muse', 'Myth',
  'Nectar', 'Nova', 'Parfait', 'Passion', 'Pop',
  'Rain', 'Reflection', 'Rhapsody', 'Romance', 'Satin',
  'Sensation', 'Silk', 'Shine', 'Shadow', 'Shimmer',
  'Sky', 'Spice', 'Star', 'Sugar', 'Sunrise',
  'Sunset', 'Sun', 'Twist', 'Unbound', 'Velvet',
  'Vibrant', 'Waters', 'Wine', 'Wink', 'Wonder',
  'Zone',
];
