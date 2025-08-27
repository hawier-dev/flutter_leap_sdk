import 'package:flutter/material.dart';
import 'package:flutter_leap_sdk/flutter_leap_sdk.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';

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
      home: const MainTabScreen(),
    );
  }
}

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LEAP SDK Demo'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.functions), text: 'Function Calling'),
              Tab(icon: Icon(Icons.image), text: 'Vision Chat'),
              Tab(icon: Icon(Icons.chat), text: 'Regular Chat'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            TextChatScreen(),
            VisionChatScreen(),
            RegularChatScreen(),
          ],
        ),
      ),
    );
  }
}

class TextChatScreen extends StatefulWidget {
  const TextChatScreen({super.key});

  @override
  State<TextChatScreen> createState() => _TextChatScreenState();
}

class _TextChatScreenState extends State<TextChatScreen> {
  String _status = 'Initializing...';
  bool _isDownloading = false;
  bool _isLoading = false;
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
        if (isLoaded && _conversation != null) {
          _status = '🚀 Ready to chat! Try: "What\'s the weather in Paris?"';
        } else if (isLoaded) {
          _status = '✅ Model ready - click Load to start chat';
        } else {
          _status = '⬇️ Need to download model';
        }
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
              _status = '✅ Downloaded! Loading model...';
              _loadModel();
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
    setState(() {
      _isLoading = true;
    });
    
