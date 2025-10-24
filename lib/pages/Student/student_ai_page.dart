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
import 'package:google_mobile_ads/google_mobile_ads.dart'; // NEW: Google Mobile Ads SDK
import 'package:google_fonts/google_fonts.dart'; // NEW: For consistent styling

// Color constant inferred from student_home_page.dart
const Color _kPrimaryColor = Color(0xFF6A67FE);

// --- UPDATED QUOTA CONSTANTS ---
const int _kFreeTextPromptsPerDay = 10; // Changed from 3 to 10
const int _kRewardTextPrompts = 5;      // Changed from 3 to 5
const int _kFreeFilePromptsPerDay = 5;  // New constant
const int _kRewardFilePrompts = 3;      // New constant for file reward

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

class StudentAIPage extends StatefulWidget {
  final FileData? initialFile;
  const StudentAIPage({super.key, this.initialFile});

  @override
  State<StudentAIPage> createState() => _StudentAIPageState();
}

class _StudentAIPageState extends State<StudentAIPage> {
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

  // --- NEW Quota and Ad State ---
  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  final String _rewardedAdUnitId = Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/5224354917' // Android Test ID
      : 'ca-app-pub-3940256099942544/1712485360'; // iOS Test ID

  int _freeTextPromptCount = 0; // UPDATED: State for Text Prompts
  int _freeFilePromptCount = 0; // NEW: State for File Prompts
  DateTime? _lastQuotaResetDate;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
    _initializeChat();
    _scrollController.addListener(_onScroll);
    _loadRewardedAd();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _removeFile(isDisposing: true);
    _rewardedAd?.dispose(); // NEW: Dispose ad
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
    // Ensure quota is reloaded on refresh
    await _loadUserQuota();
    await _loadConversations(isInitial: true);
    _showSnackbar("Chat reloaded.", success: true);
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

    await _loadUserQuota(); // NEW: Load quota before loading conversations

