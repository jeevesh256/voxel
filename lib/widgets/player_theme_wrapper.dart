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



  @override
  void initState() {
    super.initState();
    // Do NOT call _updateTheme() here — Theme.of(context) is not safe in initState.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTheme();
  }

  @override
  void didUpdateWidget(covariant PlayerThemeWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.artPath != oldWidget.artPath ||
        widget.fallbackColor != oldWidget.fallbackColor) {
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
        ResizeImage(provider, width: 128, height: 128),
        maximumColorCount: 24,
      ).timeout(const Duration(seconds: 4));

      Color? extractedColor;
      final List<PaletteColor> candidates = List.from(palette.paletteColors);
      
      // Sort candidates using a scoring algorithm that prioritizes saturation and population 
      // while filtering out muted, extreme light, or extreme dark colors.
      candidates.sort((a, b) {
        final hslA = HSLColor.fromColor(a.color);
        final hslB = HSLColor.fromColor(b.color);
        
        // Saturation factor (0.0 to 1.0)
        final satA = hslA.saturation;
        final satB = hslB.saturation;
        
        // Favor colors with a standard pleasant lightness (between 0.25 and 0.70)
        final distToIdealLightA = (hslA.lightness - 0.45).abs();
        final distToIdealLightB = (hslB.lightness - 0.45).abs();
        final lightScoreA = (1.0 - distToIdealLightA).clamp(0.0, 1.0);
        final lightScoreB = (1.0 - distToIdealLightB).clamp(0.0, 1.0);

        final scoreA = satA * satA * lightScoreA * a.population;
        final scoreB = satB * satB * lightScoreB * b.population;
        return scoreB.compareTo(scoreA);
      });

      for (final candidate in candidates) {
        final hsl = HSLColor.fromColor(candidate.color);
        // Exclude extreme dark (lightness < 0.15), extreme bright (lightness > 0.82), and very greyish tones (saturation < 0.20)
        if (hsl.saturation >= 0.20 && hsl.lightness >= 0.15 && hsl.lightness <= 0.82) {
          extractedColor = candidate.color;
          break;
        }
      }

      final Color seedColor = extractedColor ??
          palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.darkVibrantColor?.color ??
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
      final fb = widget.fallbackColor;
      if (fb != null) {
        final scheme = ColorScheme.fromSeed(
          seedColor: fb,
          brightness: Brightness.dark,
        );
        setState(() {
          _currentScheme = scheme;
          _extractedColor = fb;
        });
      } else {
        setState(() {
          _currentScheme = null;
          _extractedColor = null;
        });
      }
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
