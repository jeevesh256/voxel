import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../services/metadata_service.dart';

/// Shared widget — displays a metadata search result with an apply button.
/// Used by both PlaylistPage and ArtistPage.
class ApplyableMetadataItem extends StatefulWidget {
  final MetadataResult result;
  final bool isITunes;
  final MetadataService metadataService;
  final Function(String? artPath) onApply;
  final Future<Uint8List?> Function(String? url) getPreviewFuture;

  const ApplyableMetadataItem({
    super.key,
    required this.result,
    required this.isITunes,
    required this.metadataService,
    required this.onApply,
    required this.getPreviewFuture,
  });

  @override
  State<ApplyableMetadataItem> createState() => _ApplyableMetadataItemState();
}

class _ApplyableMetadataItemState extends State<ApplyableMetadataItem> {
  bool _isApplying = false;

  Future<void> _applyMetadata() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);

    String? artPath;
    if (widget.result.coverArtUrl != null &&
        widget.result.coverArtUrl!.isNotEmpty) {
      if (widget.isITunes) {
        artPath = await widget.metadataService.downloadCoverArtFromUrl(
          url: widget.result.coverArtUrl!,
          identifier:
              '${widget.result.artist}_${widget.result.album.isNotEmpty ? widget.result.album : widget.result.title}',
        );
      } else if (widget.result.releaseId != null) {
        artPath = await widget.metadataService.downloadCoverArtForRelease(
          releaseId: widget.result.releaseId!,
          identifier:
              '${widget.result.artist}_${widget.result.album.isNotEmpty ? widget.result.album : widget.result.title}',
        );
      }
    }

    if (mounted) widget.onApply(artPath);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 56,
        height: 56,
        child: FutureBuilder<Uint8List?>(
          future: widget.getPreviewFuture(widget.result.coverArtUrl),
          builder: (context, artSnap) {
            if (artSnap.connectionState == ConnectionState.waiting) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            if (artSnap.data != null) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(artSnap.data!, fit: BoxFit.cover),
                ),
              );
            }
            return Container(
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.album, color: Colors.white54),
            );
          },
        ),
      ),
      title: Text(widget.result.title,
          style: const TextStyle(color: Colors.white)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [widget.result.artist, widget.result.album]
                .where((e) => e.isNotEmpty)
                .join(' • '),
            style: TextStyle(color: Colors.grey[400]),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.public,
                size: 16,
                color: widget.isITunes
                    ? Colors.red.shade300
                    : Colors.green.shade300),
          ]),
        ],
      ),
      trailing: _isApplying
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: Icon(Icons.check_circle_outline, color: Colors.grey[400]),
              onPressed: _applyMetadata,
            ),
      onTap: _applyMetadata,
    );
  }
}
