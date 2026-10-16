import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../onboarding/profile_controller.dart';
import 'photo_controller.dart';

class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  final Set<String> _compare = {};

  Future<void> _add() async {
    String pose = 'frente';
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'frente', label: Text('Frente')),
                    ButtonSegment(value: 'perfil', label: Text('Perfil')),
                    ButtonSegment(value: 'espalda', label: Text('Espalda')),
                  ],
                  selected: {pose},
                  onSelectionChanged: (s) => setSheet(() => pose = s.first),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Tomar foto'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Elegir de la galería'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (source == null) return;
    await ref.read(photoProvider.notifier).add(
          source: source,
          pose: pose,
          weightKg: ref.read(profileProvider)?.weightKg,
        );
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(photoProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fotos de progreso'),
        actions: [
          if (_compare.length == 2)
            TextButton.icon(
              onPressed: () {
                final pair = photos.where((p) => _compare.contains(p.id)).toList()
                  ..sort((a, b) => a.date.compareTo(b.date));
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => _CompareScreen(before: pair[0], after: pair[1]),
                ));
              },
              icon: const Icon(Icons.compare),
              label: const Text('Comparar'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Nueva foto'),
      ),
      body: photos.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Tus fotos se guardan cifradas solo en este teléfono y nunca se suben a internet.\n\nToma una foto cada 2–4 semanas con la misma luz y postura.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AurumColors.textMuted),
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 3 / 4,
              ),
              itemCount: photos.length,
              itemBuilder: (context, i) {
                final p = photos[i];
                final selected = _compare.contains(p.id);
                return GestureDetector(
                  key: ValueKey(p.id),
                  onTap: () => setState(() {
                    if (selected) {
                      _compare.remove(p.id);
                    } else if (_compare.length < 2) {
                      _compare.add(p.id);
                    }
                  }),
                  onLongPress: () => _confirmDelete(p),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _EncryptedImage(id: p.id),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${p.date.day}/${p.date.month} · ${p.pose}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      if (selected)
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AurumColors.gold, width: 3),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _confirmDelete(PhotoEntry p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar esta foto?'),
        content: const Text('Se elimina de forma permanente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok == true) {
      _compare.remove(p.id);
      await ref.read(photoProvider.notifier).remove(p.id);
    }
  }
}

class _EncryptedImage extends ConsumerStatefulWidget {
  const _EncryptedImage({required this.id});

  final String id;

  @override
  ConsumerState<_EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends ConsumerState<_EncryptedImage> {
  // Se descifra una sola vez por widget, no en cada reconstrucción.
  late final Future<Uint8List?> _bytes =
      ref.read(photoProvider.notifier).bytesOf(widget.id);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return const ColoredBox(color: AurumColors.surfaceHigh);
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

class _CompareScreen extends StatelessWidget {
  const _CompareScreen({required this.before, required this.after});

  final PhotoEntry before;
  final PhotoEntry after;

  @override
  Widget build(BuildContext context) {
    final days = after.date.difference(before.date).inDays;
    String label(PhotoEntry p) =>
        '${p.date.day}/${p.date.month}/${p.date.year}'
        '${p.weightKg != null ? ' · ${p.weightKg!.toStringAsFixed(1)} kg' : ''}';

    return Scaffold(
      appBar: AppBar(title: Text('Antes y después · $days días')),
      body: Row(
        children: [
          for (final p in [before, after])
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _EncryptedImage(id: p.id)),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(label(p)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
