class ModelInfo {
  final String fileName;
  final String displayName;
  final String size;
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

class DownloadProgress {
  final int bytesDownloaded;
  final int totalBytes;
  final double percentage;

  const DownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.percentage,
  });

  bool get isComplete => percentage >= 100.0;

  @override
  String toString() {
    return 'DownloadProgress(bytesDownloaded: $bytesDownloaded, totalBytes: $totalBytes, percentage: ${percentage.toStringAsFixed(1)}%)';
  }
}