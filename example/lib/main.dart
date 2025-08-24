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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const DemoScreen(),
    );
  }
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  bool _isModelLoaded = false;
  String _status = 'Initializing...';
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  
  Conversation? _conversation;
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    FlutterLeapSdkService.initialize();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final isLoaded = FlutterLeapSdkService.modelLoaded;
      setState(() {
        _isModelLoaded = isLoaded;
        _status = isLoaded ? '✅ Model ready' : '⬇️ Need to download model';
      });
    } catch (e) {
      setState(() {
        _status = '❌ Error: $e';
      });
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      await FlutterLeapSdkService.downloadModel(
        modelName: 'LFM2-350M',
        onProgress: (progress) {
          setState(() {
            _downloadProgress = progress.percentage / 100.0;
            if (progress.isComplete) {
              _isDownloading = false;
              _checkStatus();
            }
          });
        },
      );
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _status = '❌ Download failed: $e';
      });
    }
  }

  Future<void> _loadModel() async {
    try {
      await FlutterLeapSdkService.loadModel(modelPath: 'LFM2-350M');
      
      // Create conversation
      _conversation = Conversation(
        id: 'demo-chat',
        systemPrompt: 'You are a helpful AI assistant.',
      );
      
      // Register function
      await _conversation!.registerFunction(
        LeapFunction(
          name: 'get_weather',
          description: 'Get weather information for a location',
          parameters: [
            LeapFunctionParameter(
              name: 'location',
              type: 'string',
              description: 'The city name',
              required: true,
            ),
          ],
          implementation: (args) async {
            final location = args['location'] as String;
            return {
              'location': location,
              'temperature': 22,
              'description': 'Sunny',
            };
          },
        ),
      );
      
      _checkStatus();
    } catch (e) {
      setState(() {
        _status = '❌ Load failed: $e';
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _conversation == null) return;

    final userMessage = _messageController.text.trim();
    _messageController.clear();

    setState(() {
      _messages.add(ChatMessage.user(userMessage));
      _isGenerating = true;
    });

    try {
      // Simple generation - just get the final response
      final response = await _conversation!.generateResponse(userMessage);
      
      setState(() {
        _messages.add(ChatMessage.assistant(response));
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage.assistant('Error: $e'));
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LEAP SDK Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Status section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status: $_status', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_isDownloading)
                  Column(
                    children: [
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 4),
                      Text('Downloading: ${(_downloadProgress * 100).toStringAsFixed(1)}%'),
                    ],
                  )
                else if (!_isModelLoaded)
                  ElevatedButton(
                    onPressed: _downloadModel,
                    child: const Text('Download Model'),
                  )
                else if (_conversation == null)
                  ElevatedButton(
                    onPressed: _loadModel,
                    child: const Text('Load Model & Start Chat'),
                  ),
              ],
            ),
          ),
          
          // Chat section
          if (_conversation != null) ...[
            // Messages
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final isUser = message.role == MessageRole.user;
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blue.shade100 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isUser ? 'You' : 'Assistant',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isUser ? Colors.blue.shade800 : Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(message.content),
                      ],
                    ),
                  );
                },
              ),
            ),
            
            // Input section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message... (try: "What\'s the weather in Paris?")',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      enabled: !_isGenerating,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isGenerating ? null : _sendMessage,
                    child: _isGenerating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}