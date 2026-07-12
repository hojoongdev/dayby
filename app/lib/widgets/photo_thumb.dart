import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// A photo stored on the server, by id. Tap to see it full size.
class PhotoThumb extends ConsumerWidget {
  const PhotoThumb(this.photoId, {super.key, this.size = 56});

  final String photoId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(photoProvider(photoId));
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: photo.when(
          loading: () => const ColoredBox(
            color: Colors.black12,
            child: Center(
              child: SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => const ColoredBox(
            color: Colors.black12,
            child: Icon(Icons.broken_image_outlined, size: 18),
          ),
          data: (bytes) => GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(16),
                child: InteractiveViewer(child: Image.memory(bytes)),
              ),
            ),
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}