    if (widget.initialFile != null) {
      _startNewSessionWithFile(widget.initialFile!);
    } else {
      _loadConversations(isInitial: true);
    }
  }
  
  // --- UPDATED Quota Management Methods ---

  Future<void> _loadUserQuota() async {
    if (_currentUser == null || _currentUser!.email == null) return;
    
    final quotaRef = _firestore.collection('users').doc(_currentUser!.email).collection('settings').doc('ai_quota');
    final now = DateTime.now();
    
    try {
        final doc = await quotaRef.get();
        
        if (doc.exists) {
            final data = doc.data()!;
            int textCount = data['textCount'] ?? 0;
            int fileCount = data['fileCount'] ?? 0; // NEW
            Timestamp? lastResetTimestamp = data['lastReset'] as Timestamp?;
            DateTime? lastResetDate = lastResetTimestamp?.toDate();
            
            bool shouldReset = lastResetDate == null ||
                lastResetDate.year != now.year ||
                lastResetDate.month != now.month ||
                lastResetDate.day != now.day;
            
            if (shouldReset) {
                // Reset quotas to their free limits
                await quotaRef.set({
                    'textCount': _kFreeTextPromptsPerDay,
                    'fileCount': _kFreeFilePromptsPerDay, // NEW
                    'lastReset': Timestamp.now(),
                });
                textCount = _kFreeTextPromptsPerDay;
                fileCount = _kFreeFilePromptsPerDay;
                lastResetDate = now;
            }

            if(mounted) {
                setState(() {
                    _freeTextPromptCount = textCount;
                    _freeFilePromptCount = fileCount; // NEW
                    _lastQuotaResetDate = lastResetDate;
                });
            }
        } else {
            // Document does not exist, create it with initial free quota
            await quotaRef.set({
                'textCount': _kFreeTextPromptsPerDay,
                'fileCount': _kFreeFilePromptsPerDay, // NEW
                'lastReset': Timestamp.now(),
            });
            if(mounted) {
                setState(() {
                    _freeTextPromptCount = _kFreeTextPromptsPerDay;
                    _freeFilePromptCount = _kFreeFilePromptsPerDay; // NEW
                    _lastQuotaResetDate = now;
                });
            }
        }
    } catch (e) {
        if (kDebugMode) //print("Error loading user quota: $e");
        if(mounted) {
            setState(() {
                _freeTextPromptCount = 0;
                _freeFilePromptCount = 0;
            });
        }
    }
  }

  Future<void> _decrementPromptCount({required bool isFilePrompt}) async {
    if (_currentUser == null || _currentUser!.email == null) return;
    
    final quotaRef = _firestore.collection('users').doc(_currentUser!.email).collection('settings').doc('ai_quota');
    
    String fieldToDecrement = isFilePrompt ? 'fileCount' : 'textCount';
    
    try {
        await quotaRef.update({
            fieldToDecrement: FieldValue.increment(-1),
        });
        if(mounted) {
            setState(() {
                if (isFilePrompt) {
                    _freeFilePromptCount -= 1;
                } else {
                    _freeTextPromptCount -= 1;
                }
            });
        }
    } catch (e) {
        if (kDebugMode) print("Error decrementing quota: $e");
    }
  }

  Future<void> _grantPrompts({required int count, required bool isFilePrompt}) async {
    if (_currentUser == null || _currentUser!.email == null) return;

    final quotaRef = _firestore.collection('users').doc(_currentUser!.email).collection('settings').doc('ai_quota');
    
    String fieldToIncrement = isFilePrompt ? 'fileCount' : 'textCount';

    try {
        await quotaRef.update({
            fieldToIncrement: FieldValue.increment(count),
        });
        if(mounted) {
            setState(() {
                if (isFilePrompt) {
                    _freeFilePromptCount += count;
                } else {
                    _freeTextPromptCount += count;
                }
            });
        }
        _showSnackbar("$count extra prompts granted!", success: true);
    } catch (e) {
        if (kDebugMode) print("Error granting quota: $e");
    }
  }

  // --- NEW Rewarded Ad Logic ---

  void _loadRewardedAd() {
    RewardedAd.load(
        adUnitId: _rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: (ad) {
                if (!mounted) {
                    ad.dispose();
                    return;
                }
                setState(() {
                    _rewardedAd = ad;
                    _isAdLoaded = true;
                });
            },
            onAdFailedToLoad: (error) {
                if (kDebugMode) print('RewardedAd failed to load: $error');
                setState(() => _isAdLoaded = false);
            },
        ),
    );
  }

  void _showRewardedAd(Function(bool isFilePrompt) onAdWatched, bool isFilePrompt) {
    if (_rewardedAd == null) {
        _showErrorDialog("Ad Not Ready", "The rewarded ad is not loaded yet. Please try again in a moment.");
        _loadRewardedAd();
        return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            _rewardedAd = null;
            _isAdLoaded = false;
            _loadRewardedAd(); // Load the next ad
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
            ad.dispose();
            _rewardedAd = null;
            _isAdLoaded = false;
            _loadRewardedAd(); // Load the next ad
            _showErrorDialog("Ad Error", "Failed to show ad. Please try again.");
            if (kDebugMode) print('Rewarded ad failed to show: $error');
        },
    );

    _rewardedAd!.show(onUserEarnedReward: (ad, reward) {
        // Reward the user only after they successfully watch the ad
        onAdWatched(isFilePrompt);
    });
  }


  Future<void> _loadConversations({bool isInitial = false}) async {
    // ... existing logic ...
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
      if (isInitial) _isLoading = true;
    });

    if (_currentUser == null || _currentUser!.email == null) return;
    
    // ... existing query logic ...

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
          // Display initial welcome message only if there are no existing chat items
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
          // Set the latest session ID only if we successfully loaded chat history
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
        // Force a new session creation here
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
  
  // --- FIXED: The required _sendMessage function (Entry Point) ---
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
    
    // Set loading state right away.
    if(mounted) setState(() => _isLoading = true);
    _textController.clear();
    _scrollToBottom();
    
    // **FIX APPLIED HERE:**
    // Removed the check that forced a refresh and showed the "Session Error" dialog
    // if (_latestSessionId == null). The logic now proceeds directly to the
    // quota check and execution, allowing the core function to create the session.
    
    // Handle Quota/Ad check
    await _handleQuotaAndSend(userMessageText);
    
    // _isLoading will be reset by _executeSendMessage's finally block
  }
  // --- END FIXED: _sendMessage function ---

  // --- UPDATED Quota and Ad Check Handler ---
  Future<void> _handleQuotaAndSend(String userMessageText) async {
    final bool isFilePrompt = _attachedFile != null;
    
    if (isFilePrompt) {
        // 1. File Prompt Logic
        if (_freeFilePromptCount > 0) {
            await _decrementPromptCount(isFilePrompt: true);
            await _executeSendMessage(userMessageText);
        } else {
            // Quota depleted, require ad for more file prompts
            _showAdPromptDialog(
                title: "Run out of file prompts!",
                content: "You have used your daily free file prompts. Watch a short rewarded ad to get $_kRewardFilePrompts more file prompts.",
                onConfirm: () {
                    _showRewardedAd(
                        (bool isFile) {
                            _grantPrompts(count: _kRewardFilePrompts, isFilePrompt: true);
                            _executeSendMessage(userMessageText); // Immediately run the current message after getting the reward
                        },
                        true // isFilePrompt
                    );
                },
            );
        }
    } else {
        // 2. Text Prompt Logic
        if (_freeTextPromptCount > 0) {
            await _decrementPromptCount(isFilePrompt: false);
            await _executeSendMessage(userMessageText);
        } else {
            // Quota depleted, require ad for more text prompts
            _showAdPromptDialog(
                title: "Run out of text prompts!",
                content: "You have used your daily free prompts. Watch a short rewarded ad to get $_kRewardTextPrompts more text prompts.",
                onConfirm: () {
                    _showRewardedAd(
                        (bool isFile) {
                            _grantPrompts(count: _kRewardTextPrompts, isFilePrompt: false);
                            _executeSendMessage(userMessageText); // Immediately run the current message after getting the reward
                        },
                        false // isFilePrompt
                    );
                },
            );
        }
    }
  }

  // Renamed core logic for message generation and API call
  Future<void> _executeSendMessage(String userMessageText) async {
    final userMessage = ChatMessage(
        text: userMessageText, role: 'user', timestamp: Timestamp.now());
    
    // Add user message to UI immediately
    if (mounted) setState(() => _chatItems.add(MessageItem(userMessage)));
    _scrollToBottom();

    // Save the user message and ensure session ID is set (or was already set).
    // isNewSession will be true if _latestSessionId is null (first message for a new user).
    bool shouldStartNewSession = _latestSessionId == null; 
    await _saveMessage(userMessage, isNewSession: shouldStartNewSession);

    // After save, _latestSessionId *must* be set, either from loading history or from creating the new document.
    if (_latestSessionId == null) {
        // This is a last-resort error, indicating Firestore failed to create the session document.
        if (mounted) setState(() => _isLoading = false);
        _showErrorDialog("Firestore Error", "Failed to establish a chat session. Please check your network and refresh.");
        return;
    }

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

      // Update UI and save model response
      if (mounted) setState(() => _chatItems.add(MessageItem(modelMessage)));
      await _saveMessage(modelMessage);

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
        // IMPORTANT: Set the new session ID after creation
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
        actions: [
          // NEW: Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _isLoading ? null : _handleRefresh,
            tooltip: 'Reload Chat',
          ),
        ],
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
                child: LinearProgressIndicator(color: _kPrimaryColor),
              ),
            _buildMessageInputField(),
          ],
        ),
      ),
    );
  }
  
  // --- UPDATED Quota Display Widget ---
  Widget _buildQuotaDisplay() {
    final bool hasFile = _attachedFile != null;
    final int textCount = _freeTextPromptCount;
    final int fileCount = _freeFilePromptCount;

    String quotaText;
    Color textColor;
    Color bgColor;

    if (hasFile) {
        quotaText = "File Prompts Remaining: $fileCount";
        if (fileCount <= 0) {
            quotaText = "Out of File Prompts! Watch an ad for $_kRewardFilePrompts more.";
            textColor = Colors.red.shade700;
            bgColor = Colors.red.shade50;
        } else {
            textColor = Colors.blue.shade700;
            bgColor = Colors.blue.shade50;
        }
    } else {
        quotaText = "Text Prompts Remaining: $textCount";
        if (textCount <= 0) {
            quotaText = "Out of Text Prompts! Watch an ad for $_kRewardTextPrompts more.";
            textColor = Colors.red.shade700;
            bgColor = Colors.red.shade50;
        } else {
            textColor = Colors.green.shade700;
            bgColor = Colors.green.shade50;
        }
    }


    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      margin: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: textColor.withOpacity(0.3))
      ),
      child: Row(
        children: [
          Icon(hasFile ? Icons.attach_file : Icons.text_fields, size: 20, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              quotaText,
              style: GoogleFonts.inter(
                color: textColor,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          // Ad button if quotas are depleted
          if (hasFile ? fileCount <= 0 : textCount <= 0)
              ElevatedButton.icon(
                onPressed: _isAdLoaded
                    ? () {
                        // Show Ad Dialog directly from the display widget for quick access
                        _showAdPromptDialog(
                            title: hasFile ? "Watch Ad for File Prompts" : "Watch Ad for Text Prompts",
                            content: hasFile 
                                ? "Watch a short rewarded ad to get $_kRewardFilePrompts file prompts."
                                : "Watch a short rewarded ad to get $_kRewardTextPrompts text prompts.",
                            onConfirm: () {
                                _showRewardedAd(
                                    (bool isFile) {
                                        _grantPrompts(
                                            count: isFile ? _kRewardFilePrompts : _kRewardTextPrompts,
                                            isFilePrompt: isFile,
                                        );
                                    },
                                    hasFile // isFilePrompt
                                );
                            },
                        );
                    }
                    : null,
                icon: Icon(_isAdLoaded ? Icons.play_arrow : Icons.sync, size: 16, color: Colors.white),
                label: Text(_isAdLoaded ? 'Get Free Prompts' : 'Loading...', style: GoogleFonts.inter(fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
        ],
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
            const CircleAvatar(child: Icon(Icons.auto_awesome, color: _kPrimaryColor)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? _kPrimaryColor
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Markdown(
                data: message.text,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                styleSheet: MarkdownStyleSheet(
                  p: GoogleFonts.inter(
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
          // NEW: Quota Display
          _buildQuotaDisplay(),
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
                      backgroundColor: _kPrimaryColor,
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

  void _showSnackbar(String message, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: success ? Colors.green : Colors.red),
    );
  }

  // NEW: Dialog to prompt user to watch an ad
  Future<void> _showAdPromptDialog({
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _kPrimaryColor)),
          content: Text(content, style: GoogleFonts.inter(fontSize: 15, color: Colors.black87)),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss dialog
                if (mounted) setState(() => _isLoading = false); // Stop loading if cancelled
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: _isAdLoaded
                  ? () {
                      Navigator.of(context).pop(); // Dismiss dialog
                      onConfirm();
                    }
                  : null, // Disable if ad is not loaded
              icon: Icon(_isAdLoaded ? Icons.play_arrow : Icons.sync, color: Colors.white),
              label: Text(_isAdLoaded ? 'Watch Rewarded Ad' : 'Loading Ad...', style: GoogleFonts.inter(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        );
      },
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