import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grademate/models/file_models.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key});

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  String? _userName;
  bool _isLoading = true;
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _upcomingReminders = [];
  List<Map<String, dynamic>> _recentlyAccessedItems = [];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await _loadUserData();
    await _loadActivities();
    await _loadUpcomingReminders();
    await _loadRecentlyAccessedFiles(); // Added call
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
        final userDoc =
            await _firestore.collection('users').doc(user.email).get();
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
    await _loadActivitiesFromCache();
    await _fetchActivitiesFromFirestore();
  }

  Future<void> _loadActivitiesFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedActivities = prefs.getString('student_recent_activities');
      if (cachedActivities != null) {
        if (mounted) {
          setState(() {
            _activities =
                List<Map<String, dynamic>>.from(json.decode(cachedActivities));
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
          .limit(5)
          .get();

      final List<Map<String, dynamic>> firestoreActivities = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['timestamp'] is Timestamp) {
          data['timestamp'] =
              (data['timestamp'] as Timestamp).toDate().toIso8601String();
        }
        firestoreActivities.add(data);
      }

      if (mounted) {
        setState(() {
          _activities = firestoreActivities;
        });
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'student_recent_activities', json.encode(firestoreActivities));
    } catch (e) {
      print("Error fetching activities from Firestore: $e");
    }
  }

  Future<void> _loadUpcomingReminders() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    try {
      final now = Timestamp.now();
      final snapshot = await _firestore
          .collection('users')
          .doc(user.email)
          .collection('reminders')
          .where('reminderTime', isGreaterThanOrEqualTo: now)
          .orderBy('reminderTime', descending: false)
          .limit(3)
          .get();

      final List<Map<String, dynamic>> upcoming = [];
      for (var doc in snapshot.docs) {
        upcoming.add(doc.data());
      }

      if (mounted) {
        setState(() {
          _upcomingReminders = upcoming;
        });
      }
    } catch (e) {
      print("Error fetching upcoming reminders: $e");
    }
  }

  // **NEW**: Added function to load recently accessed files
  Future<void> _loadRecentlyAccessedFiles() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    final userDocRef = _firestore.collection('users').doc(user.email);
    final userDoc = await userDocRef.get();

    if (!userDoc.exists || userDoc.data()?['recentlyAccessed'] == null) {
      return;
    }

    List<String> paths = List<String>.from(userDoc.data()!['recentlyAccessed']);
    List<Map<String, dynamic>> validItems = [];
    List<String> invalidPaths = [];

    for (String path in paths) {
      try {
        final fileDoc = await _firestore.doc(path).get();
        if (fileDoc.exists) {
          final data = fileDoc.data() as Map<String, dynamic>;
          data['id'] = fileDoc.id;
          data['path'] = fileDoc.reference.path;
          validItems.add(data);
        } else {
          invalidPaths.add(path);
        }
      } catch (e) {
        print("Error fetching recent file at path $path: $e");
        invalidPaths.add(path);
      }
    }

    if (invalidPaths.isNotEmpty) {
      await userDocRef.update({
        'recentlyAccessed': FieldValue.arrayRemove(invalidPaths),
      });
    }

    if (mounted) {
      setState(() {
        _recentlyAccessedItems = validItems;
      });
    }
  }

  // **NEW**: Added function to open external URLs
  Future<void> _openExternalUrl(String? url) async {
    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link: URL is empty.')),
        );
      }
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open URL: $url')),
        );
      }
    }
  }

  Stream<int> _getUnreadNotificationsCountStream() {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      return Stream.value(0);
    }
    return _firestore
        .collection('users')
        .doc(user.email)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .where('timestamp', isLessThanOrEqualTo: Timestamp.now())
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> quickAccessItems = [
      {'icon': Icons.star_outline, 'label': 'Favorites', 'route': '/favorites'},
      {'icon': Icons.assignment_outlined, 'label': 'Assignments', 'route': '/student_assignments'},
      {'icon': Icons.download_outlined, 'label': 'Downloads', 'route': '/downloads'},
      {'icon': Icons.note_alt_outlined, 'label': 'My Notes', 'route': '/my_notes'},
      {'icon': Icons.notifications_active_outlined, 'label': 'Reminders', 'route': '/reminders'},
    ];

    return Scaffold(
      // **MODIFIED**: AppBar updated to match faculty page
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'GradeMate',
          style: GoogleFonts.playwriteDeGrund(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          StreamBuilder<int>(
            stream: _getUnreadNotificationsCountStream(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined,
                        color: Colors.black),
                    onPressed: () => context.push('/notifications'),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10)),
                        constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadInitialData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    // **MODIFIED**: Greeting text updated with gradient
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            fontSize: 28, color: Colors.black87),
                        children: <TextSpan>[
                          const TextSpan(text: 'Hello, '),
                          TextSpan(
                            text: _userName ?? 'Student',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              foreground: Paint()
                                ..shader = const LinearGradient(
                                  colors: <Color>[
                                    Colors.blueAccent,
                                    Colors.purpleAccent
                                  ],
                                ).createShader(const Rect.fromLTWH(
                                    0.0, 0.0, 200.0, 70.0)),
                            ),
                          ),
                        ],
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
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                          item['icon'] as IconData,
                          item['label'] as String,
                          onTap: () {
                            if (item['route'] != null) {
                              context.push(item['route'] as String);
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
                    _buildUpcomingSection(),
                    const SizedBox(height: 32),
                    // **NEW**: Recently Accessed Section Added
                    const Text(
                      'Recently Accessed',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    _buildRecentlyAccessedSection(),
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
                          onPressed: () => context.push('/all_activities'),
                          child: const Text('Show All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildRecentActivityList(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildQuickAccessCard(IconData icon, String label,
      {VoidCallback? onTap}) {
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
  
  // **NEW**: Widget to build the recently accessed section
  Widget _buildRecentlyAccessedSection() {
    if (_recentlyAccessedItems.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
        child: Center(
          child: Text("Files you open will appear here.",
              style: TextStyle(color: Colors.grey[600], fontSize: 15)),
        ),
      );
    }

    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _recentlyAccessedItems.length,
        itemBuilder: (context, index) {
          final item = _recentlyAccessedItems[index];
          return _buildRecentFileCard(item);
        },
      ),
    );
  }

  // **NEW**: Widget to build a single card for a recently accessed file
  Widget _buildRecentFileCard(Map<String, dynamic> item) {
    final String itemName = item['fileName'] ?? item['title'] ?? 'Unknown';
    final String itemType = item['type'] ?? 'unknown';

    return GestureDetector(
      onTap: () {
        final isLink = item['type'] == 'link';
        if (isLink) {
          _openExternalUrl(item['url'] as String?);
        } else {
          final file = FileData(
            id: item['id'] ?? '',
            name: itemName,
            url: item['fileURL'] ?? item['url'] ?? '', // Crucial fallback
            type: itemType,
            size: item['size'] ?? 0,
            uploadedAt: item['timestamp'] ?? Timestamp.now(),
            ownerId: item['ownerId'] ?? item['uploadedBy'] ?? '',
            ownerName: item['ownerName'] ?? '',
          );

          if (file.url.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot open file: URL is missing.'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
          context.push('/file_viewer', extra: file);
        }
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.teal.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(_getFileIcon(itemType), size: 40, color: Colors.teal[800]),
            const SizedBox(height: 12),
            Text(
              itemName,
              style: const TextStyle(fontWeight: FontWeight.w500),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingSection() {
    if (_upcomingReminders.isEmpty) {
      return Container(
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
      );
    } else {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _upcomingReminders.length,
        itemBuilder: (context, index) {
          final reminder = _upcomingReminders[index];
          final reminderTime = (reminder['reminderTime'] as Timestamp).toDate();
          return _buildUpcomingCard(
              reminder['title'],
              DateFormat('MMM d, yyyy \'at\' hh:mm a').format(reminderTime));
        },
      );
    }
  }

  Widget _buildUpcomingCard(String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: Colors.blue[800]),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final Map<String, dynamic> details =
        data['details'] is Map ? data['details'] : {};

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
  
  // **NEW**: Helper function to get the correct icon for a file type
  IconData _getFileIcon(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image_outlined;
      case 'zip':
      case 'rar':
        return Icons.folder_zip_outlined;
      case 'link':
        return Icons.link;
      default:
        return Icons.insert_drive_file_outlined;
    }
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