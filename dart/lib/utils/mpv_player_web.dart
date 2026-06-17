import 'package:media_kit/media_kit.dart';

/// Web playback goes through HTML `<video>`; there is no libmpv and therefore no
/// stray native window to suppress.
void hardenPlayer(Player player) {}
