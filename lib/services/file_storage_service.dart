import 'dart:io';
import 'dart:developer';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

enum StorageDirectoryType {
  images,
  video,
  audio,
  documents,
}

class FileStorageService {
  FileStorageService._privateConstructor();
  static final FileStorageService instance = FileStorageService._privateConstructor();
  final MediaStore _mediaStore = MediaStore();

  Future<bool> requestStoragePermission(StorageDirectoryType dirType) async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    Permission permission;
    
    // Kuva kuri Android 13 (SDK 33), impushya zaratandukanye
    if (sdkInt >= 33) {
      switch (dirType) {
        case StorageDirectoryType.images:
          permission = Permission.photos;
          break;
        case StorageDirectoryType.video:
          permission = Permission.videos;
          break;
        case StorageDirectoryType.audio:
          // Hano niho twemeza ko audio ifite uruhushya rwayo
          permission = Permission.audio;
          break;
        case StorageDirectoryType.documents:
          // Documents akenshi ntabwo zisaba uruhushya rwinshi nka media kuri Android nshya
          return true;
      }
    } else {
      // Kuri Android za kera, ni uruhushya rumwe rwa 'storage'
      permission = Permission.storage;
    }

    final status = await permission.status;
    if (status.isGranted) {
      return true;
    } else {
      final result = await permission.request();
      if(result.isGranted){
        return true;
      } else {
        log('${permission.toString()} permission denied. Opening app settings.');
        await openAppSettings();
        return false;
      }
    }
  }
  
  Future<String?> saveFileToPublicDirectory({
    required String tempFilePath,
    required StorageDirectoryType dirType,
    required String fileName,
  }) async {
    // Ibi ntibigikoreshwa cyane muri MediaStorePlus nshya ariko turabireka
    MediaStore.appFolder = "Jembe Talk";

    final hasPermission = await requestStoragePermission(dirType);
    if (!hasPermission) {
      log("Required permission not granted. Cannot save file.");
      return null;
    }

    try {
      String relativePath;
      
      // Dukoresha 'DirType.download' kuri byose kugira ngo tubashe
      // gukora folder zacu bwite nka 'Jembe Talk/...'
      // Android izamenya ubwoko bwa fayili ishingiye kuri extension (.mp3, .jpg, etc)
      final DirType mediaStoreDirType = DirType.download;
      final DirName mediaStoreDirName = DirName.download;

      // Hano niho dusobanura neza aho buri fayili igomba kujya
      switch (dirType) {
        case StorageDirectoryType.images:
          relativePath = "Jembe Talk/Jembe Talk Images";
          break;
        case StorageDirectoryType.video:
          relativePath = "Jembe Talk/Jembe Talk Videos";
          break;
        case StorageDirectoryType.audio:
          // Hano twongeyemo Folder ya Audio kugira ngo iboneke neza
          relativePath = "Jembe Talk/Jembe Talk Audio";
          break;
        case StorageDirectoryType.documents:
          relativePath = "Jembe Talk/Jembe Talk Documents";
          break;
      }

      log("Saving '$fileName' type: $dirType from '$tempFilePath' to $mediaStoreDirName/$relativePath");

      final SaveInfo? saveInfo = await _mediaStore.saveFile(
        tempFilePath: tempFilePath,
        dirType: mediaStoreDirType, 
        dirName: mediaStoreDirName, 
        relativePath: relativePath,
      );

      if (saveInfo == null) {
        log("Failed to save file using MediaStore. SaveInfo is null.");
        return null;
      }
      
      String? finalPath;
      if (saveInfo.uri != null) {
        finalPath = await _mediaStore.getFilePathFromUri(uriString: saveInfo.uri!.toString());
      } else {
         log("Failed to get uri from SaveInfo object.");
         return null;
      }

      if (finalPath == null || finalPath.isEmpty) {
        log("getFilePathFromUri returned null or empty path.");
        return null;
      }

      log("File saved successfully. Final path: $finalPath");
      
      // Turasiba fayili yo muri cache (temp) kuko yamaze kubikwa ahabona
      final tempFile = File(tempFilePath);
      if (await tempFile.exists()) {
        await tempFile.delete();
        log("Temporary file deleted: $tempFilePath");
      }

      return finalPath;

    } catch (e, s) {
      log("Error saving file to public directory: $e", stackTrace: s);
      return null;
    }
  }
}