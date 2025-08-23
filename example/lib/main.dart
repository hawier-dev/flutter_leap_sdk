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
      title: 'Flutter LEAP SDK Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter LEAP SDK Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _messageController = TextEditingController();
  String _response = '';
  bool _isLoading = false;
  bool _isModelLoaded = false;
  String _status = 'No model loaded';
  String? _currentDownloadTaskId;

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
  }

  Future<void> _checkModelStatus() async {
    try {
      setState(() {
        _status = 'Checking model status...';
      });

      print('DEBUG: Starting model status check');
      final isLoaded = await FlutterLeapSdkService.checkModelLoaded();
      print('DEBUG: Model loaded status: $isLoaded');
      
      // Also check if model file exists
      final modelExists = await FlutterLeapSdkService.checkModelExists('LFM2-350M-8da4w_output_8da8w-seq_4096.bundle');
      print('DEBUG: Model file exists: $modelExists');
      
      // Get list of all downloaded models
      final downloadedModels = await FlutterLeapSdkService.getDownloadedModels();
      print('DEBUG: Downloaded models: $downloadedModels');
      
      setState(() {
        _isModelLoaded = isLoaded;
        String statusText = isLoaded ? 'Model loaded: ${FlutterLeapSdkService.currentLoadedModel}' : 'No model loaded';
        statusText += '\nModel file exists: $modelExists';
        statusText += '\nDownloaded models: ${downloadedModels.length}';
        if (downloadedModels.isNotEmpty) {
          statusText += '\nFiles: ${downloadedModels.join(', ')}';
        }
        statusText += '\n\n[DEBUG INFO]';
        statusText += '\nSDK isLoaded: $isLoaded';
        statusText += '\nFile exists: $modelExists';
        statusText += '\nDownloaded count: ${downloadedModels.length}';
        _status = statusText;
      });
      print('DEBUG: Status updated: $statusText');
    } catch (e) {
      print('DEBUG: Error in _checkModelStatus: $e');
      setState(() {
        _status = 'Error checking model status: $e';
      });
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isLoading = true;
      _status = 'Starting download...';
    });

    try {
      print('DEBUG: Starting model download');
      final taskId = await FlutterLeapSdkService.downloadLFM2_350M(
        onProgress: (progress) {
          print('DEBUG: Download progress: ${progress.percentage}%');
          setState(() {
            if (progress.percentage >= 100.0) {
              _status = 'Download completed! Checking file...';
              _currentDownloadTaskId = null;
              // Auto-check status after download
              Future.delayed(const Duration(milliseconds: 500), () {
                _checkModelStatus();
              });
            } else {
              _status = 'Downloading: ${progress.percentage.toStringAsFixed(2)}%';
            }
          });
        },
      );
      
      if (taskId != null) {
        _currentDownloadTaskId = taskId;
        print('DEBUG: Download task started: $taskId');
        setState(() {
          _status = 'Download started (Task: ${taskId.substring(0, 8)}...)';
        });
      } else {
        print('DEBUG: Download task ID is null!');
      }
    } catch (e) {
      print('DEBUG: Download error: $e');
      setState(() {
        _status = 'Download failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelDownload() async {
    if (_currentDownloadTaskId != null) {
      try {
        await FlutterLeapSdkService.cancelDownload(_currentDownloadTaskId!);
        setState(() {
          _status = 'Download cancelled';
          _currentDownloadTaskId = null;
        });
      } catch (e) {
        setState(() {
          _status = 'Failed to cancel: $e';
        });
      }
    }
  }

  Future<void> _loadModel() async {
    setState(() {
      _isLoading = true;
      _status = 'Loading model...';
    });

    try {
      print('DEBUG: Attempting to load model: LFM2-350M-8da4w_output_8da8w-seq_4096.bundle');
      
      // First check if file exists before trying to load
      final modelExists = await FlutterLeapSdkService.checkModelExists('LFM2-350M-8da4w_output_8da8w-seq_4096.bundle');
      print('DEBUG: Model file exists before load: $modelExists');
      
      if (!modelExists) {
        setState(() {
          _status = 'ERROR: Model file not found! Please download first.';
        });
        return;
      }

      final result = await FlutterLeapSdkService.loadModel(
        modelPath: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
      );
      print('DEBUG: Model load result: $result');
      
      // Verify the model is actually loaded
      final isLoaded = await FlutterLeapSdkService.checkModelLoaded();
      print('DEBUG: Model loaded verification: $isLoaded');
      
      setState(() {
        _isModelLoaded = isLoaded;
        _status = 'Model load result: $result\nVerification: Model loaded = $isLoaded';
      });
    } catch (e) {
      print('DEBUG: Model load error: $e');
      setState(() {
        _status = 'Failed to load model: $e\n\nFull error details: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generateResponse() async {
    if (_messageController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _response = '';
    });

    try {
      final response = await FlutterLeapSdkService.generateResponse(_messageController.text);
      setState(() {
        _response = response;
      });
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _generateStreamingResponse() {
    if (_messageController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _response = '';
    });

    FlutterLeapSdkService.generateResponseStream(_messageController.text).listen(
      (chunk) {
        setState(() {
          _response += chunk;
        });
      },
      onError: (error) {
        setState(() {
          _response = 'Streaming error: $error';
          _isLoading = false;
        });
      },
      onDone: () {
        setState(() {
          _isLoading = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _status,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _checkModelStatus,
                          child: const Text('Refresh Status'),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Last updated: ${DateTime.now().toString().substring(11, 19)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _downloadModel,
                    child: const Text('Download Model'),
                  ),
                ),
                const SizedBox(width: 4),
                if (_currentDownloadTaskId != null)
                  ElevatedButton(
                    onPressed: _isLoading ? null : _cancelDownload,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _loadModel,
                    child: const Text('Load Model'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Enter your message',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_isModelLoaded && !_isLoading) ? _generateResponse : null,
                    child: const Text('Generate Response'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_isModelLoaded && !_isLoading) ? _generateStreamingResponse : null,
                    child: const Text('Stream Response'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SingleChildScrollView(
                    child: Text(
                      _response.isEmpty ? 'Response will appear here...' : _response,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Center(child: CircularProgressIndicator()),
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