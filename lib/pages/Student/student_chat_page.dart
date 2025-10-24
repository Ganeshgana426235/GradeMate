import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart'; 
import 'dart:async'; 
import 'package:shimmer/shimmer.dart'; // NEW: Import Shimmer

// --- Global Constants (Assumed from login_page.dart logic) ---
class UserData {
  final String uid;
  final String email;
  final String name; 
  final String role;
  final String collegeId;
  final String branch;
  final String year;
  final String regulation; 

  UserData({
    required this.uid,
    required this.email,
    required this.name, 
    required this.role,
    required this.collegeId,
    required this.branch,
    required this.year,
    required this.regulation,
  });
}

// Enum to define chat types and their display logic
enum ChatType { college, branch, year }

// Enum for message status
enum MessageStatus { sending, delivered, failed }

// Helper class for local message representation (Optimistic UI)
class ChatMessage {
  final String id;
  final Map<String, dynamic> data;
  final MessageStatus status;

  ChatMessage({required this.id, required this.data, this.status = MessageStatus.delivered});
}

// --- Main Chat Page ---

class StudentChatPage extends StatefulWidget {
  const StudentChatPage({super.key});

  @override
  State<StudentChatPage> createState() => _StudentChatPageState();
}

class _StudentChatPageState extends State<StudentChatPage> {
  UserData? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  // Fetches essential user data
  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
       if (mounted) {
         setState(() {
           _isLoading = false;
         });
       }
       return;
    }

    try {
      final userBox = Hive.box<String>('userBox');
      
      // Attempt to load from Hive first
      String? collegeId = userBox.get('collegeId');
      String? branch = userBox.get('branch');
      String? year = userBox.get('year');
      String? regulation = userBox.get('regulation'); 
      String? role = userBox.get('role');
      String? name = userBox.get('name'); // NEW: Get user 'name'

      // If any essential data is missing, fetch from Firestore
      if (collegeId == null || branch == null || year == null || regulation == null || name == null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.email!).get();
        if (doc.exists) {
          final data = doc.data();
          _userData = UserData(
            uid: user.uid,
            email: user.email!,
            name: data?['name'] ?? user.email!.split('@').first, 
            role: data?['role'] ?? 'Student',
            collegeId: data?['collegeId'] ?? 'default',
            branch: data?['branch'] ?? '',
            year: data?['year'] ?? '',
            regulation: data?['regulation'] ?? '', 
          );
          
          // Save to Hive
          userBox.put('collegeId', _userData!.collegeId);
          userBox.put('branch', _userData!.branch);
          userBox.put('year', _userData!.year);
          userBox.put('regulation', _userData!.regulation);
          userBox.put('role', _userData!.role);
          userBox.put('name', _userData!.name); 
          
        } else {
          // Fallback data if user doc not found
          _userData = UserData(
            uid: user.uid, email: user.email!, role: 'Student', name: user.email!.split('@').first,
            collegeId: 'unknown', branch: 'unknown', year: 'unknown', regulation: 'unknown',
          );
        }
      } else {
         _userData = UserData(
          uid: user.uid, email: user.email!, role: role!, name: name!,
          collegeId: collegeId, branch: branch, year: year, regulation: regulation,
        );
      }
    } catch (e) {
      //prin('Error fetching user data for chat: $e');
      // If any error, use fallback data for UI
      _userData = UserData(
            uid: user.uid, email: user.email!, role: 'Student', name: user.email!.split('@').first,
            collegeId: 'error', branch: 'error', year: 'error', regulation: 'error',
          );
    } finally {
      // FIX: Ensure setState is only called if the widget is still mounted
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // Gets the Firestore collection path based on the chat type
  String _getChatPath(ChatType type) {
    if (_userData == null) return 'chats/default/messages';

    // Ensure COLLEGE_ID is lowercase and others are uppercase for path creation
    final college = _userData!.collegeId.toLowerCase();
    final branch = _userData!.branch.toUpperCase(); 
    final year = _userData!.year.toUpperCase();     
    final regulation = _userData!.regulation.toUpperCase(); 

    // Paths follow the user's requirements:
    switch (type) {
      case ChatType.college:
        // Path: /colleges/{collegeId}/chat
        return 'colleges/$college/chat';
      case ChatType.branch:
        // Path: /colleges/{collegeId}/branches/{BRANCHNAME}/chat
        return 'colleges/$college/branches/$branch/chat';
      case ChatType.year:
        // Path: /colleges/{collegeId}/branches/{BRANCHNAME}/regulation/{REGULATION}/year/{YEAR}/chat
        return 'colleges/$college/branches/$branch/regulations/$regulation/years/$year/chat';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine the primary color (light blue)
    const Color primaryChatColor = Color(0xFF87CEEB); 
    
    if (_isLoading) {
      // NEW: Show Shimmer Effect during initial loading
      return const Scaffold(
        appBar: _ChatAppBarShimmer(),
        body: _ChatRoomShimmer(),
      );
    }

    // Display names are kept in original casing for UI readability
    final String collegeName = _userData?.collegeId ?? 'College';
    final String branchName = _userData?.branch ?? 'Branch';
    final String yearName = _userData?.year ?? 'Year';

    // DefaultTabController manages the state for the tabs and TabBarView
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Community Chat',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: primaryChatColor, 
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
            tabs: [
              // 1. College Tab - Shows actual College Name
              Tab(text: collegeName.toUpperCase()),
              // 2. Branch Tab - Shows actual Branch Name
              Tab(text: branchName.toUpperCase()),
              // 3. Year Tab - Shows actual Year Name (or Level)
              Tab(text: yearName.toUpperCase()),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: College Chat
            _ChatRoom(chatPath: _getChatPath(ChatType.college), userData: _userData!, chatType: ChatType.college),
            // Tab 2: Branch Chat
            _ChatRoom(chatPath: _getChatPath(ChatType.branch), userData: _userData!, chatType: ChatType.branch),
            // Tab 3: Year Chat
            _ChatRoom(chatPath: _getChatPath(ChatType.year), userData: _userData!, chatType: ChatType.year),
          ],
        ),
      ),
    );
  }
}

