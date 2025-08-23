import 'package:flutter/material.dart';
import 'package:flutter_leap_sdk/flutter_leap_sdk.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LEAP SDK Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  String _response = '';
  bool _isLoading = false;
  bool _isModelLoaded = false;
  String _status = 'No model loaded';
  String? _currentDownloadTaskId;
  bool _hasText = false;
  String _fileOperationStatus = '';
  double _downloadProgress = 0.0;
  bool _isFinalizingDownload = false;
  String _downloadSpeed = '';
  int _downloadedBytes = 0;
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() {
      setState(() {
        _hasText = _messageController.text.isNotEmpty;
      });
    });
    
    // Initialize the service and logging
    FlutterLeapSdkService.initialize();
    
    _checkModelStatus();
  }

  void _clearResponse() {
    setState(() {
      _response = '';
    });
  }

  Future<void> _checkModelStatus() async {
    try {
      setState(() {
        _status = 'Checking model status...';
        _fileOperationStatus = 'Loading model information...';
      });

      final isLoaded = await FlutterLeapSdkService.checkModelLoaded();
      final modelExists = await FlutterLeapSdkService.checkModelExists(
        'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
      );
      final downloadedModels = await FlutterLeapSdkService.getDownloadedModels();

      setState(() {
        _isModelLoaded = isLoaded;
        _fileOperationStatus = '';
        
        if (isLoaded) {
          _status = '✅ Model loaded and ready (${FlutterLeapSdkService.currentLoadedModel})';
        } else if (modelExists) {
          _status = '📁 Model downloaded, click "Load Model" to use';
        } else if (downloadedModels.isNotEmpty) {
          _status = '📋 ${downloadedModels.length} model(s) available:\n${downloadedModels.map((f) => '• ${FlutterLeapSdkService.getModelDisplayName(f)}').join('\n')}';
        } else {
          _status = '⬇️ No models found. Click "Download Model" to start.';
        }
      });
    } catch (e) {
      setState(() {
        _status = '❌ Error: ${e.toString().split('\n').first}';
        _fileOperationStatus = '';
      });
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isLoading = true;
      _status = '🔄 Starting download...';
    });

    try {
      final taskId = await FlutterLeapSdkService.downloadModel(
        modelName: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
        onProgress: (progress) {
          setState(() {
            _downloadProgress = progress.percentage;
            _downloadedBytes = progress.downloaded;
            _totalBytes = progress.total;
            _downloadSpeed = progress.speed;
            
            if (progress.percentage >= 100.0) {
              _status = '✅ Download completed!';
              _currentDownloadTaskId = null;
              _isFinalizingDownload = false;
              _downloadProgress = 0.0;
              _downloadSpeed = '';
              Future.delayed(const Duration(milliseconds: 500), _checkModelStatus);
            } else if (progress.percentage >= 99.0) {
              _status = '🔄 Finalizing download...';
              _isFinalizingDownload = true;
            } else {
              final percent = progress.percentage.toStringAsFixed(1);
              final downloadedMB = (_downloadedBytes / 1024 / 1024).toStringAsFixed(1);
              final totalMB = (_totalBytes / 1024 / 1024).toStringAsFixed(1);
              _status = '📥 Downloading: $percent% ($downloadedMB/$totalMB MB)';
              _isFinalizingDownload = false;
            }
          });
        },
      );

      if (taskId != null) {
        _currentDownloadTaskId = taskId;
      }
    } catch (e) {
      setState(() {
        _status = '❌ Download failed: ${e.toString().split('\n').first}';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _downloadProgress = 0.0;
        _downloadSpeed = '';
        _isFinalizingDownload = false;
      });
    }
  }

  Future<void> _cancelDownload() async {
    if (_currentDownloadTaskId != null) {
      try {
        await FlutterLeapSdkService.cancelDownload(_currentDownloadTaskId!);
        setState(() {
          _status = '⏹️ Download cancelled';
          _currentDownloadTaskId = null;
          _downloadProgress = 0.0;
          _downloadSpeed = '';
          _isFinalizingDownload = false;
        });
      } catch (e) {
        setState(() {
          _status = '❌ Failed to cancel download';
          _downloadProgress = 0.0;
          _downloadSpeed = '';
          _isFinalizingDownload = false;
        });
      }
    }
  }

  Future<void> _loadModel() async {
    setState(() {
      _isLoading = true;
      _status = '🔄 Loading model...';
    });

    try {
      final modelExists = await FlutterLeapSdkService.checkModelExists(
        'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
      );

      if (!modelExists) {
        setState(() {
          _status = '❌ Model not found! Please download first.';
        });
        return;
      }

      await FlutterLeapSdkService.loadModel(
        modelPath: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
      );

      final isLoaded = await FlutterLeapSdkService.checkModelLoaded();
      setState(() {
        _isModelLoaded = isLoaded;
        _status = isLoaded 
          ? '✅ Model loaded successfully!' 
          : '❌ Model loading failed';
      });
    } catch (e) {
      setState(() {
        _status = '❌ Loading failed: ${e.toString().split('\n').first}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generateResponse() async {
    if (_messageController.text.isEmpty) return;

    final userMessage = _messageController.text;
    _messageController.clear();
    setState(() {
      _hasText = false;
      _isLoading = true;
      _response = '';
      _fileOperationStatus = 'Generating response...';
    });

    try {
      final response = await FlutterLeapSdkService.generateResponse(userMessage);
      setState(() {
        _response = response;
        _fileOperationStatus = '';
      });
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
        _fileOperationStatus = '';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _fileOperationStatus = '';
      });
    }
  }

  void _generateStreamingResponse() {
    if (_messageController.text.isEmpty) return;

    final userMessage = _messageController.text;
    _messageController.clear();
    setState(() {
      _hasText = false;
      _isLoading = true;
      _response = '';
      _fileOperationStatus = 'Streaming response...';
    });

    FlutterLeapSdkService.generateResponseStream(userMessage).listen(
      (chunk) {
        setState(() {
          _response += chunk;
          if (_response.isNotEmpty) {
            _fileOperationStatus = 'Streaming in progress...';
          }
        });
      },
      onError: (error) {
        setState(() {
          _response = 'Streaming error: $error';
          _isLoading = false;
          _fileOperationStatus = '';
        });
      },
      onDone: () {
        setState(() {
          _isLoading = false;
          _fileOperationStatus = '';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LEAP SDK Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Model Status',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: _checkModelStatus,
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh Status',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _status,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (_fileOperationStatus.isNotEmpty) ..[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _fileOperationStatus,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_currentDownloadTaskId != null && _downloadProgress > 0) ..[
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Download Progress',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${_downloadProgress.toStringAsFixed(1)}%',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: _downloadProgress / 100,
                            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _isFinalizingDownload
                                  ? Colors.orange
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          if (_downloadSpeed.isNotEmpty) ..[
                            const SizedBox(height: 4),
                            Text(
                              'Speed: $_downloadSpeed',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Model Actions
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _downloadModel,
                    icon: const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                ),
                if (_currentDownloadTaskId != null) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _cancelDownload,
                    icon: const Icon(Icons.stop),
                    label: const Text('Cancel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _loadModel,
                    icon: const Icon(Icons.memory),
                    label: const Text('Load'),
                  ),
                ),
              ],
            ),
            // File Operation Status
            if (_fileOperationStatus.isNotEmpty)
              Card(
                elevation: 1,
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _fileOperationStatus,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Chat Interface
            const SizedBox(height: 24),
            Text(
              'Chat with Model',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              decoration: InputDecoration(
                labelText: 'Enter your message',
                hintText: 'Ask me anything...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.chat_bubble_outline),
              ),
              maxLines: 3,
              enabled: _isModelLoaded && !_isLoading,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isModelLoaded && !_isLoading && _hasText)
                        ? _generateResponse
                        : null,
                    icon: const Icon(Icons.send),
                    label: const Text('Send'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isModelLoaded && !_isLoading && _hasText)
                        ? _generateStreamingResponse
                        : null,
                    icon: const Icon(Icons.stream),
                    label: const Text('Stream'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            // Response Area
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.chat,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Response',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          if (_response.isNotEmpty)
                            IconButton(
                              onPressed: _clearResponse,
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear response',
                            ),
                          if (_isLoading)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            _response.isEmpty
                                ? 'Model response will appear here...'
                                : _response,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}