    try {
      await FlutterLeapSdkService.loadModel(modelPath: 'LFM2-350M');
      
      // Create conversation through service (creates both Dart and native conversation)
      _conversation = await FlutterLeapSdkService.createConversation(
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
      
      setState(() {
        _isLoading = false;
        _status = '🚀 Ready to chat! Try: "What\'s the weather in Paris?"';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
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
      String assistantResponse = '';
      bool hasFunctionCalls = false;
      
      await for (final response in _conversation!.generateResponseStructured(userMessage)) {
        if (response is MessageResponseChunk) {
          assistantResponse += response.text;
          setState(() {
            if (_messages.isEmpty || _messages.last.role != MessageRole.assistant) {
              _messages.add(ChatMessage.assistant(''));
            }
            _messages[_messages.length - 1] = ChatMessage.assistant(assistantResponse);
          });
        } else if (response is MessageResponseFunctionCalls) {
          hasFunctionCalls = true;
          // Execute functions
          final results = <Map<String, dynamic>>[];
          for (final call in response.functionCalls) {
            try {
              final result = await _conversation!.executeFunction(call);
              results.add({'call': call.toMap(), 'result': result, 'success': true});
            } catch (e) {
              results.add({'call': call.toMap(), 'error': e.toString(), 'success': false});
            }
          }
          
          // Add results and show in UI
          _conversation!.addFunctionResults(results);
          
          setState(() {
            // Update current assistant response if exists
            if (_messages.isNotEmpty && _messages.last.role == MessageRole.assistant) {
              _messages[_messages.length - 1] = ChatMessage.assistant(assistantResponse);
            }
            
            // Add function results as separate message
            String functionInfo = '🔧 Function Results:\n';
            for (final result in results) {
              final success = result['success'] as bool;
              
              if (success) {
                final functionResult = result['result'] as Map<String, dynamic>;
                functionInfo += '📍 Weather in ${functionResult['location']}: ${functionResult['temperature']}°C, ${functionResult['description']}\n';
              } else {
                functionInfo += '❌ Error: ${result['error']}\n';
              }
            }
            _messages.add(ChatMessage.assistant(functionInfo));
          });
        } else if (response is MessageResponseComplete) {
          // Final response after function calls
          if (hasFunctionCalls && response.message.content.isNotEmpty) {
            setState(() {
              // Add final response as separate message
              _messages.add(ChatMessage.assistant('💬 ${response.message.content}'));
            });
          }
          break;
        }
      }
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
                else if (_conversation == null) ...[
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _downloadModel,
                        child: const Text('Download Model'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _loadModel,
                        child: _isLoading 
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Load Model'),
                      ),
                    ],
                  ),
                ],
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

class RegularChatScreen extends StatefulWidget {
  const RegularChatScreen({super.key});

  @override
  State<RegularChatScreen> createState() => _RegularChatScreenState();
}

class _RegularChatScreenState extends State<RegularChatScreen> {
  String _status = 'Initializing...';
  bool _isDownloading = false;
  bool _isLoading = false;
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
        if (isLoaded && _conversation != null) {
          _status = '💬 Ready to chat!';
        } else if (isLoaded) {
          _status = '✅ Model ready - click Load to start chat';
        } else {
          _status = '⬇️ Need to download model';
        }
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
              _status = '✅ Downloaded! Loading model...';
              _loadModel();
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
    setState(() {
      _isLoading = true;
    });
    
    try {
      await FlutterLeapSdkService.loadModel(modelPath: 'LFM2-350M');
      
      _conversation = await FlutterLeapSdkService.createConversation(
        systemPrompt: 'You are a helpful AI assistant.',
      );
      
      setState(() {
        _isLoading = false;
        _status = '💬 Ready to chat!';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
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
      String response = '';
      await for (final chunk in _conversation!.generateResponse(userMessage)) {
        response += chunk;
        setState(() {
          if (_messages.isEmpty || _messages.last.role != MessageRole.assistant) {
            _messages.add(ChatMessage.assistant(''));
          }
          _messages[_messages.length - 1] = ChatMessage.assistant(response);
        });
      }
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
    return Column(
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
              else if (_conversation == null) ...[
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _downloadModel,
                      child: const Text('Download Model'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _loadModel,
                      child: _isLoading 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Load Model'),
                    ),
                  ],
                ),
              ],
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
                      hintText: 'Type a message...',
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
    );
  }
}

class VisionChatScreen extends StatefulWidget {
  const VisionChatScreen({super.key});

  @override
  State<VisionChatScreen> createState() => _VisionChatScreenState();
}

class _VisionChatScreenState extends State<VisionChatScreen> {
  String _status = 'Initializing...';
  bool _isDownloading = false;
  bool _isLoading = false;
  double _downloadProgress = 0.0;
  
  Conversation? _conversation;
  final TextEditingController _messageController = TextEditingController();
  bool _isGenerating = false;
  String _currentResponse = '';
  
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    FlutterLeapSdkService.initialize();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final isLoaded = FlutterLeapSdkService.modelLoaded;
      final currentModel = FlutterLeapSdkService.currentModel;
      final isVisionModel = currentModel.contains('VL') || currentModel.contains('Vision');
      
      setState(() {
        if (isLoaded && isVisionModel && _conversation != null) {
          _status = '🖼️ Vision model ready! Select an image and ask about it.';
        } else if (isLoaded && !isVisionModel) {
          _status = '⚠️ Please load a vision model (LFM2-VL-1.6B) for image processing';
        } else if (isLoaded) {
          _status = '✅ Model ready - click Load to start vision chat';
        } else {
          _status = '⬇️ Need to download vision model';
        }
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
        modelName: 'LFM2-VL-1.6B (Vision)',
        onProgress: (progress) {
          setState(() {
            _downloadProgress = progress.percentage / 100.0;
            if (progress.isComplete) {
              _isDownloading = false;
              _status = '✅ Downloaded! Loading vision model...';
              _loadModel();
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
    setState(() {
      _isLoading = true;
    });
    
    try {
      await FlutterLeapSdkService.loadModel(modelPath: 'LFM2-VL-1.6B (Vision)');
      
      _conversation = await FlutterLeapSdkService.createConversation(
        systemPrompt: 'You are a helpful AI assistant that can see and analyze images. Describe what you see in detail and answer questions about the images.',
      );
      
      setState(() {
        _isLoading = false;
        _status = '🖼️ Vision model ready! Select an image and ask about it.';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = '❌ Load failed: $e';
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _conversation == null) return;
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first')),
      );
      return;
    }

    final userMessage = _messageController.text.trim();
    _messageController.clear();

    setState(() {
      _currentResponse = '';
      _isGenerating = true;
    });

    try {
      final imageBytes = await _selectedImage!.readAsBytes();
      
      // Clear previous response and start streaming
      setState(() {
        _currentResponse = '';
      });
      
      // Generate response with image (vision models don't stream)
      final response = await _conversation!.generateResponseWithImage(userMessage, imageBytes);
      
      setState(() {
        _currentResponse = response;
      });
      
    } catch (e) {
      setState(() {
        _currentResponse = 'Error: $e';
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
              else if (_conversation == null) ...[
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _downloadModel,
                      child: const Text('Download Vision Model'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _loadModel,
                      child: _isLoading 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Load Vision Model'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        
        // Chat section
        if (_conversation != null) ...[
          // Image selection
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              children: [
                if (_selectedImage != null) ...[
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          _selectedImage!,
                          height: 32,
                          width: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedImage!.path.split('/').last,
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library),
                      label: Text(_selectedImage == null ? 'Select Image' : 'Change Image'),
                    ),
                    if (_selectedImage != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => setState(() => _selectedImage = null),
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          
          // Response Output
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.smart_toy, color: Colors.grey.shade600, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Vision Assistant Response:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _isGenerating
                          ? Column(
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  'Analyzing image...',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            )
                          : _currentResponse.isEmpty
                              ? Text(
                                  'Select an image and ask a question to see the response here.',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : SelectableText(
                                  _currentResponse,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.5,
                                  ),
                                ),
                    ),
                  ),
                ],
              ),
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
                      hintText: 'Ask about the image... (try: "What do you see in this image?")',
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
    );
  }
}