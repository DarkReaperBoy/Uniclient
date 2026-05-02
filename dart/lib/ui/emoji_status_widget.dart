import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import 'custom_emoji_cache.dart';

class EmojiStatusWidget extends StatefulWidget {
  final String emojiStatusId;
  final String accountId;
  final double size;
  final Color? fallbackColor;

  const EmojiStatusWidget({
    super.key,
    required this.emojiStatusId,
    required this.accountId,
    this.size = 20.0,
    this.fallbackColor,
  });

  @override
  State<EmojiStatusWidget> createState() => _EmojiStatusWidgetState();
}

class _EmojiStatusWidgetState extends State<EmojiStatusWidget>
    with TickerProviderStateMixin {
  static const int _maxLoops = 2;

  AnimationController? _lottieController;
  int _loopCount = 0;
  Uint8List? _decompressedLottie;

  int? _documentId;
  bool _isCollectible = false;
  Color? _collectibleCenterColor;
  Color? _collectibleEdgeColor;

  @override
  void initState() {
    super.initState();
    _parseEmojiStatusId();
    CustomEmojiCache.instance.addListener(_onCacheUpdate);
    _requestIfNeeded();
  }

  @override
  void didUpdateWidget(EmojiStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emojiStatusId != widget.emojiStatusId) {
      _lottieController?.dispose();
      _lottieController = null;
      _decompressedLottie = null;
      _loopCount = 0;
      _parseEmojiStatusId();
      _requestIfNeeded();
    }
  }

  @override
  void dispose() {
    CustomEmojiCache.instance.removeListener(_onCacheUpdate);
    _lottieController?.dispose();
    super.dispose();
  }

  void _parseEmojiStatusId() {
    final id = widget.emojiStatusId;
    if (id.isEmpty) {
      _documentId = null;
      _isCollectible = false;
      return;
    }

    if (id.startsWith('collectible:')) {
      _isCollectible = true;
      final parts = id.substring(12).split(':');
      _documentId = int.tryParse(parts[0]);
      if (parts.length >= 3) {
        _collectibleCenterColor = _parseHexColor(parts[1]);
        _collectibleEdgeColor = _parseHexColor(parts[2]);
      }
    } else if (id.startsWith('userpic:')) {
      _documentId = null;
      _isCollectible = false;
    } else {
      _documentId = int.tryParse(id);
      _isCollectible = false;
    }
  }

  static Color? _parseHexColor(String hex) {
    if (hex.isEmpty) return null;
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final val = int.tryParse(hex, radix: 16);
    return val != null ? Color(val) : null;
  }

  void _onCacheUpdate() {
    if (!mounted || _documentId == null) return;
    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(_documentId!);
    if (file != null && file.isTgs && _decompressedLottie == null) {
      _decompressLottie(file.fileData);
    }
    setState(() {});
  }

  void _requestIfNeeded() {
    if (_documentId == null || widget.accountId.isEmpty) return;
    final cache = CustomEmojiCache.instance;
    if (cache.getThumb(_documentId!) == null &&
        !cache.isPending(_documentId!) &&
        !cache.hasFailed(_documentId!)) {
      final engine = context.read<EngineService>();
      cache.request(_documentId!, widget.accountId, engine);
    }
    if (cache.getFile(_documentId!) == null &&
        !cache.isFilePending(_documentId!)) {
      final engine = context.read<EngineService>();
      cache.requestFile(_documentId!, widget.accountId, engine);
    }
  }

  void _decompressLottie(Uint8List tgsData) {
    try {
      _decompressedLottie = Uint8List.fromList(gzip.decode(tgsData));
    } catch (_) {}
  }

  bool _isPowerSaving(BuildContext context) {
    final appState = context.read<AppState>();
    return appState.powerSaving(AppState.kPowerSavingEmojiStatus);
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieController?.dispose();
    _lottieController = AnimationController(
      vsync: this,
      duration: composition.duration,
    );
    _loopCount = 0;
    _lottieController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _loopCount++;
        if (_loopCount < _maxLoops) {
          _lottieController!.forward(from: 0);
        }
      }
    });
    _lottieController!.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.emojiStatusId.isEmpty || _documentId == null) {
      return const SizedBox.shrink();
    }

    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(_documentId!);
    final powerSaving = _isPowerSaving(context);
    final s = widget.size;

    Widget content;

    if (file != null && !powerSaving) {
      if (file.isTgs && _decompressedLottie != null) {
        content = Lottie.memory(
          _decompressedLottie!,
          width: s,
          height: s,
          fit: BoxFit.contain,
          controller: _lottieController,
          onLoaded: _onLottieLoaded,
          errorBuilder: (_, __, ___) => _buildThumbOrFallback(cache),
        );
      } else if (file.isWebp) {
        content = Image.memory(
          file.fileData,
          width: s,
          height: s,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _buildThumbOrFallback(cache),
        );
      } else {
        content = _buildThumbOrFallback(cache);
      }
    } else {
      content = _buildThumbOrFallback(cache);
    }

    if (_isCollectible && _collectibleCenterColor != null && _collectibleEdgeColor != null) {
      content = ShaderMask(
        shaderCallback: (bounds) => RadialGradient(
          colors: [_collectibleCenterColor!, _collectibleEdgeColor!],
        ).createShader(bounds),
        blendMode: BlendMode.srcATop,
        child: content,
      );
    }

    return SizedBox(width: s, height: s, child: content);
  }

  Widget _buildThumbOrFallback(CustomEmojiCache cache) {
    final thumb = cache.getThumb(_documentId!);
    final s = widget.size;
    if (thumb != null) {
      return Image.memory(
        thumb,
        width: s,
        height: s,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _premiumFallback(s),
      );
    }
    return _premiumFallback(s);
  }

  Widget _premiumFallback(double s) {
    return Icon(
      Icons.workspace_premium,
      size: s,
      color: widget.fallbackColor ?? const Color(0xFF6C3BEB),
    );
  }
}

