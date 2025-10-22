import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart'; // Unused, but kept for context consistency
import 'package:intl/intl.dart'; 
import 'dart:async'; 
import 'package:shimmer/shimmer.dart'; 
import 'dart:math';
import 'package:flutter/foundation.dart'; 

// --- Global Constants (Assumed from login_page.dart logic) ---
const Color _kPrimaryChatColor = Color(0xFF6A67FE); 

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

// Enum to define chat types (Only College remains)
enum ChatType { college }

// Enum for message status
enum MessageStatus { sending, delivered, failed }

// Helper class for local message representation (Optimistic UI)
class ChatMessage {
  final String id;
  final Map<String, dynamic> data;
  final MessageStatus status;

  ChatMessage({required this.id, required this.data, this.status = MessageStatus.delivered});
}

// --- Main Faculty Chat Page (Simplified to single chat) ---

class FacultyChatPage extends StatefulWidget {
  const FacultyChatPage({super.key});

  @override
  State<FacultyChatPage> createState() => _FacultyChatPageState();
}

// NOTE: SingleTickerProviderStateMixin is REMOVED as TabController is no longer used.
class _FacultyChatPageState extends State<FacultyChatPage> {
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  UserData? _userData;
  bool _isLoading = true;
  
  // Removed all branch/tab related state variables
  
  @override
  void initState() {
    super.initState();
    _fetchUserData(); // Simplified initial load function
  }
  
  // Fetches essential user data for the chat path
  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
       if (mounted) setState(() => _isLoading = false);
       return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.email!).get();
      if (!userDoc.exists) throw Exception("User data not found.");

      final data = userDoc.data();
      _userData = UserData(
        uid: user.uid,
        email: user.email!,
        name: data?['name'] ?? user.email!.split('@').first, 
        role: data?['role'] ?? 'Faculty',
        collegeId: data?['collegeId'] ?? 'default',
        branch: data?['branch'] ?? '', 
        year: data?['year'] ?? '',
        regulation: data?['regulation'] ?? '', 
      );
      
    } catch (e) {
      if (kDebugMode) print('Error fetching faculty user data: $e');
      _showSnackbar('Failed to load user data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  void _showSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // Gets the Firestore collection path for the College chat
  String _getChatPath() {
    if (_userData == null) {
      return 'colleges/default/chat'; 
    }
    // Path: /colleges/{collegeId}/chat
    final college = _userData!.collegeId.toLowerCase();
    return 'colleges/$college/chat';
  }

  @override
  Widget build(BuildContext context) {
    
    // College name is extracted once
    final String collegeName = _userData?.collegeId ?? 'College';
    
    if (_isLoading) {
      // Use the shimmer without the TabBar
      return Scaffold(
        appBar: AppBar(
          title: const Text('Faculty Chat', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: _kPrimaryChatColor,
          elevation: 0,
        ),
        body: const _ChatRoomShimmer(),
      );
    }
    
    if (_userData == null) {
       return Scaffold(
         appBar: AppBar(title: const Text('Faculty Chat'), backgroundColor: _kPrimaryChatColor),
         body: const Center(child: Text("Error: User data is unavailable.", style: TextStyle(color: Colors.red))),
       );
    }


    // Simplified UI for a single chat room
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'College Chat (${collegeName.toUpperCase()})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _kPrimaryChatColor, 
        elevation: 0,
      ),
      // Only display the single ChatRoom widget
      body: _ChatRoom(
        chatPath: _getChatPath(), 
        userData: _userData!, 
        chatType: ChatType.college, // Fixed to college chat type
        emptyMessage: 'Start a conversation with all faculty and students in ${collegeName}!',
      ),
    );
  }
}

// --- Chat Room Widget (Reusable) ---

class _ChatRoom extends StatefulWidget {
  final String chatPath;
  final UserData userData;
  final ChatType chatType;
  final String emptyMessage; // Custom empty state message

  const _ChatRoom({
    required this.chatPath, 
    required this.userData, 
    required this.chatType,
    required this.emptyMessage,
  });

  @override
  State<_ChatRoom> createState() => __ChatRoomState();
}

