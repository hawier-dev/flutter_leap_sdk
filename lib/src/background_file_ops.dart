import 'dart:isolate';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Background file operations to prevent UI thread blocking
/// All heavy I/O operations are performed in isolates
class BackgroundFileOps {
  /// Get file size in background isolate
  static Future<int> getFileSize(String path) async {
    return await compute(_getFileSizeIsolate, path);
  }
  
  /// Check if file exists in background isolate
  static Future<bool> fileExists(String path) async {
    return await compute(_fileExistsIsolate, path);
  }
  
  /// List model files in directory in background isolate
  static Future<List<String>> listModelFiles(String dirPath) async {
    return await compute(_listFilesIsolate, dirPath);
  }
  
  /// Get file stats in background isolate
  static Future<FileStat?> getFileStat(String path) async {
    return await compute(_getFileStatIsolate, path);
  }
  
  /// Delete file in background isolate
  static Future<bool> deleteFile(String path) async {
    return await compute(_deleteFileIsolate, path);
  }

  // Static isolate functions
  static int _getFileSizeIsolate(String path) {
    try {
      final file = File(path);
      return file.existsSync() ? file.lengthSync() : 0;
    } catch (e) {
      return 0;
    }
  }
  
  static bool _fileExistsIsolate(String path) {
    try {
      return File(path).existsSync();
    } catch (e) {
      return false;
    }
  }
  
  static List<String> _listFilesIsolate(String dirPath) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return [];
      
      return dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.bundle'))
          .map((file) => file.path.split('/').last)
          .toList();
    } catch (e) {
      return [];
    }
  }
  
  static FileStat? _getFileStatIsolate(String path) {
    try {
      final file = File(path);
      return file.existsSync() ? file.statSync() : null;
    } catch (e) {
      return null;
    }
  }
  
  static bool _deleteFileIsolate(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}