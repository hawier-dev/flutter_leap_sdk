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
      title: 'LEAP SDK Chat Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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
  final ScrollController _scrollController = ScrollController();
  
  Conversation? _conversation;
  List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _isModelLoaded = false;
  String _status = 'No model loaded';
  
  // Model management
  String? _currentDownloadTaskId;
  double _downloadProgress = 0.0;
  String _downloadSpeed = '';
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    FlutterLeapSdkService.initialize();
    _checkModelStatus();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkModelStatus() async {
    try {
      setState(() {
        _status = 'Checking model status...';
      });

      final isLoaded = await FlutterLeapSdkService.checkModelLoaded();
      final downloadedModels = await FlutterLeapSdkService.getDownloadedModels();

      setState(() {
        _isModelLoaded = isLoaded;
        
        if (isLoaded) {
          _status = '✅ Model ready: ${FlutterLeapSdkService.currentModel}';
        } else if (downloadedModels.isNotEmpty) {
          _status = '📁 ${downloadedModels.length} model(s) available - Load to start chatting';
        } else {
          _status = '⬇️ No models found - Download to start chatting';
        }
      });
    } catch (e) {
      setState(() {
        _status = '❌ Error: ${e.toString().split('\n').first}';
      });
    }
  }

  Future<void> _createConversation() async {
    try {
      final conversation = await FlutterLeapSdkService.createConversation(
        systemPrompt: "You are a helpful AI assistant. Be concise and friendly.",
        generationOptions: GenerationOptions.balanced(),
      );
      
      setState(() {
        _conversation = conversation;
        _messages = [];
      });
    } catch (e) {
      _showErrorDialog('Failed to create conversation: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _conversation == null) return;
    
    final userMessage = _messageController.text.trim();
    _messageController.clear();
    
    setState(() {
      _messages.add(ChatMessage.user(userMessage));
      _isTyping = true;
    });
    
    _scrollToBottom();
    
    try {
      String assistantResponse = '';
      
      await for (final chunk in _conversation!.generateResponseStream(userMessage)) {
        setState(() {
          if (_messages.isEmpty || _messages.last.role != MessageRole.assistant) {
            _messages.add(ChatMessage.assistant(''));
          }
          assistantResponse += chunk;
          _messages[_messages.length - 1] = ChatMessage.assistant(assistantResponse);
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage.assistant('Error: ${e.toString()}'));
      });
    } finally {
      setState(() {
        _isTyping = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    setState(() {
      _showSettings = true;
    });
  }

  void _hideSettings() {
    setState(() {
      _showSettings = false;
    });
  }

  Widget _buildChatInterface() {
    return Column(
      children: [
        // Status bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: _isModelLoaded ? Colors.green.shade50 : Colors.orange.shade50,
          child: Row(
            children: [
              Icon(
                _isModelLoaded ? Icons.check_circle : Icons.warning,
                color: _isModelLoaded ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_status)),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: _openSettings,
              ),
            ],
          ),
        ),
        
        // Messages
        Expanded(
          child: _conversation == null 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      _isModelLoaded 
                        ? 'Ready to chat!\nTap the message button to start.'
                        : 'Load a model to start chatting',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isTyping) {
                    return _buildTypingIndicator();
                  }
                  
                  final message = _messages[index];
                  return _buildMessageBubble(message);
                },
              ),
        ),
        
        // Input
        if (_isModelLoaded) _buildMessageInput(),
      ],
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.role == MessageRole.user;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.purple.shade100,
              child: Icon(Icons.android, size: 16, color: Colors.purple.shade700),
            ),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue.shade500 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.person, size: 16, color: Colors.blue.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.purple.shade100,
            child: Icon(Icons.android, size: 16, color: Colors.purple.shade700),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(3, (index) => 
                  Container(
                    width: 8,
                    height: 8,
                    margin: EdgeInsets.only(right: index < 2 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_conversation == null)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _createConversation,
                icon: const Icon(Icons.chat),
                label: const Text('Start New Chat'),
              ),
            )
          else ...[
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
                enabled: !_isTyping,
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              onPressed: _isTyping ? null : _sendMessage,
              mini: true,
              child: Icon(_isTyping ? Icons.hourglass_empty : Icons.send),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.settings, size: 24),
              const SizedBox(width: 8),
              const Text('Model Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _hideSettings,
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Model Status
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Current Status', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_status),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Download Progress
          if (_currentDownloadTaskId != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Download Progress', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _downloadProgress / 100),
                    const SizedBox(height: 8),
                    Text('${_downloadProgress.toInt()}% - $_downloadSpeed'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Actions
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isModelLoaded ? null : _downloadModel,
                    icon: const Icon(Icons.download),
                    label: const Text('Download Model (LFM2-350M)'),
                  ),
                ),
                const SizedBox(height: 8),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isModelLoaded ? null : _loadModel,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Load Model'),
                  ),
                ),
                const SizedBox(height: 8),
                
                if (_isModelLoaded) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _unloadModel,
                      icon: const Icon(Icons.eject),
                      label: const Text('Unload Model'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                
                if (_currentDownloadTaskId != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _cancelDownload,
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancel Download'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadModel() async {
    try {
      setState(() {
        _downloadProgress = 0.0;
        _downloadSpeed = '';
      });

      final taskId = await FlutterLeapSdkService.downloadModel(
        modelName: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
        onProgress: (progress) {
          setState(() {
            _downloadProgress = progress.percentage;
            _downloadSpeed = progress.speed;
            
            if (progress.percentage >= 100.0) {
              _currentDownloadTaskId = null;
              _checkModelStatus();
            }
          });
        },
      );

      setState(() {
        _currentDownloadTaskId = taskId;
      });
    } catch (e) {
      _showErrorDialog('Download failed: $e');
    }
  }

  Future<void> _cancelDownload() async {
    if (_currentDownloadTaskId != null) {
      try {
        await FlutterLeapSdkService.cancelDownload(_currentDownloadTaskId!);
        setState(() {
          _currentDownloadTaskId = null;
          _downloadProgress = 0.0;
          _downloadSpeed = '';
        });
      } catch (e) {
        _showErrorDialog('Failed to cancel download: $e');
      }
    }
  }

  Future<void> _loadModel() async {
    try {
      setState(() {
        _status = 'Loading model...';
      });

      await FlutterLeapSdkService.loadModel(
        modelPath: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
      );
      
      await _checkModelStatus();
      
      if (_conversation == null && _isModelLoaded) {
        await _createConversation();
      }
    } catch (e) {
      _showErrorDialog('Failed to load model: $e');
      _checkModelStatus();
    }
  }

  Future<void> _unloadModel() async {
    try {
      await FlutterLeapSdkService.unloadModel();
      setState(() {
        _conversation = null;
        _messages.clear();
      });
      await _checkModelStatus();
    } catch (e) {
      _showErrorDialog('Failed to unload model: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LEAP SDK Chat'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_conversation != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _messages.clear();
                });
                _createConversation();
              },
            ),
        ],
      ),
      body: _showSettings ? _buildSettingsPanel() : _buildChatInterface(),
    );
  }
}