import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
          title: const Text('All Activities'),
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
                        style: TextStyle(color: Colors.grey[600]),
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

  Widget _buildActivityCard(Map<String, dynamic> data) {
    final String action = data['action'] ?? 'Unknown Action';
    final Map<String, dynamic> details = data['details'] is Map ? data['details'] : {};
    final Timestamp? timestamp = data['timestamp'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_getIconForActivity(action), color: Colors.blue[800], size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildActivityText(action, details),
                const SizedBox(height: 4),
                if (timestamp != null)
                  Text(
                    _formatTimestamp(timestamp),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForActivity(String action) {
    if (action.contains('Upload')) {
      return Icons.upload_file;
    } else if (action.contains('Create')) {
      return Icons.create_new_folder_outlined;
    } else if (action.contains('Delete')) {
      return Icons.delete_outline;
    } else if (action.contains('Rename')) {
      return Icons.drive_file_rename_outline;
    } else if (action.contains('Access')) {
      return Icons.lock_open_outlined;
    }
    return Icons.history;
  }

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
    } else {
      return DateFormat('MMM d, yyyy').format(activityTime);
    }
  }

  Widget _buildActivityText(String action, Map<String, dynamic> details) {
    String detailText = '';
    if (details.containsKey('fileName')) {
      detailText = ' file "${details['fileName']}"';
    } else if (details.containsKey('folderName')) {
      detailText = ' folder "${details['folderName']}"';
    } else if (details.containsKey('subjectName')) {
      detailText = ' subject "${details['subjectName']}"';
    } else if (details.containsKey('branchName')) {
      detailText = ' branch "${details['branchName']}"';
    } else if (details.containsKey('newName')) {
      detailText = ' to "${details['newName']}"';
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87, fontSize: 15),
        children: [
          const TextSpan(text: 'You '),
          TextSpan(
            text: action.toLowerCase().replaceAll('my ', ''),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: detailText),
        ],
      ),
    );
  }
}

