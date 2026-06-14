// lib/services/file_storage_service.dart (VERSION 3.1 - FULL COMPATIBILITY & PRIVACY)

import 'dart:io';
import 'dart:developer';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart'; // IYI NI NGOMBWA KURI VOICE NOTES

enum StorageDirectoryType {
  images,
  video,
  audio,
  documents,
  voiceNotes, // Ubwoko bushya twongeyeho
}

class FileStorageService {
  FileStorageService._privateConstructor();
  static final FileStorageService instance = FileStorageService._privateConstructor();
  final MediaStore _mediaStore = MediaStore();

  Future<bool> requestStoragePermission(StorageDirectoryType dirType) async {
    if (!Platform.isAndroid) return true;

    // Voice notes ntizisaba MediaStore permission kuko zibitse muri App's Private Folder
    if (dirType == StorageDirectoryType.voiceNotes) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    Permission permission;
    if (sdkInt >= 33) {
      switch (dirType) {
        case StorageDirectoryType.images: permission = Permission.photos; break;
        case StorageDirectoryType.video: permission = Permission.videos; break;
        case StorageDirectoryType.audio: permission = Permission.audio; break;
        case StorageDirectoryType.documents: return true;
        default: return true;
      }
    } else {
      permission = Permission.storage;
    }

    final status = await permission.status;
    if (status.isGranted) return true;
    final result = await permission.request();
    return result.isGranted;
  }
  
  // 🔥 IZINA RYAGUMYE UKO RYARI RIRI KUGIRA NGO NTA KOSA RIBAHO
  Future<String?> saveFileToPublicDirectory({
    required String tempFilePath,
    required StorageDirectoryType dirType,
    required String fileName,
  }) async {
    
    // 1. 🔥 LOGIC YA VOICE NOTES (PRIVATE STORAGE - NO MUSIC PLAYER)
    if (dirType == StorageDirectoryType.voiceNotes) {
      return await _saveVoiceNotePrivately(tempFilePath, fileName);
    }

    // 2. LOGIC ISANZWE YA MEDIA (Images, Videos, Audio, Documents)
    MediaStore.appFolder = "Jembe Talk";
    final hasPermission = await requestStoragePermission(dirType);
    if (!hasPermission) {
      log("Required permission not granted. Cannot save file.");
      return null;
    }

    try {
      String relativePath;
      final DirType mediaStoreDirType = DirType.download;
      final DirName mediaStoreDirName = DirName.download;

      switch (dirType) {
        case StorageDirectoryType.images:
          relativePath = "Jembe Talk/Jembe Talk Images";
          break;
        case StorageDirectoryType.video:
          relativePath = "Jembe Talk/Jembe Talk Videos";
          break;
        case StorageDirectoryType.audio:
          relativePath = "Jembe Talk/Jembe Talk Audio";
          break;
        case StorageDirectoryType.documents:
          relativePath = "Jembe Talk/Jembe Talk Documents";
          break;
        default:
          relativePath = "Jembe Talk/Others";
      }

      log("Saving '$fileName' type: $dirType to $mediaStoreDirName/$relativePath");

      final SaveInfo? saveInfo = await _mediaStore.saveFile(
        tempFilePath: tempFilePath,
        dirType: mediaStoreDirType, 
        dirName: mediaStoreDirName, 
        relativePath: relativePath,
      );

      if (saveInfo != null && saveInfo.uri != null) {
        String? finalPath = await _mediaStore.getFilePathFromUri(uriString: saveInfo.uri!.toString());
        
        // Siba file yo muri cache
        final tempFile = File(tempFilePath);
        if (await tempFile.exists()) await tempFile.delete();

        return finalPath;
      }
      return null;
    } catch (e, s) {
      log("Error saving file: $e", stackTrace: s);
      return null;
    }
  }

  // 🔥 FUNCTION IFITE UMUTEKANO KURI VOICE NOTES
  Future<String?> _saveVoiceNotePrivately(String tempPath, String fileName) async {
    try {
      // Ibi bituma ubutumwa bw'amajwi bubikwa muri:
      // 'Internal Storage/Android/data/com.jembe.talk/files/VoiceNotes'
      // Iyi folder ntisomwa n'izindi App (Music Player ntishobora kuyibona)
      final directory = await getExternalStorageDirectory();
      if (directory == null) return null;

      final voiceNoteDir = Directory('${directory.path}/VoiceNotes');
      if (!await voiceNoteDir.exists()) {
        await voiceNoteDir.create(recursive: true);
        
        // Kwemeza ko Android izahisha ibi bintu (No Media Indexing)
        final noMediaFile = File('${voiceNoteDir.path}/.nomedia');
        if (!await noMediaFile.exists()) await noMediaFile.create();
      }

      final String finalPath = '${voiceNoteDir.path}/$fileName';
      final File tempFile = File(tempPath);
      
      if (await tempFile.exists()) {
        await tempFile.copy(finalPath);
        await tempFile.delete(); // Siba ya kera
        log("Voice Note saved privately at: $finalPath");
        return finalPath;
      }
      return null;
    } catch (e) {
      log("Error in private save: $e");
      return null;
    }
  }
}