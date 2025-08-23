import 'dart:io';
import 'dart:typed_data';
import 'background_file_ops.dart';
import 'leap_logger.dart';

/// Chunked file operations for large files to prevent UI blocking
/// Uses streaming I/O to handle files up to several GB without blocking main thread
class ChunkedFileOps {
  static const int _chunkSize = 1024 * 1024; // 1MB chunks
  static const int _yieldEveryChunks = 5; // Yield control every 5 chunks (5MB)

  /// Move large file using chunked streaming instead of atomic rename
  /// This prevents UI blocking for large model files (900MB+)
  static Future<bool> moveFileChunked(
    File source, 
    File destination, {
    Function(double progress)? onProgress,
  }) async {
    try {
      final sourceSize = await BackgroundFileOps.getFileSize(source.path);
      if (sourceSize == 0) {
        LeapLogger.warning('Source file is empty or does not exist: ${source.path}');
        return false;
      }

      int bytesTransferred = 0;
      int chunkCount = 0;
      
      // Open streams
      final sourceStream = source.openRead();
      final destinationSink = destination.openWrite();
      
      LeapLogger.info('Starting chunked file move: ${source.path} → ${destination.path}');
      LeapLogger.info('File size: ${(sourceSize / 1024 / 1024).toStringAsFixed(1)}MB');
      
      try {
        await for (final chunk in sourceStream) {
          await destinationSink.add(chunk);
          bytesTransferred += chunk.length;
          chunkCount++;
          
          // Yield control back to UI thread periodically
          if (chunkCount % _yieldEveryChunks == 0) {
            await Future.delayed(Duration.zero);
          }
          
          // Report progress
          if (onProgress != null && sourceSize > 0) {
            final progress = bytesTransferred / sourceSize;
            onProgress(progress);
          }
        }
        
        // Ensure all data is written
        await destinationSink.flush();
        await destinationSink.close();
        
        // Verify transfer completed successfully
        final destinationSize = await BackgroundFileOps.getFileSize(destination.path);
        if (destinationSize != sourceSize) {
          LeapLogger.error('File transfer size mismatch: expected $sourceSize, got $destinationSize');
          await destination.delete();
          return false;
        }
        
        // Only delete source after successful verification
        await source.delete();
        
        LeapLogger.info('Chunked file move completed successfully');
        return true;
        
      } catch (e) {
        LeapLogger.error('Error during chunked file move: $e');
        await destinationSink.close();
        
        // Clean up partial destination file
        if (await destination.exists()) {
          await destination.delete();
        }
        
        rethrow;
      }
      
    } catch (e) {
      LeapLogger.error('Failed to move file chunked: $e');
      return false;
    }
  }

  /// Copy large file using chunked streaming
  static Future<bool> copyFileChunked(
    File source,
    File destination, {
    Function(double progress)? onProgress,
  }) async {
    try {
      final sourceSize = await BackgroundFileOps.getFileSize(source.path);
      if (sourceSize == 0) {
        LeapLogger.warning('Source file is empty or does not exist: ${source.path}');
        return false;
      }

      int bytesTransferred = 0;
      int chunkCount = 0;
      
      final sourceStream = source.openRead();
      final destinationSink = destination.openWrite();
      
      LeapLogger.info('Starting chunked file copy: ${source.path} → ${destination.path}');
      
      try {
        await for (final chunk in sourceStream) {
          await destinationSink.add(chunk);
          bytesTransferred += chunk.length;
          chunkCount++;
          
          // Yield control periodically
          if (chunkCount % _yieldEveryChunks == 0) {
            await Future.delayed(Duration.zero);
          }
          
          // Report progress
          if (onProgress != null && sourceSize > 0) {
            final progress = bytesTransferred / sourceSize;
            onProgress(progress);
          }
        }
        
        await destinationSink.flush();
        await destinationSink.close();
        
        // Verify copy completed successfully
        final destinationSize = await BackgroundFileOps.getFileSize(destination.path);
        if (destinationSize != sourceSize) {
          LeapLogger.error('File copy size mismatch: expected $sourceSize, got $destinationSize');
          await destination.delete();
          return false;
        }
        
        LeapLogger.info('Chunked file copy completed successfully');
        return true;
        
      } catch (e) {
        await destinationSink.close();
        if (await destination.exists()) {
          await destination.delete();
        }
        rethrow;
      }
      
    } catch (e) {
      LeapLogger.error('Failed to copy file chunked: $e');
      return false;
    }
  }

  /// Read large file in chunks to prevent memory issues
  static Stream<Uint8List> readFileChunked(File file) async* {
    final stream = file.openRead(_chunkSize);
    int chunkCount = 0;
    
    await for (final chunk in stream) {
      yield Uint8List.fromList(chunk);
      chunkCount++;
      
      // Yield control periodically
      if (chunkCount % _yieldEveryChunks == 0) {
        await Future.delayed(Duration.zero);
      }
    }
  }

  /// Get file hash using chunked reading (for verification)
  static Future<String> getFileHashChunked(File file) async {
    // Simple checksum for verification (could be replaced with proper hash)
    int checksum = 0;
    int chunkCount = 0;
    
    await for (final chunk in readFileChunked(file)) {
      for (final byte in chunk) {
        checksum = (checksum + byte) & 0xFFFFFFFF;
      }
      chunkCount++;
      
      // Yield control every few chunks
      if (chunkCount % 10 == 0) {
        await Future.delayed(Duration.zero);
      }
    }
    
    return checksum.toRadixString(16);
  }
}