import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:grademate/models/file_models.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:grademate/models/chat_message_model.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

// --- New Models for Unified Chat List ---
abstract class ChatItem {}

class MessageItem extends ChatItem {
  final ChatMessage message;
  MessageItem(this.message);
}

class SeparatorItem extends ChatItem {
  final Timestamp timestamp;
  final String? fileName;
  SeparatorItem({required this.timestamp, this.fileName});
}
// ---

class FacultyAIPage extends StatefulWidget {
  final FileData? initialFile;
  const FacultyAIPage({super.key, this.initialFile});

  @override
  State<FacultyAIPage> createState() => _FacultyAIPageState();
}

class _FacultyAIPageState extends State<FacultyAIPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatItem> _chatItems = [];

  bool _isLoading = false;
  String? _apiKey;

  FileData? _attachedFile;
  String? _extractedFileText;
  File? _downloadedImageFile;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _currentUser;

  // --- State for Pagination & Refresh ---
  DocumentSnapshot? _lastDocumentSnapshot;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  String? _latestSessionId; // To append new messages to the most recent chat

  @override
  void initState() {
    super.initState();
    _loadApiKey();
    _initializeChat();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _removeFile(isDisposing: true);
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
            _scrollController.position.minScrollExtent &&
        !_isLoadingMore &&
        _hasMoreData) {
      _loadConversations();
    }
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _chatItems.clear();
      _lastDocumentSnapshot = null;
      _hasMoreData = true;
      _latestSessionId = null;
      _attachedFile = null;
      _downloadedImageFile = null;
      _extractedFileText = null;
    });
    await _loadConversations(isInitial: true);
  }

  Future<void> _loadApiKey() async {
    await dotenv.load(fileName: ".env");
    if (mounted) {
      setState(() {
        _apiKey = dotenv.env['GEMINI_API_KEY'];
      });
    }
  }

  Future<void> _initializeChat() async {
    _currentUser = _auth.currentUser;
    if (_currentUser == null || _currentUser!.email == null) {
      _showErrorDialog("Authentication Error",
          "You must be logged in with a valid email to use the AI assistant.");
      if (mounted) {
        setState(() {
          _chatItems.add(MessageItem(ChatMessage(
            text: "Could not authenticate user. Please log in again.",
            role: 'model',
            timestamp: Timestamp.now(),
          )));
        });
      }
      return;
    }

    if (widget.initialFile != null) {
      _startNewSessionWithFile(widget.initialFile!);
    } else {
      _loadConversations(isInitial: true);
    }
  }

  Future<void> _loadConversations({bool isInitial = false}) async {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
      if (isInitial) _isLoading = true;
    });

    if (_currentUser == null || _currentUser!.email == null) return;

    Query query = _firestore
        .collection('users')
        .doc(_currentUser!.email)
        .collection('ai')
        .orderBy('createdAt', descending: true)
        .limit(3);

    if (!isInitial && _lastDocumentSnapshot != null) {
      query = query.startAfterDocument(_lastDocumentSnapshot!);
    }

    try {
      final querySnapshot = await query.get();

      if (querySnapshot.docs.isEmpty) {
        if (isInitial && _chatItems.isEmpty) {
          _chatItems.add(MessageItem(ChatMessage(
            text: "Hello! I am your AI Assistant. How can I help you today?",
            role: 'model',
            timestamp: Timestamp.now(),
          )));
        }
        setState(() => _hasMoreData = false);
      } else {
        _lastDocumentSnapshot = querySnapshot.docs.last;
        final newItems = <ChatItem>[];

        if (isInitial) {
          _latestSessionId = querySnapshot.docs.first.id;
        }

        for (final doc in querySnapshot.docs.reversed) {
          final data = doc.data() as Map<String, dynamic>;
          final messagesData =
              List<Map<String, dynamic>>.from(data['messages'] ?? []);

          newItems.add(SeparatorItem(
              timestamp: data['createdAt'] ?? Timestamp.now(),
              fileName: data['fileName']));

          for (final msgMap in messagesData) {
            newItems.add(MessageItem(ChatMessage.fromMap(msgMap)));
          }
        }
        if (mounted) {
          setState(() {
            _chatItems.insertAll(0, newItems);
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error loading conversations: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          if (isInitial) _isLoading = false;
        });
      }
    }
  }

  void _startNewSessionWithFile(FileData file) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleRefresh();
        setState(() {
          _attachedFile = file;
          _isLoading = true;
        });
        final initialMessage = ChatMessage(
          role: 'model',
          text: "Analyzing your file: **${_attachedFile!.name}**... Please wait.",
          timestamp: Timestamp.now(),
        );
        _chatItems.add(MessageItem(initialMessage));
        _saveMessage(initialMessage, isNewSession: true, file: _attachedFile);
        _processFile(_attachedFile!);
      }
    });
  }

  Future<void> _processFile(FileData file) async {
    try {
      final supportedImageTypes = ['jpg', 'jpeg', 'png'];
      final supportedDocTypes = ['doc', 'docx', 'ppt', 'pptx'];
      ChatMessage resultMessage;

      if (file.type == 'pdf') {
        final text = await _extractTextFromPdf(file);
        if (text != null && text.isNotEmpty) {
          _extractedFileText = text;
          resultMessage = ChatMessage(
              role: 'model',
              text: "I've finished reviewing the PDF. How can I help you with it?",
              timestamp: Timestamp.now());
        } else {
          _onFileProcessingError(
              "Sorry, I couldn't extract any text from this PDF.");
          return;
        }
      } else if (supportedImageTypes.contains(file.type)) {
        _downloadedImageFile = await _downloadFile(file);
        resultMessage = ChatMessage(
            role: 'model',
            text: "I've loaded the image. What would you like to know about it?",
            timestamp: Timestamp.now());
      } else if (supportedDocTypes.contains(file.type)) {
        _extractedFileText =
            "The user has attached a file named '${file.name}' of type '${file.type}'.";
        resultMessage = ChatMessage(
            role: 'model',
            text:
                "I've attached the file **${file.name}**. While I can't read its contents directly, feel free to ask me questions about its subject matter!",
            timestamp: Timestamp.now());
      } else {
        _onFileProcessingError(
            "This file type (${file.type}) is not supported for AI analysis.");
        return;
      }

      if (mounted) setState(() => _chatItems.add(MessageItem(resultMessage)));
      await _saveMessage(resultMessage);
    } catch (e) {
      _onFileProcessingError("An error occurred while processing the file: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onFileProcessingError(String message) {
    final errorMessage = ChatMessage(
        role: 'model', text: message, timestamp: Timestamp.now());
    if (mounted) {
      setState(() {
        _chatItems.add(MessageItem(errorMessage));
        _attachedFile = null;
        _extractedFileText = null;
        _downloadedImageFile = null;
      });
    }
    _saveMessage(errorMessage);
  }

  Future<void> _sendMessage() async {
    final userMessageText = _textController.text.trim();
    if (userMessageText.isEmpty || _isLoading) return;
    if (_apiKey == null || _apiKey!.isEmpty) {
      _showErrorDialog("API Key Missing", "GEMINI_API_KEY is not configured.");
      return;
    }
    if (_currentUser == null || _currentUser!.email == null) {
      _showErrorDialog(
          "Authentication Error", "Could not send message. Please log in again.");
      return;
    }

    final userMessage = ChatMessage(
        text: userMessageText, role: 'user', timestamp: Timestamp.now());

    setState(() {
      _chatItems.add(MessageItem(userMessage));
      _isLoading = true;
    });
    _textController.clear();
    _scrollToBottom();

    bool shouldStartNewSession = _latestSessionId == null;
    await _saveMessage(userMessage, isNewSession: shouldStartNewSession);

    if (shouldStartNewSession) {
      await _handleRefresh();
      if(mounted) setState(() => _isLoading = false);
      return;
    }

    final lowerCaseMessage = userMessageText.toLowerCase();
    if (lowerCaseMessage.contains("who are you") ||
        lowerCaseMessage.contains("who developed you") ||
        lowerCaseMessage.contains("who made you")) {
      final identityResponse = ChatMessage(
        text: "I am a Grademate AI, developed by the Grademate team.",
        role: 'model',
        timestamp: Timestamp.now(),
      );
      if (mounted) setState(() => _chatItems.add(MessageItem(identityResponse)));
      await _saveMessage(identityResponse);
    } else {
      ChatMessage modelMessage;
      try {
        final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-05-20:generateContent?key=$_apiKey');
        List<Map<String, dynamic>> parts = [];

        if (_attachedFile != null) {
            if (_downloadedImageFile != null) {
                final imageBytes = await _downloadedImageFile!.readAsBytes();
                String base64Image = base64Encode(imageBytes);
                parts.add({'text': userMessageText});
                parts.add({
                'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image}
                });
            } else if (_extractedFileText != null) {
                String promptForTextBasedFiles = """
                Based on the document content below, please answer the user's request.
                DOCUMENT NAME: ${_attachedFile!.name}
                DOCUMENT CONTENT: --- \n$_extractedFileText\n ---
                USER'S REQUEST: $userMessageText
                """;
                parts.add({'text': promptForTextBasedFiles});
            } else {
                parts.add({'text': userMessageText});
            }
        } else {
            parts.add({'text': userMessageText});
        }
        
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'contents': [{'parts': parts}]}),
        );

        if (!mounted) return;

        if (response.statusCode == 200) {
          final body = json.decode(response.body);
          final modelResponse =
              body['candidates'][0]['content']['parts'][0]['text'];
          modelMessage = ChatMessage(
              text: modelResponse, role: 'model', timestamp: Timestamp.now());
        } else {
          final errorBody = json.decode(response.body);
          final errorMessage =
              errorBody['error']?['message'] ?? 'An unknown error occurred.';
          modelMessage = ChatMessage(
              text: "Sorry, I couldn't get a response. Error: $errorMessage",
              role: 'model',
              timestamp: Timestamp.now());
        }
      } catch (e) {
        modelMessage = ChatMessage(
            text: "Sorry, something went wrong. Please check your internet connection.",
            role: 'model',
            timestamp: Timestamp.now());
      }

      if (mounted) setState(() => _chatItems.add(MessageItem(modelMessage)));
      await _saveMessage(modelMessage);
    }

    if (mounted) setState(() => _isLoading = false);
    _scrollToBottom();
  }

  Future<void> _saveMessage(ChatMessage message, {bool isNewSession = false, FileData? file}) async {
    if (_currentUser == null || _currentUser!.email == null) return;
    final sessionCollection = _firestore.collection('users').doc(_currentUser!.email).collection('ai');

    if (isNewSession || _latestSessionId == null) {
      try {
        final newSessionDoc = await sessionCollection.add({
          'createdAt': Timestamp.now(),
          'fileName': file?.name,
          'fileType': file?.type,
          'messages': [message.toMap()],
        });
        if (mounted) setState(() => _latestSessionId = newSessionDoc.id);
      } catch (e) { if (kDebugMode) print("Error creating new chat session: $e"); }
    } else {
      try {
        await sessionCollection.doc(_latestSessionId).update({
          'messages': FieldValue.arrayUnion([message.toMap()]),
        });
      } catch (e) { if (kDebugMode) print("Error updating chat session: $e"); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: Column(
          children: [
            if (_isLoadingMore)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.all(16.0),
                itemCount: _chatItems.length,
                itemBuilder: (context, index) {
                  final item = _chatItems.reversed.toList()[index];
                  if (item is MessageItem) {
                    return _buildMessageBubble(item.message);
                  }
                  if (item is SeparatorItem) {
                    return _buildSeparator(item);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            if (_isLoading && !_isLoadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: LinearProgressIndicator(),
              ),
            _buildMessageInputField(),
          ],
        ),
      ),
    );
  }

  Widget _buildSeparator(SeparatorItem item) {
    String dateText =
        DateFormat('MMMM d, yyyy').format(item.timestamp.toDate());
    if (item.fileName != null) {
      dateText += "  •  About: ${item.fileName}";
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(dateText,
            style: const TextStyle(color: Colors.black54, fontSize: 12)),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final bool isUser = message.role == 'user';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const CircleAvatar(child: Icon(Icons.auto_awesome)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Markdown(
                data: message.text,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 16),
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(child: Icon(Icons.person_outline)),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInputField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_attachedFile != null) _buildAttachedFilePreview(),
          _buildActionChips(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: _attachedFile != null
                            ? 'Ask about the file...'
                            : 'Ask me anything...',
                        fillColor: Colors.grey.shade100,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _isLoading ? null : _sendMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    // With a reversed list, scrolling to 0 is scrolling to the bottom.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<File?> _downloadFile(FileData file) async {
    try {
      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final safeFileName = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final tempPath = '${tempDir.path}/$safeFileName';
      await dio.download(file.url, tempPath);
      return File(tempPath);
    } catch (e) {
      if (kDebugMode) print("Error downloading file: $e");
      return null;
    }
  }

  Future<String?> _extractTextFromPdf(FileData file) async {
    try {
      final downloadedFile = await _downloadFile(file);
      if (downloadedFile == null) return null;
      final fileBytes = await downloadedFile.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: fileBytes);
      String text = PdfTextExtractor(document).extractText();
      document.dispose();
      await downloadedFile.delete();
      return text;
    } catch (e) {
      if (kDebugMode) print("Error extracting PDF text: $e");
      return null;
    }
  }

  void _removeFile({bool isDisposing = false}) {
    if (!isDisposing && mounted) {
      setState(() {
        if (_attachedFile != null) {
          final removedMessage = ChatMessage(
            role: 'model',
            text: "File **${_attachedFile!.name}** has been removed.",
            timestamp: Timestamp.now(),
          );
          _chatItems.add(MessageItem(removedMessage));
          _saveMessage(removedMessage);
        }
        _attachedFile = null;
        _extractedFileText = null;
      });
    }

    if (_downloadedImageFile != null) {
      _downloadedImageFile!.delete().catchError((e) {
        if (kDebugMode) {
          print("Error deleting temp file: $e");
        }
      });
      _downloadedImageFile = null;
    }
  }

  void _showErrorDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionChips() {
    if (_attachedFile == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildChip("Explain this"),
            _buildChip("Summarize in 3 bullet points"),
            _buildChip("What are the key topics?"),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ActionChip(
        label: Text(label),
        onPressed: _isLoading
            ? null
            : () {
                _textController.text = label;
                _textController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _textController.text.length),
                );
              },
        backgroundColor: Colors.grey.shade100,
        labelStyle: TextStyle(color: Theme.of(context).primaryColor),
      ),
    );
  }

  Widget _buildAttachedFilePreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.05),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          if (_downloadedImageFile != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(_downloadedImageFile!,
                  width: 40, height: 40, fit: BoxFit.cover),
            )
          else
            Icon(Icons.description,
                size: 24, color: Theme.of(context).primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _attachedFile!.name,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColorDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => _removeFile(),
          )
        ],
      ),
    );
  }
}