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
      final isLoaded = await FlutterLeapSdkService.checkModelLoaded();
      
      // Also check if model file exists
      final modelExists = await FlutterLeapSdkService.checkModelExists('LFM2-350M-8da4w_output_8da8w-seq_4096.bundle');
      
      // Get list of all downloaded models
      final downloadedModels = await FlutterLeapSdkService.getDownloadedModels();
      
      setState(() {
        _isModelLoaded = isLoaded;
        String statusText = isLoaded ? 'Model loaded: ${FlutterLeapSdkService.currentLoadedModel}' : 'No model loaded';
        statusText += '\nModel file exists: $modelExists';
        statusText += '\nDownloaded models: ${downloadedModels.length}';
        if (downloadedModels.isNotEmpty) {
          statusText += '\nFiles: ${downloadedModels.join(', ')}';
        }
        _status = statusText;
      });
    } catch (e) {
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
      final taskId = await FlutterLeapSdkService.downloadLFM2_350M(
        onProgress: (progress) {
          setState(() {
            if (progress.percentage >= 100.0) {
              _status = 'Download completed! Model ready to load.';
              _currentDownloadTaskId = null;
            } else {
              _status = 'Downloading: ${progress.percentage.toStringAsFixed(2)}%';
            }
          });
        },
      );
      
      if (taskId != null) {
        _currentDownloadTaskId = taskId;
        setState(() {
          _status = 'Download started (Task: ${taskId.substring(0, 8)}...)';
        });
      }
    } catch (e) {
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
      final result = await FlutterLeapSdkService.loadModel(
        modelPath: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
      );
      setState(() {
        _isModelLoaded = true;
        _status = result;
      });
    } catch (e) {
      setState(() {
        _status = 'Failed to load model: $e';
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
                child: Text(
                  _status,
                  style: Theme.of(context).textTheme.bodyLarge,
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