class __ChatRoomState extends State<_ChatRoom> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Use a StreamController to manually manage the stream source
  final StreamController<List<DocumentSnapshot>> _firestoreMessagesController = 
      StreamController<List<DocumentSnapshot>>.broadcast();

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
    _startChatListener();
  }

  @override
  void didUpdateWidget(_ChatRoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart listener if the chat path changes (e.g., user switches selections)
    // This check is mostly redundant now but kept for robustness
    if (oldWidget.chatPath != widget.chatPath) {
      _firestoreMessages = [];
      _pendingMessages = []; // Clear pending messages on path switch
      _isInitialLoad = true;
      _stopChatListener();
      _startChatListener();
    }
  }
  
  // Checks if the document/collection path exists before attaching listener
  Future<bool> _doesChatCollectionExist() async {
    // Attempt to read the collection's parent document or just try to get a snapshot
    try {
        final querySnapshot = await FirebaseFirestore.instance.collection(widget.chatPath).limit(1).get();
        // If it returns docs or if it's not from cache (meaning it hit Firestore and found the collection path)
        return querySnapshot.docs.isNotEmpty || !querySnapshot.metadata.isFromCache;
    } catch (e) {
        // If there's a Firebase error (e.g., permission denied, invalid path segment), assume it doesn't exist for UI purposes.
        if (kDebugMode) print("Chat path validation error for ${widget.chatPath}: $e");
        return false;
    }
  }

  void _startChatListener() async {
    final bool chatExists = await _doesChatCollectionExist();
    
    if (!mounted || !chatExists) {
      _firestoreMessagesController.add([]);
      setState(() {
         _isInitialLoad = false;
      });
      return;
    }
    
    final Query baseQuery = FirebaseFirestore.instance
        .collection(widget.chatPath)
        .orderBy('timestamp', descending: true)
        .limit(30);

    // Initial load state is handled here.
    baseQuery.get().then((initialSnapshot) {
      if (mounted) {
         _firestoreMessages = initialSnapshot.docs.reversed.toList();
         _firestoreMessagesController.add(_firestoreMessages);
         setState(() {
            _isInitialLoad = false;
         });
         WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }).catchError((error) {
       if (kDebugMode) print('Firestore Initial Load Error: $error');
       if (mounted) {
          setState(() {
             _isInitialLoad = false;
          });
          _firestoreMessagesController.add([]);
       }
    });

    // Start the continuous listener for updates
    _chatSubscription = baseQuery.snapshots(includeMetadataChanges: true).listen(
      (snapshot) {
        if (mounted && !_isInitialLoad) {
          
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
          
          _firestoreMessagesController.add(_firestoreMessages);
          
          // Scroll to bottom only if a new message was added by another user
          if (addedNewMessage) {
             WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          }
        }
      },
      onError: (error) {
        if (kDebugMode) print('Firestore Listener Error: $error');
      },
    );
  }

  void _stopChatListener() {
    _chatSubscription?.cancel();
    _chatSubscription = null;
    _firestoreMessagesController.add([]); // Clear existing messages
  }

  // NEW: Function to delete a message
  Future<void> _deleteMessage(String docId) async {
    try {
      await FirebaseFirestore.instance.collection(widget.chatPath).doc(docId).delete();
    } catch (e) {
      if (kDebugMode) print('Error deleting message $docId: $e');
      if (mounted) {
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
      if (kDebugMode) print('Error editing message $docId: $e');
      if (mounted) {
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
       ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message exceeds the maximum limit of $_maxMessageLength characters.')),
        );
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // 3. Attempt to send to Firestore
    try {
      await FirebaseFirestore.instance.collection(widget.chatPath).add(messageData);
      // Success: The listener will handle removal from _pendingMessages and addition to _firestoreMessages
      
    } catch (e) {
      if (kDebugMode) print('Error sending message: $e');
      // Failure: Update status of the pending message
      if (mounted) {
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
    _firestoreMessagesController.close();
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
  
  // Custom Empty Chat State for Faculty
  Widget _buildEmptyState() {
     return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                widget.emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Messages are visible to all peers and faculty in this group.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Message Stream Area
        Expanded(
          child: StreamBuilder<List<DocumentSnapshot>>(
            stream: _firestoreMessagesController.stream,
            builder: (context, snapshot) {
              
              if (_isInitialLoad) {
                return const _ChatRoomShimmer();
              }
              
              final messages = _getDisplayMessages();
              
              // Check for empty state 
              if (messages.isEmpty && _pendingMessages.isEmpty) {
                // If there are no messages, show the custom empty state
                return _buildEmptyState();
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
                  backgroundColor: _kPrimaryChatColor,
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


// --- Individual Message Bubble Widget (Reused with slight adjustment to sender info) ---

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
  
  // Helper to format the sender display text based on chat type
  String _getSenderDetails() {
    final name = chatMessage.data['name'] ?? 'Unknown User'; 
    final role = chatMessage.data['role'] ?? 'Unknown Role';
    final branch = (chatMessage.data['branch'] ?? 'N/A');
    final year = (chatMessage.data['year'] ?? 'N/A');
    
    if (isMe) {
      return 'You (Faculty)';
    }
    
    // For faculty, display the sender's role and relevant course info
    // The chat is now only COLLEGE wide, so display full details for identification
    return '$name (${role.toUpperCase()}) | ${branch.toUpperCase()} - ${year.toUpperCase()}';
  }

  // Shows the edit/delete options on long press
  void _showOptions(BuildContext context) {
    // Only show options if the message has been delivered (has a confirmed ID)
    if (chatMessage.status != MessageStatus.delivered) return;
    
    // Faculty can edit/delete their own messages (isMe)
    if (!isMe) return; 

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
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Display sender details
              Flexible(
                child: Text(
                  _getSenderDetails(), 
                  overflow: TextOverflow.ellipsis,
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
            color: isMe ? _kPrimaryChatColor.withOpacity(0.9) : Colors.grey[200],
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

// --- SHIMMER WIDGETS (Updated for 2 tabs) ---

class _ChatAppBarShimmer extends StatelessWidget implements PreferredSizeWidget {
  final int length;
  const _ChatAppBarShimmer({this.length = 3});
  
  @override
  Widget build(BuildContext context) {
    // This shimmer is no longer needed since the main page is simplified, but kept for Shimmer logic in the ChatRoom.
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
        // Removed TabBar shimmer section
      ),
    );
  }
  
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight); // Only standard AppBar height
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
