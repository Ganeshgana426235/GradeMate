import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:grademate/widgets/bottom_nav_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class FacultyHomePage extends StatefulWidget {
  const FacultyHomePage({super.key});

  @override
  State<FacultyHomePage> createState() => _FacultyHomePageState();
}

class _FacultyHomePageState extends State<FacultyHomePage> {
  int _selectedIndex = 0;
  String? _userName;
  bool _isLoading = true;
  List<Map<String, dynamic>> _activities = [];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadUserData();
    await _loadActivities();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        final userDoc = await _firestore.collection('users').doc(user.email).get();
        if (mounted && userDoc.exists) {
          final fullName = userDoc.data()?['name'] as String?;
          _userName = fullName?.split(' ').first;
        }
      } catch (e) {
        print("Error loading user data: $e");
      }
    }
  }

  Future<void> _loadActivities() async {
    // 1. Try to load activities from local storage first for a quick startup.
    await _loadActivitiesFromCache();

    // 2. Fetch latest activities from Firestore and update cache.
    await _fetchActivitiesFromFirestore();
  }

  Future<void> _loadActivitiesFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedActivities = prefs.getString('recent_activities');
      if (cachedActivities != null) {
        if (mounted) {
          setState(() {
            _activities = List<Map<String, dynamic>>.from(json.decode(cachedActivities));
          });
        }
      }
    } catch (e) {
      print("Error loading activities from cache: $e");
    }
  }

  Future<void> _fetchActivitiesFromFirestore() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.email)
          .collection('activities')
          .orderBy('timestamp', descending: true)
          .limit(5) // Fetching latest 5 activities
          .get();

      final List<Map<String, dynamic>> firestoreActivities = [];
      for (var doc in snapshot.docs) {
          final data = doc.data();
          // Convert Timestamp to a serializable format (ISO 8601 string)
          if (data['timestamp'] is Timestamp) {
            data['timestamp'] = (data['timestamp'] as Timestamp).toDate().toIso8601String();
          }
          firestoreActivities.add(data);
      }
      
      if (mounted) {
        setState(() {
          _activities = firestoreActivities;
        });
      }

      // Save the fresh data to local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('recent_activities', json.encode(firestoreActivities));

    } catch (e) {
      print("Error fetching activities from Firestore: $e");
    }
  }


  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 0) {
      // Stay on the home page
    } else if (index == 1) {
      context.go('/faculty_courses');
    } else if (index == 2) {
      context.go('/faculty_my_files');
    } else if (index == 3) {
      context.go('/faculty_profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define the quick access items
    final List<Map<String, dynamic>> quickAccessItems = [
      {'icon': Icons.assignment_outlined, 'label': 'Assignments', 'route': '/faculty_assignments'},
      {'icon': Icons.download_outlined, 'label': 'Downloads', 'route': '/downloads'},
      {'icon': Icons.note_alt_outlined, 'label': 'My Notes', 'route': '/my_notes'},
      {'icon': Icons.notifications_outlined, 'label': 'Reminders', 'route': '/reminders'},
      {'icon': Icons.announcement_outlined, 'label': 'Send Notification', 'route': '/send_notification'},
      {'icon': Icons.groups_outlined, 'label': 'Manage Students', 'route': '/manage_students'},
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Home', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.black),
            onPressed: () {
              // TODO: Implement settings functionality
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    'Hello, ${_userName ?? 'Faculty'}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Quick Access',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 2.8,
                    ),
                    itemCount: quickAccessItems.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      final item = quickAccessItems[index];
                      return _buildQuickAccessCard(
                        item['icon'],
                        item['label'],
                        onTap: () {
                          if (item['route'] != null) {
                            context.go(item['route']);
                          } else {
                            // TODO: Implement other quick access actions
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${item['label']} clicked')),
                            );
                          }
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Upcoming',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        "You have no upcoming events.",
                        style: TextStyle(color: Colors.grey[600], fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                   Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Activity',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/all_activities'),
                        child: const Text('Show All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildRecentActivityList(),
                ],
              ),
            ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  Widget _buildQuickAccessCard(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.blue[800], size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRecentActivityList() {
    if (_activities.isEmpty) {
      return Center(
        child: Text(
          "No recent activity.",
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _activities.length,
      itemBuilder: (context, index) {
        final data = _activities[index];
        return _buildActivityCard(data);
      },
    );
  }


  Widget _buildActivityCard(Map<String, dynamic> data) {
    final String action = data['action'] ?? 'Unknown Action';
    final Map<String, dynamic> details = data['details'] is Map ? data['details'] : {};
    
    // The timestamp is now stored as a String, so we need to parse it.
    final String? timestampString = data['timestamp'];
    final Timestamp? timestamp = timestampString != null 
        ? Timestamp.fromDate(DateTime.parse(timestampString)) 
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
    // This part can be expanded to provide more descriptive text
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
