import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'network_browser_page.dart';

class PhotoSlideshowPage extends StatefulWidget {
  final List<BrowserItem> items;
  final int initialIndex;

  const PhotoSlideshowPage({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<PhotoSlideshowPage> createState() => _PhotoSlideshowPageState();
}

class _PhotoSlideshowPageState extends State<PhotoSlideshowPage> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isPlaying = true;
  Timer? _slideshowTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _startSlideshow();
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startSlideshow() {
    _slideshowTimer?.cancel();
    if (!_isPlaying) return;
    _slideshowTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (_currentIndex < widget.items.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      } else {
        // Loop back to beginning
        _pageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _startSlideshow();
      } else {
        _slideshowTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${widget.items.length}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
            onPressed: _togglePlay,
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.items.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
          // Restart timer on manual swipe to give full 3 seconds to current slide
          if (_isPlaying) {
            _startSlideshow();
          }
        },
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final imageUrl = (item.streamUrl != null && item.streamUrl!.isNotEmpty)
              ? item.streamUrl
              : item.artworkUrl;
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 3.0,
            child: Center(
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white30),
                      errorWidget: (context, url, error) => const Icon(Icons.broken_image_rounded, color: Colors.white30, size: 64),
                    )
                  : const Icon(Icons.image_rounded, color: Colors.white30, size: 64),
            ),
          );
        },
      ),
    );
  }
}
