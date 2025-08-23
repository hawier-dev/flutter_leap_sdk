/// Information about a LEAP SDK model bundle.
///
/// Contains metadata for downloadable LFM2 models including file details,
/// display name, estimated size, and download URL.
class ModelInfo {
  /// The actual filename of the model bundle
  final String fileName;

  /// Human-readable display name for the model
  final String displayName;

  /// Estimated size of the model (e.g., "322 MB")
  final String size;

  /// Direct download URL for the model bundle
  final String url;

  const ModelInfo({
    required this.fileName,
    required this.displayName,
    required this.size,
    required this.url,
  });

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'displayName': displayName,
      'size': size,
      'url': url,
    };
  }

  factory ModelInfo.fromMap(Map<String, dynamic> map) {
    return ModelInfo(
      fileName: map['fileName'] ?? '',
      displayName: map['displayName'] ?? '',
      size: map['size'] ?? '',
      url: map['url'] ?? '',
    );
  }

  @override
  String toString() {
    return 'ModelInfo(fileName: $fileName, displayName: $displayName, size: $size, url: $url)';
  }
}

/// Represents the progress of a model download operation.
///
/// Tracks download progress with bytes downloaded, total bytes, percentage, and speed.
/// Used in download progress callbacks to provide real-time download status.
class DownloadProgress {
  /// Number of bytes successfully downloaded
  final int bytesDownloaded;

  /// Total size of the download in bytes
  final int totalBytes;

  /// Percentage of download completed (0.0 to 100.0)
  final double percentage;

  /// Current download speed as a formatted string
  final String speed;

  const DownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.percentage,
    this.speed = '',
  });

  /// Alias for bytesDownloaded for backward compatibility
  int get downloaded => bytesDownloaded;
  
  /// Alias for totalBytes for backward compatibility
  int get total => totalBytes;

  bool get isComplete => percentage >= 100.0;

  @override
  String toString() {
    return 'DownloadProgress(bytesDownloaded: $bytesDownloaded, totalBytes: $totalBytes, percentage: ${percentage.toStringAsFixed(1)}%, speed: $speed)';
  }
}
