import 'dart:typed_data';

import '../utils/native_clipboard.dart';

/// Formerly thrown by [getClipboardImage] when the platform clipboard-image
/// tool was missing (Linux: neither `wl-paste` nor `xclip` installed). The
/// clipboard now goes through the native `pasteboard` plugin
/// ([NativeClipboard]) instead of shelling out, so there is no external-binary
/// dependency and this failure mode can no longer arise — but the type is kept
/// because callers still `catch` it (e.g. `my_profile_page.dart`,
/// `contacts_screen.dart`). It is simply never thrown anymore, matching
/// AyuGram, which reads the clipboard natively via
/// `QGuiApplication::clipboard()->mimeData()` (userpic_button.cpp:383-384).
class ClipboardToolMissingException implements Exception {
  final String message;
  const ClipboardToolMissingException(this.message);
  @override
  String toString() => message;
}

/// Reads a raw image from the system clipboard, returning its PNG bytes, or
/// null if the clipboard holds no image. Mirrors AyuGram's
/// `QGuiApplication::clipboard()->mimeData()->hasImage()` path used by
/// `showPhotoMenu` ("Photo from clipboard"). Delegates to [NativeClipboard]
/// (the `pasteboard` plugin — platform channels, no subprocess), which coerces
/// any clipboard image format to PNG bytes, reproducing Qt's
/// `qvariant_cast<QImage>(data->imageData())` coercion natively.
///
/// No longer throws [ClipboardToolMissingException] — native clipboard access
/// has no external-tool dependency to be missing — but the signature is
/// retained for callers that still guard against it.
Future<Uint8List?> getClipboardImage() async {
  return NativeClipboard.readImage();
}

/// Reports whether the system clipboard currently offers an image. This is the
/// gate AyuGram applies before adding the "Photo from clipboard" menu action:
/// the item only appears when `data->hasImage()` is true
/// (userpic_button.cpp:382-398). Backed by [NativeClipboard.readImage]; returns
/// false (never throws) on any failure, so a menu item that silently doesn't
/// appear is the correct degradation — exactly matching AyuGram not adding the
/// action when `hasImage()` is false.
Future<bool> clipboardHasImage() async {
  try {
    final bytes = await NativeClipboard.readImage();
    return bytes != null && bytes.isNotEmpty;
  } catch (_) {
    return false;
  }
}
