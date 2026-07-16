import 'dart:io';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/artwork_validator.dart';

class PlayerThemeWrapper extends StatefulWidget {
  final String? artPath;
  final Color? fallbackColor;
  final bool parseArtwork;
  final Widget Function(BuildContext context, ColorScheme colorScheme, Color extractedColor) builder;

  const PlayerThemeWrapper({
    super.key,
    required this.artPath,
    this.fallbackColor,
    this.parseArtwork = true,
    required this.builder,
  });

  @override
  State<PlayerThemeWrapper> createState() => _PlayerThemeWrapperState();
}

class _PlayerThemeWrapperState extends State<PlayerThemeWrapper> {
  static final Map<String, _ThemeCacheEntry> _cache = {};
  
  ColorScheme? _currentScheme;
  Color? _extractedColor;
  String? _lastArtPath;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // Do NOT call _updateTheme() here — Theme.of(context) is not safe in initState.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final art = widget.artPath;
      final fallbackPrimary = widget.fallbackColor ?? Theme.of(context).colorScheme.primary;

      if (art != null && art.isNotEmpty && isValidArtwork(art) && _cache.containsKey(art)) {
        final entry = _cache[art]!;
        _currentScheme = entry.scheme;
        _extractedColor = entry.color;
      } else {
        _currentScheme = ColorScheme.fromSeed(
          seedColor: fallbackPrimary,
          brightness: Brightness.dark,
        );
        _extractedColor = fallbackPrimary;
      }
      _updateTheme();
    }
  }

  @override
  void didUpdateWidget(covariant PlayerThemeWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.artPath != oldWidget.artPath) {
      final art = widget.artPath;
      if (art != null && art.isNotEmpty && isValidArtwork(art) && _cache.containsKey(art)) {
        final entry = _cache[art]!;
        _currentScheme = entry.scheme;
        _extractedColor = entry.color;
      }
      _updateTheme();
    }
  }

  Future<void> _updateTheme() async {
    final art = widget.artPath;
    _lastArtPath = art;
    final fallbackPrimary = widget.fallbackColor ?? Theme.of(context).colorScheme.primary;

    if (art == null || art.isEmpty || !isValidArtwork(art)) {
      _applyFallback();
      return;
    }

    // Check memory cache
    if (_cache.containsKey(art)) {
      final entry = _cache[art]!;
      if (mounted && _lastArtPath == art) {
        setState(() {
          _currentScheme = entry.scheme;
          _extractedColor = entry.color;
        });
      }
      return;
    }

    if (!widget.parseArtwork) {
      _applyFallback();
      return;
    }

    try {
      ImageProvider? provider;
      if (art.startsWith('http://') || art.startsWith('https://')) {
        provider = CachedNetworkImageProvider(art);
      } else {
        String filePath = art;
        if (art.startsWith('file://')) {
          try {
            filePath = Uri.parse(art).toFilePath();
          } catch (_) {
            filePath = art.replaceFirst('file://', '');
          }
        }
        final file = File(filePath);
        if (file.existsSync()) {
          provider = FileImage(file);
        }
      }

      if (provider == null) {
        _applyFallback();
        return;
      }

      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(provider, width: 12, height: 12),
        maximumColorCount: 8,
      ).timeout(const Duration(seconds: 4));

      Color? extractedColor;
      final List<PaletteColor> candidates = List.from(palette.paletteColors);
      candidates.sort((a, b) {
        final hslA = HSLColor.fromColor(a.color);
        final hslB = HSLColor.fromColor(b.color);
        final scoreA = hslA.saturation * a.population;
        final scoreB = hslB.saturation * b.population;
        return scoreB.compareTo(scoreA);
      });

      for (final candidate in candidates) {
        final hsl = HSLColor.fromColor(candidate.color);
        if (hsl.saturation >= 0.15 && hsl.lightness >= 0.1 && hsl.lightness <= 0.85) {
          extractedColor = candidate.color;
          break;
        }
      }

      final Color seedColor = extractedColor ??
          palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          fallbackPrimary;

      // Generate a refined dark M3 ColorScheme using the seed color
      final scheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      );

      _cache[art] = _ThemeCacheEntry(scheme: scheme, color: seedColor);

      if (mounted && _lastArtPath == art) {
        setState(() {
          _currentScheme = scheme;
          _extractedColor = seedColor;
        });
      }
    } catch (_) {
      _applyFallback();
    }
  }

  void _applyFallback() {
    if (mounted) {
      final fallbackPrimary = widget.fallbackColor ?? Theme.of(context).colorScheme.primary;
      final scheme = ColorScheme.fromSeed(
        seedColor: fallbackPrimary,
        brightness: Brightness.dark,
      );
      setState(() {
        _currentScheme = scheme;
        _extractedColor = fallbackPrimary;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultScheme = Theme.of(context).colorScheme;
    final activeScheme = _currentScheme ?? defaultScheme;
    final activeColor = _extractedColor ?? defaultScheme.primary;

    return widget.builder(context, activeScheme, activeColor);
  }
}

class _ThemeCacheEntry {
  final ColorScheme scheme;
  final Color color;

  const _ThemeCacheEntry({
    required this.scheme,
    required this.color,
  });
}
