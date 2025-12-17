import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart'; // Provider
import 'package:jembe_talk/language_provider.dart'; // LanguageProvider
import 'package:jembe_talk/services/file_storage_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class FullPhotoScreen extends StatefulWidget {
  final String imageUrl;
  final String heroTag;
  final bool isLocalFile;

  const FullPhotoScreen({
    super.key,
    required this.imageUrl,
    required this.heroTag,
    this.isLocalFile = false,
  });

  @override
  State<FullPhotoScreen> createState() => _FullPhotoScreenState();
}

class _FullPhotoScreenState extends State<FullPhotoScreen> {
  bool _isSaving = false;

  Future<void> _savePhoto() async {
    if (_isSaving) return;
    
    // Tugomba gukoresha Provider(listen: false) hano kuko turi muri async function
    final lang = Provider.of<LanguageProvider>(context, listen: false);

    setState(() {
      _isSaving = true;
    });

    try {
      File sourceFile;
      
      if (widget.isLocalFile) {
        sourceFile = File(widget.imageUrl);
      } else {
        final fileInfo = await DefaultCacheManager().getFileFromCache(widget.imageUrl);
        if (fileInfo == null || !await fileInfo.file.exists()) {
          final downloadedFile = await DefaultCacheManager().downloadFile(widget.imageUrl);
          sourceFile = downloadedFile.file;
        } else {
          sourceFile = fileInfo.file;
        }
      }

      if (!await sourceFile.exists()) {
        throw Exception(lang.t('photo_not_found_error')); // "Ifoto ntibonetse..."
      }

      final tempDir = await getTemporaryDirectory();
      final tempFileName = 'saving_copy_${path.basename(sourceFile.path)}';
      final tempCopiedFile = await sourceFile.copy(path.join(tempDir.path, tempFileName));
      
      final finalFileName = 'JembeTalk_IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final savedPath = await FileStorageService.instance.saveFileToPublicDirectory(
        tempFilePath: tempCopiedFile.path,
        dirType: StorageDirectoryType.images,
        fileName: finalFileName,
      );

      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lang.t('photo_saved_success'))), // "Ifoto ibitswe..."
        );
      } else {
        throw Exception(lang.t('photo_save_error')); // "Kwandika ifoto byanze."
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${lang.t('photo_save_generic_error')} $e')), // "Habaye ikosa..."
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context); // Provider

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download_rounded),
                  tooltip: lang.t('photo_tooltip_save'), // "Bika ifoto"
                  onPressed: _savePhoto,
                ),
        ],
      ),
      body: Center(
        child: Hero(
          tag: widget.heroTag,
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4,
            child: Builder(
              builder: (context) {
                if (widget.isLocalFile) {
                  return Image.file(
                    File(widget.imageUrl),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => _buildErrorWidget(lang),
                  );
                } else {
                  return CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) => _buildErrorWidget(lang),
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(LanguageProvider lang) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_outlined, color: Colors.white, size: 50),
          const SizedBox(height: 10),
          Text(lang.t('photo_display_error'), style: const TextStyle(color: Colors.white)), // "Ntibishoboye..."
        ],
      ),
    );
  }
}