import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart'; // NEW: Import Google Fonts

// Primary accent color for consistency
const Color _kPrimaryColor = Color(0xFF6A67FE);
const Color _kAccentGradientStart = Color(0xFFF0F5FF);
const Color _kAccentGradientEnd = Color(0xFFFFFFFF);

class AllActivitiesPage extends StatefulWidget {
  const AllActivitiesPage({super.key});

  @override
  State<AllActivitiesPage> createState() => _AllActivitiesPageState();
}

class _AllActivitiesPageState extends State<AllActivitiesPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        final doc = await _firestore.collection('users').doc(user.email).get();
        if (mounted && doc.exists) {
          setState(() {
            _userRole = doc.data()?['role'];
          });
        }
      } catch (e) {
        // Handle error if needed, e.g., show a snackbar
        print('Error fetching user role: $e');
      }
    }
  }

  void _navigateBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      // Fallback navigation if there's no page to pop to
      if (_userRole == 'Faculty') {
        context.go('/faculty_home');
      } else if (_userRole == 'Student') {
        context.go('/student_home');
      } else {
        // Default fallback if role is not determined
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _navigateBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: _navigateBack,
          ),
          title: Text('All Activities', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
        ),
        body: user == null || user.email == null
            ? const Center(child: Text("Not logged in."))
            : StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('users')
                    .doc(user.email)
                    .collection('activities')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Center(child: Text("Error loading activities."));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        "No activity found.",
                        style: GoogleFonts.inter(color: Colors.grey[600]),
                      ),
                    );
                  }
  
                  final activities = snapshot.data!.docs;
  
                  return ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: activities.length,
                    itemBuilder: (context, index) {
                      final doc = activities[index];
                      final data = doc.data() as Map<String, dynamic>;
                      return _buildActivityCard(data);
                    },
                  );
                },
              ),
      ),
    );
  }

  // --- UPDATED: Activity Card UI ---
  Widget _buildActivityCard(Map<String, dynamic> data) {
    final String action = data['action'] ?? 'Unknown Action';
    final Map<String, dynamic> details = data['details'] is Map ? data['details'] : {};
    final Timestamp? timestamp = data['timestamp'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPrimaryColor.withOpacity(0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon with Primary Color
          Icon(_getIconForActivity(action), color: _kPrimaryColor, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Activity Text Builder
                _buildActivityText(action, details),
                const SizedBox(height: 4),
                // Timestamp
                if (timestamp != null)
                  Text(
                    _formatTimestamp(timestamp),
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- UPDATED: Activity Icon ---
  IconData _getIconForActivity(String action) {
    if (action.contains('Favorite')) {
      return Icons.star;
    } else if (action.contains('Upload')) {
      return Icons.upload_file_outlined;
    } else if (action.contains('Create') || action.contains('Added Link')) {
      return Icons.add_circle_outline;
    } else if (action.contains('Delete')) {
      return Icons.delete_outline;
    } else if (action.contains('Rename')) {
      return Icons.drive_file_rename_outline;
    } else if (action.contains('Access')) {
      return Icons.lock_open_outlined;
    } else if (action.contains('Share')) {
      return Icons.share_outlined;
    } else if (action.contains('Edited Access')) {
      return Icons.lock_outline;
    }
    return Icons.history;
  }

  // --- UPDATED: Timestamp Formatting (similar to home page) ---
  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final activityTime = timestamp.toDate();
    final difference = now.difference(activityTime);

    if (difference.inSeconds < 60) {
      return "${difference.inSeconds}s ago";
    } else if (difference.inMinutes < 60) {
      return "${difference.inMinutes}m ago";
    } else if (difference.inHours < 24) {
      return "${difference.inHours}h ago";
    } else if (difference.inDays < 7) {
      return "${difference.inDays}d ago";
    } else {
      return DateFormat('MMM d, yyyy').format(activityTime);
    }
  }

  // --- UPDATED: Activity Text Builder (Improved RichText) ---
  Widget _buildActivityText(String action, Map<String, dynamic> details) {
    String objectName = '';
    String actionWord = action.toLowerCase();
    
    // Determine the main object
    if (details.containsKey('fileName')) {
      objectName = details['fileName'];
    } else if (details.containsKey('folderName')) {
      objectName = details['folderName'];
    } else if (details.containsKey('subjectName')) {
      objectName = details['subjectName'];
    } else if (details.containsKey('branchName')) {
      objectName = details['branchName'];
    } else if (details.containsKey('linkName')) {
      objectName = details['linkName'];
    } else if (details.containsKey('newName')) {
      objectName = details['newName'];
    }

    // Determine the full descriptive phrase for the object
    String objectPhrase = objectName.isNotEmpty ? '"$objectName"' : 'an item';

    // Adjust action word for readability
    if (action.contains('Created')) {
      actionWord = 'created';
    } else if (action.contains('Uploaded')) {
      actionWord = 'uploaded';
    } else if (action.contains('Added Link')) {
      actionWord = 'added link';
    } else if (action.contains('Deleted')) {
      actionWord = 'deleted';
    } else if (action.contains('Renamed')) {
       // Handle rename specifically
       final oldName = details['oldName'] ?? 'an item';
       final newName = details['newName'] ?? 'New Name';
       actionWord = 'renamed "$oldName" to';
       objectPhrase = '"$newName"';
    } else if (action.contains('Edited Access')) {
      final sharedWith = (details['sharedWith'] as List?)?.join(', ') ?? 'No One';
      actionWord = 'changed access for "$objectName" to';
      objectPhrase = '$sharedWith';
    } else if (action.contains('Removed from Favorites')) {
      actionWord = 'removed from Favorites';
    } else if (action.contains('Added to Favorites')) {
      actionWord = 'added to Favorites';
    }
    
    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(color: Colors.black87, fontSize: 15),
        children: [
          const TextSpan(text: 'You '),
          TextSpan(
            text: actionWord,
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: objectPhrase,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          // Add context for multi-level actions (e.g., subject creation)
          if (details.containsKey('branch') && !action.contains('Branch'))
            TextSpan(text: ' in ${details['branch'] ?? ''}/${details['year'] ?? ''}'),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}