// --- Chat Room Widget (Reusable) ---

class _ChatRoom extends StatefulWidget {
  final String chatPath;
  final UserData userData;
  final ChatType chatType;

  const _ChatRoom({required this.chatPath, required this.userData, required this.chatType});

  @override
  State<_ChatRoom> createState() => __ChatRoomState();
}

class __ChatRoomState extends State<_ChatRoom> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // FIX: Make StreamController nullable and initialize/dispose properly
  StreamController<List<DocumentSnapshot>>? _firestoreMessagesController;

  // State for official Firestore messages loaded so far
  List<DocumentSnapshot> _firestoreMessages = [];
  StreamSubscription<QuerySnapshot>? _chatSubscription;
  bool _isInitialLoad = true;
  
  // NEW: List for messages currently being sent (Optimistic UI)
  List<ChatMessage> _pendingMessages = [];
  
  // Max character limit for chat messages
  static const int _maxMessageLength = 500;

  @override
  void initState() {
    super.initState();
    // Start listening to the chat stream
    _startChatListener();
  }

  @override
  void didUpdateWidget(_ChatRoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart listener if the chat path changes (e.g., user switches tabs)
    if (oldWidget.chatPath != widget.chatPath) {
      _firestoreMessages = [];
      _pendingMessages = []; // Clear pending messages on tab switch
      _isInitialLoad = true;
      _stopChatListener();
      _startChatListener();
    }
  }
  
  // FIX: Refactored logic to correctly manage the StreamController life cycle
  void _startChatListener() {
    // 1. Create a new controller
    _firestoreMessagesController = StreamController<List<DocumentSnapshot>>.broadcast();
    
    final Query baseQuery = FirebaseFirestore.instance
        .collection(widget.chatPath)
        .orderBy('timestamp', descending: true)
        .limit(30);

    // Initial load state: Added mounted check
    baseQuery.get().then((initialSnapshot) {
      if (mounted) { 
         _firestoreMessages = initialSnapshot.docs.reversed.toList();
         _firestoreMessagesController!.add(_firestoreMessages); // Use ! for non-nullable access
         setState(() {
            _isInitialLoad = false;
         });
         WidgetsBinding.instance.addPostFrameCallback((_) {
            // FIX: Check mounted before scrolling, which uses context/controller
            if (mounted) _scrollToBottom();
         });
      }
    }).catchError((error) {
       //prin('Firestore Initial Load Error: $error');
       if (mounted) { 
          setState(() {
             _isInitialLoad = false;
          });
          _firestoreMessagesController!.add([]); // Use ! for non-nullable access
       }
    });

    // Start the continuous listener for updates
    _chatSubscription = baseQuery.snapshots(includeMetadataChanges: true).listen(
      (snapshot) {
        // FIX: Check mounted and ensure controller exists before adding data
        if (mounted && !_isInitialLoad && _firestoreMessagesController != null && !_firestoreMessagesController!.isClosed) { 
          
          bool addedNewMessage = false;
          
          for (var change in snapshot.docChanges) {
            final docId = change.doc.id;
            
            // 1. Handle addition of a new, *confirmed* message
            if (change.type == DocumentChangeType.added) {
              
              final pendingIndex = _pendingMessages.indexWhere((m) => m.id == docId);
              
              if (pendingIndex != -1) {
                // Message confirmed (sent by current user): Remove pending local message
                setState(() {
                  _pendingMessages.removeAt(pendingIndex);
                });
                
              } else if (!_firestoreMessages.any((doc) => doc.id == docId)) {
                // Message confirmed (sent by *other* user): Add to confirmed list
                _firestoreMessages.add(change.doc);
                addedNewMessage = true; // Mark to scroll down
              }
            }
            // 2. Handle modification (Edit)
            if (change.type == DocumentChangeType.modified) {
               final index = _firestoreMessages.indexWhere((doc) => doc.id == docId);
               if (index != -1) {
                 _firestoreMessages[index] = change.doc;
               }
            }
            // 3. Handle deletion
            if (change.type == DocumentChangeType.removed) {
               _firestoreMessages.removeWhere((doc) => doc.id == docId);
            }
          }
          
          // Re-sort and update stream
          _firestoreMessages.sort((a, b) {
            final aTime = (a.data() as Map<String, dynamic>?)?['timestamp'] as Timestamp?;
            final bTime = (b.data() as Map<String, dynamic>?)?['timestamp'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return aTime.compareTo(bTime);
          });
          
          _firestoreMessagesController!.add(_firestoreMessages);
          
          // Scroll to bottom only if a new message was added by another user
          if (addedNewMessage) {
             WidgetsBinding.instance.addPostFrameCallback((_) {
                 // FIX: Check mounted before scrolling
                 if (mounted) _scrollToBottom(); 
             });
          }
        }
      },
      onError: (error) {
        //prin('Firestore Listener Error: $error');
        // Do not update the UI if the listener throws an error after initial load
      },
    );
  }
  
  // FIX: Clear and close the StreamController properly
  void _stopChatListener() {
    _chatSubscription?.cancel();
    _chatSubscription = null;
    if (_firestoreMessagesController != null && !_firestoreMessagesController!.isClosed) {
      _firestoreMessagesController!.add([]); // Clear existing messages
      _firestoreMessagesController!.close();
    }
    _firestoreMessagesController = null; // Set to null after closing
  }

  // NEW: Function to delete a message
  Future<void> _deleteMessage(String docId) async {
    try {
      await FirebaseFirestore.instance.collection(widget.chatPath).doc(docId).delete();
      // Deletion success is handled by the listener removing the doc from _firestoreMessages.
    } catch (e) {
      //prin('Error deleting message $docId: $e');
      if (mounted) { // FIX: Added mounted check
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete message.')),
        );
      }
    }
  }
  
  // NEW: Function to edit a message
  Future<void> _editMessage(String docId, String newText) async {
    try {
      await FirebaseFirestore.instance.collection(widget.chatPath).doc(docId).update({
        'text': newText,
        'edited': true,
      });
    } catch (e) {
      //prin('Error editing message $docId: $e');
      if (mounted) { // FIX: Added mounted check
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to edit message.')),
        );
      }
    }
  }

  // NEW: Dialog for editing message (unchanged)
  void _showEditDialog(String docId, String currentText) {
    final TextEditingController editController = TextEditingController(text: currentText);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Message'),
          content: TextField(
            controller: editController,
            maxLength: _maxMessageLength,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(hintText: "Enter new message"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Save'),
              onPressed: () {
                final newText = editController.text.trim();
                if (newText.isNotEmpty && newText.length <= _maxMessageLength) {
                  _editMessage(docId, newText);
                  Navigator.of(context).pop();
                } else if (newText.length > _maxMessageLength) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                   ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Message exceeds limit of $_maxMessageLength characters.')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Sends the message to the specified Firestore collection
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    if (text.length > _maxMessageLength) {
       if (mounted) { // FIX: Added mounted check
       ScaffoldMessenger.of(context).hideCurrentSnackBar();
         ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Message exceeds the maximum limit of $_maxMessageLength characters.')),
          );
       }
        return;
    }

    final String tempId = DateTime.now().millisecondsSinceEpoch.toString();

    // 1. Prepare data (LOWERCASE/UPPERCASE consistency is crucial for security rules)
    final Map<String, dynamic> messageData = {
        'text': text,
        'senderId': widget.userData.uid,
        'senderEmail': widget.userData.email,
        'name': widget.userData.name, 
        'role': widget.userData.role,
        'collegeId': widget.userData.collegeId.toLowerCase(), 
        'branch': widget.userData.branch.toUpperCase(),       
        'year': widget.userData.year.toUpperCase(),           
        'regulation': widget.userData.regulation.toUpperCase(), 
        'timestamp': Timestamp.fromDate(DateTime.now()), // Local timestamp for optimistic display
    };
    
    // 2. Optimistic Update: Add to local pending list
    setState(() {
      _pendingMessages.add(ChatMessage(
        id: tempId,
        data: messageData,
        status: MessageStatus.sending,
      ));
    });
    _messageController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom(); // FIX: Added mounted check
    });

    // 3. Attempt to send to Firestore
    try {
      await FirebaseFirestore.instance.collection(widget.chatPath).add(messageData);
      // Success: The listener will handle removal from _pendingMessages and addition to _firestoreMessages
      
    } catch (e) {
      //prin('Error sending message: $e');
      // Failure: Update status of the pending message
      if (mounted) { // FIX: Added mounted check
        setState(() {
          final index = _pendingMessages.indexWhere((m) => m.id == tempId);
          if (index != -1) {
            _pendingMessages[index] = ChatMessage(
              id: tempId,
              data: messageData,
              status: MessageStatus.failed, // Mark as failed
            );
          }
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message. Tap to retry.')),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _stopChatListener();
    // No need to close the controller here as it's closed in _stopChatListener
    super.dispose();
  }

  // Combines Firestore messages and pending messages for display
  List<ChatMessage> _getDisplayMessages() {
    final List<ChatMessage> displayList = [];

    // Add confirmed Firestore messages
    for (var doc in _firestoreMessages) {
      displayList.add(ChatMessage(id: doc.id, data: doc.data() as Map<String, dynamic>, status: MessageStatus.delivered));
    }

    // Add pending/failed messages
    displayList.addAll(_pendingMessages);
    
    // Final sort by timestamp (Firestore messages have official timestamp, pending use local timestamp)
    displayList.sort((a, b) {
      final aTime = a.data['timestamp'] is Timestamp 
          ? (a.data['timestamp'] as Timestamp).toDate() 
          : a.data['timestamp'] as DateTime;
      final bTime = b.data['timestamp'] is Timestamp 
          ? (b.data['timestamp'] as Timestamp).toDate() 
          : b.data['timestamp'] as DateTime;
      
      return aTime.compareTo(bTime);
    });

    return displayList;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Message Stream Area
        Expanded(
          // FIX: Access the stream controller only if it is not null
          child: StreamBuilder<List<DocumentSnapshot>>(
            stream: _firestoreMessagesController?.stream,
            builder: (context, snapshot) {
              
              if (_isInitialLoad || _firestoreMessagesController == null) {
                // Show shimmer while the initial data fetch is pending
                return const _ChatRoomShimmer();
              }
              
              final messages = _getDisplayMessages();

              if (messages.isEmpty && _pendingMessages.isEmpty) {
                // NEW: Empty state widget
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Start a new conversation in ${widget.chatType.name.toUpperCase()}!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Messages are visible to all ${widget.chatType.name.toUpperCase()} peers.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  
                  final chatMessage = messages[index];
                  final isMe = chatMessage.data['senderId'] == widget.userData.uid;
                  
                  return _MessageBubble(
                    chatMessage: chatMessage,
                    isMe: isMe,
                    chatType: widget.chatType,
                    onDelete: _deleteMessage, 
                    onEdit: _showEditDialog, 
                    onRetry: _sendMessage, 
                  );
                },
              );
            },
          ),
        ),
        
        // 2. Input Field Area
        Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                spreadRadius: 1,
                blurRadius: 5,
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    maxLength: _maxMessageLength, // Max length limit
                    maxLines: null, // Allows multi-line input
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: 'Send a message (Max ${_maxMessageLength} chars)...',
                      counterText: '', // Hide default counter text
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25.0),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8.0),
                CircleAvatar(
                  backgroundColor: const Color(0xFF87CEEB),
                  radius: 24,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


// --- Individual Message Bubble Widget ---

class _MessageBubble extends StatelessWidget {
  final ChatMessage chatMessage; // Use the combined message object
  final bool isMe;
  final ChatType chatType;
  final void Function(String) onDelete;
  final void Function(String, String) onEdit;
  final void Function()? onRetry; // New callback for failed messages

  const _MessageBubble({
    required this.chatMessage,
    required this.isMe,
    required this.chatType,
    required this.onDelete,
    required this.onEdit,
    this.onRetry,
  });

  // Helper to format the time
  String _formatTime() {
    final timestamp = chatMessage.data['timestamp'];
    if (timestamp == null) return '';
    final date = timestamp is Timestamp ? timestamp.toDate() : timestamp as DateTime;
    return DateFormat('h:mm a').format(date);
  }

  // Helper to truncate year string to first 3 characters
  String _truncateYear(String year) {
    if (year.length > 3) {
      return year.substring(0, 3);
    }
    return year;
  }
  
  // Helper to format the sender display text based on chat type and role
  String _getSenderDetails() {
    final String name = chatMessage.data['name'] ?? 'Unknown User'; 
    final String role = chatMessage.data['role'] ?? 'Unknown Role';
    final String branch = (chatMessage.data['branch'] ?? 'N/A').toUpperCase();
    final String year = (chatMessage.data['year'] ?? 'N/A').toUpperCase();
    
    if (isMe) {
      return 'You';
    }
    
    // --- FINAL CHANGE: Faculty Role Logic ---
    if (role.toUpperCase() == 'FACULTY') {
      // Faculty: Only show name - role
      return '$name - $role';
    }
    
    // --- Student/Other Role Logic ---
    
    String displayRole = role;
    String displayBranch = branch;
    String displayYear = year;
    
    // Apply requested year truncation for student view
    displayYear = _truncateYear(year);

    switch (chatType) {
      case ChatType.college:
        // College Tab (Student View): name - role | branch - year
        return '$name - $displayRole | $displayBranch - $displayYear';
      case ChatType.branch:
        // Branch Tab (Student View): name (role) | year
        return '$name ($displayRole) | $displayYear';
      case ChatType.year:
        // Year Tab (Student View): name (role) | year
        return '$name ($displayRole) | $displayYear';
    }
  }

  // Shows the edit/delete options on long press
  void _showOptions(BuildContext context) {
    // Only show options if the message has been delivered (has a confirmed ID)
    if (chatMessage.status != MessageStatus.delivered) return;
    
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Message'),
                onTap: () {
                  Navigator.pop(context);
                  onEdit(chatMessage.id, chatMessage.data['text'] ?? '');
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete Message', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete(chatMessage.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = chatMessage.data['text'] ?? '';
    final isEdited = chatMessage.data['edited'] == true;
    
    Widget bubbleContent = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              color: isMe ? Colors.white : Colors.black87,
              fontSize: 15,
            ),
          ),
          if (isEdited)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                '(edited)',
                style: TextStyle(
                  color: isMe ? Colors.white70 : Colors.grey[600],
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
    
    // Wrap with GestureDetector only if it's the current user's message
    if (isMe) {
      bubbleContent = GestureDetector(
        onLongPress: () => _showOptions(context),
        child: bubbleContent,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Sender Info and Time
          Row(
            // FIX: Use MainAxisAlignment.start instead of CrossAxisAlignment.start
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Display sender details
              Flexible(
                child: Text(
                  _getSenderDetails(), 
                  overflow: TextOverflow.ellipsis, // Ensures overflow protection
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isMe ? Colors.grey[600] : Colors.grey[700],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Timestamp
              Text(
                _formatTime(),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Message Bubble
          Material(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16.0),
              topRight: const Radius.circular(16.0),
              bottomLeft: isMe ? const Radius.circular(16.0) : const Radius.circular(4.0),
              bottomRight: isMe ? const Radius.circular(4.0) : const Radius.circular(16.0),
            ),
            elevation: 3,
            color: isMe ? const Color(0xFF87CEEB).withOpacity(0.9) : Colors.grey[200],
            child: bubbleContent,
          ),
          
          // NEW: Status Indicator (Only for current user's messages)
          if (isMe)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, right: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (chatMessage.status == MessageStatus.sending)
                    Icon(Icons.access_time, size: 12, color: Colors.grey[500]),
                  if (chatMessage.status == MessageStatus.delivered)
                    Icon(Icons.check, size: 12, color: Colors.blue[800]),
                  if (chatMessage.status == MessageStatus.failed)
                    GestureDetector(
                      onTap: onRetry,
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 12, color: Colors.red),
                          const SizedBox(width: 4),
                          const Text('Failed. Tap to retry.', style: TextStyle(fontSize: 10, color: Colors.red)),
                        ],
                      ),
                    ),
                  SizedBox(width: chatMessage.status == MessageStatus.failed ? 0 : 4),
                  if (chatMessage.status != MessageStatus.failed)
                    Text(
                      chatMessage.status == MessageStatus.sending ? 'Sending...' : 'Delivered',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// --- NEW SHIMMER WIDGETS ---

class _ChatAppBarShimmer extends StatelessWidget implements PreferredSizeWidget {
  const _ChatAppBarShimmer();
  
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: AppBar(
        backgroundColor: Colors.white,
        title: Container(
          width: 150,
          height: 20,
          color: Colors.white,
        ),
        bottom: TabBar(
          indicatorColor: Colors.transparent,
          tabs: List.generate(3, (index) => 
            Tab(
              child: Container(
                width: 80,
                height: 14,
                color: Colors.white,
              )
            )
          ),
        ),
      ),
    );
  }
  
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + kTextTabBarHeight);
}

class _ChatRoomShimmer extends StatelessWidget {
  const _ChatRoomShimmer();
  
  Widget _buildBubblePlaceholder({required bool isMe}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Sender Info Placeholder
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Container(width: 100, height: 12, color: Colors.white),
              const SizedBox(width: 8),
              Container(width: 40, height: 10, color: Colors.white),
            ],
          ),
          const SizedBox(height: 4),
          
          // Message Content Placeholder
          Container(
            width: isMe ? 220 : 180,
            height: 35,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16.0),
                topRight: const Radius.circular(16.0),
                bottomLeft: isMe ? const Radius.circular(16.0) : const Radius.circular(4.0),
                bottomRight: isMe ? const Radius.circular(4.0) : const Radius.circular(16.0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: 10,
        reverse: true, // Simulate messages appearing from the bottom
        itemBuilder: (context, index) {
          // Alternate sides for chat bubbles
          final isMe = index % 2 == 0;
          return _buildBubblePlaceholder(isMe: isMe);
        },
      ),
    );
  }
}
