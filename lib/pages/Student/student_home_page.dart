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
import 'package:shimmer/shimmer.dart';

class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key});

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  String? _userName;
  bool _isLoading = true;
  List<Map<String, dynamic>> _activities = [];
  
  // Lists to store ALL items fetched from Firestore
  List<Map<String, dynamic>> _allReminders = [];
  List<Map<String, dynamic>> _allAccessedItems = [];

  // State flags for expanding/collapsing sections
  bool _showAllReminders = false;
  bool _showAllAccessed = false;

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
    await _loadRecentlyAccessedFiles();
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
      // LIMIT is 5, as requested
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
      // Fetch ALL upcoming reminders to allow for expansion
      final snapshot = await _firestore
          .collection('users')
          .doc(user.email)
          .collection('reminders')
          .where('reminderTime', isGreaterThanOrEqualTo: now)
          .orderBy('reminderTime', descending: false)
          .get();

      final List<Map<String, dynamic>> allUpcoming = [];
      for (var doc in snapshot.docs) {
        allUpcoming.add(doc.data());
      }

      if (mounted) {
        setState(() {
          _allReminders = allUpcoming;
        });
      }
    } catch (e) {
      print("Error fetching upcoming reminders: $e");
    }
  }

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

    // Fetches items, logic for limiting to 6 for display is in the build method.
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
        _allAccessedItems = validItems;
      });
    }
  }

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
    // Quick Access items, subtitles removed as requested
    final List<Map<String, dynamic>> quickAccessItems = [
      {'icon': Icons.star_outlined, 'label': 'Favorite Files', 'route': '/favorites'},
      {'icon': Icons.assignment_outlined, 'label': 'Assignments', 'route': '/student_assignments'},
      {'icon': Icons.download_outlined, 'label': 'Downloads', 'route': '/downloads'},
      {'icon': Icons.note_alt_outlined, 'label': 'My Notes', 'route': '/my_notes'},
      {'icon': Icons.notifications_active_outlined, 'label': 'Reminders', 'route': '/reminders'},
      {'icon': Icons.business_center_outlined, 'label': 'Job Updates', 'route': '/job_updates'},
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            // AppBar title using the custom playful style
            Text(
              'GradeMate',
              style: GoogleFonts.playwriteDeGrund(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 24, // Increased size for prominence
              ),
            ),
            const Spacer(),
          ],
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
                            color: const Color(0xFF6A67FE),
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
          ? const _StudentHomePageShimmer()
          : RefreshIndicator(
              onRefresh: _loadInitialData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Adjusted horizontal padding slightly to give more room for grid items
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // --- UPDATED: Animated Greeting Text ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: RichText(
                        // Explicitly defining the list type to accept WidgetSpan and TextSpan
                        text: TextSpan(
                          style: GoogleFonts.inter(fontSize: 22, color: Colors.black87),
                          children: <InlineSpan>[ // CHANGED: Type to InlineSpan
                            const TextSpan(text: 'Hello, '),
                            WidgetSpan( 
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0.9, end: 1.0),
                                duration: const Duration(milliseconds: 700),
                                curve: Curves.elasticOut,
                                builder: (BuildContext context, double scale, Widget? child) {
                                  return Transform.scale(
                                    scale: scale,
                                    child: Text(
                                      _userName ?? 'Student',
                                      style: GoogleFonts.inter(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF6A67FE), // Use the primary purple color
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const TextSpan(text: '!'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // --- Quick Access Section ---
                    _buildSectionTitle('Quick Access', trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${quickAccessItems.length}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A67FE).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${quickAccessItems.length}',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF6A67FE),
                            ),
                          ),
                        ),
                      ],
                    ),),
                    const SizedBox(height: 8), // Reduced vertical spacing
                    _buildQuickAccessGrid(quickAccessItems),
                    const SizedBox(height: 20), // Reduced vertical spacing
                    
                    // --- Upcoming Events Section (Reminders) ---
                    _buildSectionTitle('Upcoming Events', trailing: TextButton(
                      onPressed: () {
                        setState(() {
                          _showAllReminders = !_showAllReminders;
                        });
                      },
                      child: Text(_showAllReminders ? 'See less' : 'See all', 
                                style: const TextStyle(color: Color(0xFF6A67FE))),
                    )),
                    const SizedBox(height: 8), // Reduced vertical spacing
                    _buildUpcomingSectionCard(),
                    const SizedBox(height: 20), // Reduced vertical spacing
                    
                    // --- Recently Accessed Files Section ---
                    _buildSectionTitle('Recently Accessed Files', trailing: TextButton(
                      onPressed: () {
                        setState(() {
                          _showAllAccessed = !_showAllAccessed;
                        });
                      },
                      child: Text(_showAllAccessed ? 'View less' : 'View all', 
                                style: const TextStyle(color: Color(0xFF6A67FE))),
                    )),
                    const SizedBox(height: 8), // Reduced vertical spacing
                    _buildRecentlyAccessedGrid(),
                    const SizedBox(height: 20), // Reduced vertical spacing
                    
                    // --- Recent Activity Section ---
                    _buildSectionTitle('Recent Activity', trailing: TextButton(
                      onPressed: () => context.push('/all_activities'),
                      child: const Text('See details', style: TextStyle(color: Color(0xFF6A67FE))),
                    )),
                    const SizedBox(height: 8), // Reduced vertical spacing
                    _buildRecentActivityList(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }
  
  // --- Section Title Helper ---
  Widget _buildSectionTitle(String title, {Widget? trailing}) {
    return Padding(
      // Adjusted padding for consistency with screen padding change
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // --- Quick Access Grid ---
  Widget _buildQuickAccessGrid(List<Map<String, dynamic>> items) {
    return Container(
      // FIXED: Removed the duplicate 'color' property
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        // Added border/shadow similar to the image's container style
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
        boxShadow: [
          // UPDATED: More pronounced, cleaner shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: GridView.builder(
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12, // Reduced spacing
          mainAxisSpacing: 12, // Reduced spacing
          // FIXED: Adjusted aspect ratio for more vertical space to prevent bottom overflow
          childAspectRatio: 3.2, 
        ),
        itemCount: items.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final item = items[index];
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
    );
  }

  // --- Quick Access Card (NOW WITH GRADIENT BACKGROUND) ---
  Widget _buildQuickAccessCard(IconData icon, String label,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Reduced vertical padding to compact the card height
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0), 
        decoration: BoxDecoration(
          // GRADIENT BACKGROUND added here for the card
          gradient: const LinearGradient(
            colors: [
              Color(0xFFF0F5FF), // Light gradient start
              Color(0xFFFFFFFF), // White gradient end
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          // Subtle border and shadow for depth, matching the image style
          border: Border.all(color: const Color(0xFF6A67FE).withOpacity(0.1), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        // ROW layout for icon and text
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center, 
          children: [
            Container(
              padding: const EdgeInsets.all(6), // Adjusted padding
              decoration: BoxDecoration(
                // Icon background set to a solid color/opacity
                color: const Color(0xFF6A67FE).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF6A67FE), size: 20), // Icon size 20
            ),
            const SizedBox(width: 8), // Spacing between icon and text
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13, // Font size 13
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.left,
                maxLines: 2, // Allow 2 lines for longer labels
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Upcoming Events Card Wrapper (Now handles expansion) ---
  Widget _buildUpcomingSectionCard() {
    final displayReminders = _showAllReminders 
        ? _allReminders 
        : _allReminders.take(3).toList(); // Show max 3 or all

    return Container(
      // FIXED: Removed the duplicate 'color' property
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
        boxShadow: [
          // UPDATED: More pronounced, cleaner shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: displayReminders.isEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  "You have no upcoming events.",
                  style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 15),
                ),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayReminders.length,
              itemBuilder: (context, index) {
                final reminder = displayReminders[index];
                final reminderTime = (reminder['reminderTime'] as Timestamp).toDate();
                return _buildUpcomingEventTile(
                    reminder['title'] ?? 'Upcoming Event',
                    reminderTime,
                    index == displayReminders.length - 1 // isLast
                );
              },
            ),
    );
  }

  // --- Upcoming Event Tile (NOW WITH GRADIENT BACKGROUND) ---
  Widget _buildUpcomingEventTile(String title, DateTime time, bool isLast) {
    return Container(
      // Increased bottom margin for better separation
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10.0),
      // Decreased internal padding
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // GRADIENT BACKGROUND added here
        gradient: const LinearGradient(
          colors: [
            Color(0xFFF0F5FF), // Light gradient start
            Color(0xFFFFFFFF), // White gradient end
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        // Subtle border and shadow for depth, matching the image style
        border: Border.all(color: const Color(0xFF6A67FE).withOpacity(0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date Circle (Matches image style)
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF6A67FE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('d').format(time),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(time).toUpperCase(),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('hh:mm a').format(time),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Recently Accessed Grid (Now handles expansion) ---
  Widget _buildRecentlyAccessedGrid() {
    final displayItems = _showAllAccessed
        ? _allAccessedItems 
        : _allAccessedItems.take(6).toList(); // Show max 6 or all
    
    if (displayItems.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, // Plain white background
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text("Files you open will appear here.",
              style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 15)),
        ),
      );
    }
    
    // Determine the effective item count for the GridView
    final int effectiveItemCount = displayItems.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, // Plain white background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
        boxShadow: [
          // UPDATED: More pronounced, cleaner shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // Use GridView.builder for potentially a lot of items (when expanded)
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          // FIXED: Adjusted aspect ratio to resolve 15px bottom overflow
          childAspectRatio: 1.1, 
        ),
        itemCount: effectiveItemCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          return _buildRecentFileCard(displayItems[index]);
        },
      ),
    );
  }

  // --- Recently Accessed File Card (NOW WITH CUSTOM TRUNCATION) ---
  Widget _buildRecentFileCard(Map<String, dynamic> item) {
    final String itemName = item['fileName'] ?? item['title'] ?? 'Unknown';
    final String itemType = item['type'] ?? 'unknown';
    // Logic to determine the sub-text (e.g., 'Edited 2h ago', 'Yesterday', 'Oct 10')
    String subText = '';
    
    if (item.containsKey('timestamp') && item['timestamp'] is Timestamp) {
        final accessTime = (item['timestamp'] as Timestamp).toDate();
        final now = DateTime.now();
        final difference = now.difference(accessTime);
        
        if (difference.inHours < 24) {
             subText = 'Edited ${difference.inHours}h ago';
             if (difference.inHours == 0) subText = 'Edited ${difference.inMinutes}m ago';
        } else if (difference.inDays == 1) {
             subText = 'Yesterday';
        } else {
             subText = DateFormat('MMM d').format(accessTime);
        }
    } else {
        subText = 'Recently accessed'; // Default fallback
    }

    return GestureDetector(
      onTap: () {
        final isLink = item['type'] == 'link';
        if (isLink) {
          _openExternalUrl(item['url'] as String?);
        } else {
          final file = FileData(
            id: item['id'] ?? '',
            name: itemName,
            url: item['fileURL'] ?? item['url'] ?? '',
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // GRADIENT BACKGROUND added here
          gradient: const LinearGradient(
            colors: [
              Color(0xFFF0F5FF), // Light gradient start
              Color(0xFFFFFFFF), // White gradient end
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          // Subtle border and shadow for depth, matching the image style
          border: Border.all(color: const Color(0xFF6A67FE).withOpacity(0.1), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6A67FE).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_getFileIcon(itemType), size: 30, color: const Color(0xFF6A67FE)),
            ),
            const SizedBox(height: 12),
            Text(
              // APPLIED CUSTOM TRUNCATION LOGIC HERE
              _truncateFileName(itemName),
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.black87,
              ),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              subText,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // --- Recent Activity List ---
  Widget _buildRecentActivityList() {
    if (_activities.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, // Plain white background
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            "No recent activity.",
            style: GoogleFonts.inter(color: Colors.grey[600]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, // Plain white background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
        boxShadow: [
          // UPDATED: More pronounced, cleaner shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _activities.length, // Already limited to 5
        itemBuilder: (context, index) {
          final data = _activities[index];
          return _buildActivityTile(data, index == _activities.length - 1);
        },
      ),
    );
  }

  // --- Recent Activity Tile (NOW WITH FIXED ICON COLOR) ---
  Widget _buildActivityTile(Map<String, dynamic> data, bool isLast) {
    final String action = data['action'] ?? 'Unknown Action';
    final Map<String, dynamic> details =
        data['details'] is Map ? data['details'] : {};
    
    final String? timestampString = data['timestamp'];
    final Timestamp? timestamp = timestampString != null
        ? Timestamp.fromDate(DateTime.parse(timestampString))
        : null;

    final Widget activityText = _buildActivityRichText(action, details);
    final IconData icon = _getIconForActivity(action);
    // FIXED: Force icon color to the primary blue/purple for all activities, including star
    const Color iconColor = Color(0xFF6A67FE);


    return Container(
      // Margin at the bottom, removed for the last item
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10.0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        // GRADIENT BACKGROUND added here
        gradient: const LinearGradient(
          colors: [
            Color(0xFFF0F5FF), // Light gradient start
            Color(0xFFFFFFFF), // White gradient end
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        // Subtle border and shadow for depth, matching the image style
        border: Border.all(color: const Color(0xFF6A67FE).withOpacity(0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Use the determined icon color
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: activityText,
          ),
          if (timestamp != null)
            Text(
              _formatTimestamp(timestamp),
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
            ),
        ],
      ),
    );
  }
  
  // --- Activity Rich Text Builder (Updated for CUSTOM TRUNCATION) ---
  Widget _buildActivityRichText(String action, Map<String, dynamic> details) {
    String objectName = '';
    
    if (details.containsKey('fileName')) {
      objectName = details['fileName'];
    } else if (details.containsKey('folderName')) {
      objectName = details['folderName'];
    } else if (details.containsKey('subjectName')) {
      objectName = details['subjectName'];
    } else if (details.containsKey('branchName')) {
      objectName = details['branchName'];
    } else if (details.containsKey('newName')) {
      objectName = details['newName'];
    }
    
    // Truncate the object name before using it
    // Set max length to 15 for safety in the narrow activity list
    final String truncatedName = _truncateFileName(objectName, maxLength: 15);

    String actionPrefix = '';
    String actionSuffix = '';
    
    // Customizing the action text to be more like the image examples
    if (action.contains('Upload') || action.contains('Create')) {
      actionPrefix = action.contains('Upload') ? 'Uploaded' : 'Created';
      actionSuffix = '"$truncatedName"';
    } else if (action.contains('Update')) {
      actionPrefix = 'Updated';
      actionSuffix = '"$truncatedName"';
    } else if (action.contains('Delete')) {
      actionPrefix = 'Deleted';
      actionSuffix = '"$truncatedName"';
    } else if (action.contains('Rename')) {
      actionPrefix = 'Renamed';
      actionSuffix = ' to "$truncatedName"';
    } else if (action.contains('Share')) {
      actionPrefix = 'Shared';
      // Truncate the file name in share action too
      final String sharedFileName = _truncateFileName(details['fileName'] ?? 'file', maxLength: 15);
      actionSuffix = '"$sharedFileName" with ${details['recipientName'] ?? 'a user'}';
    } else if (action.contains('Add Favorite')) {
        actionPrefix = 'Added Favorite';
        actionSuffix = '"$truncatedName"';
    } else if (action.contains('Remove Favorite')) {
        actionPrefix = 'Removed Favorite';
        actionSuffix = '"$truncatedName"';
    } else {
        // Fallback for other actions
        return Text(
            '$action $truncatedName',
            style: GoogleFonts.inter(color: Colors.black87, fontSize: 14),
        );
    }

    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(color: Colors.black87, fontSize: 14),
        children: [
          TextSpan(text: actionPrefix),
          const TextSpan(text: ' '),
          TextSpan(
            text: actionSuffix,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      maxLines: 2, // Allow activity text to wrap
      overflow: TextOverflow.ellipsis,
    );
  }

  // --- Utility Functions (Updated for Star Icon) ---
  
  IconData _getIconForActivity(String action) {
    // FIXED: Star icon for favorite actions
    if (action.contains('Favorite')) {
      return Icons.star;
    } else if (action.contains('Upload')) {
      return Icons.upload_file_outlined;
    } else if (action.contains('Create')) {
      return Icons.create_new_folder_outlined;
    } else if (action.contains('Delete')) {
      return Icons.delete_outline;
    } else if (action.contains('Rename')) {
      return Icons.drive_file_rename_outline;
    } else if (action.contains('Access')) {
      return Icons.lock_open_outlined;
    } else if (action.contains('Update')) {
      return Icons.edit_note_outlined;
    } else if (action.contains('Share')) {
      return Icons.share_outlined;
    }
    return Icons.history;
  }

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
      case 'md':
        return Icons.article_outlined;
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
    } else if (difference.inDays == 1) {
      return "Yesterday";
    } else {
      return DateFormat('MMM d').format(activityTime);
    }
  }

  // --- Utility Function to Truncate Long File Names (UPDATED CUSTOM LOGIC) ---
  String _truncateFileName(String fileName, {int maxLength = 12}) {
    if (fileName.length <= maxLength) {
      return fileName;
    }
    // Custom logic: take maxLength characters and append "..."
    // Since we don't preserve extension, we use maxLength - 3 for the substring
    return '${fileName.substring(0, maxLength - 3)}...';
  }
}

// --- Shimmer Placeholder (Updated to match new layout) ---
class _StudentHomePageShimmer extends StatelessWidget {
  const _StudentHomePageShimmer();

  @override
  Widget build(BuildContext context) {
    // Shimmer.fromColors applies the attractive loading animation over the child widgets
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(), // Prevent scrolling shimmer
        padding: const EdgeInsets.symmetric(horizontal: 12.0), // Match body padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // 1. Title Placeholder (Greeting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Container(height: 22, width: 180, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            ),
            const SizedBox(height: 16),
            
            // 2. Quick Access Title Placeholder
            _buildShimmerSectionTitle(),
            const SizedBox(height: 8),

            // 3. Quick Access Grid Placeholder (Using childAspectRatio 3.2 for row layout)
            Container(
              padding: const EdgeInsets.all(12), // Match grid padding
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12, // Match grid spacing
                  mainAxisSpacing: 12, // Match grid spacing
                  childAspectRatio: 3.2, // Match the final compact row ratio
                ),
                itemCount: 4, // Show 4 loading cards
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // 4. Upcoming Events Title Placeholder
            _buildShimmerSectionTitle(showTrailing: true),
            const SizedBox(height: 8),

            // 5. Upcoming List Placeholder (2 items in the card)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                _buildUpcomingPlaceholder(),
                const SizedBox(height: 10), // Matched margin
                _buildUpcomingPlaceholder(),
              ]),
            ),
            const SizedBox(height: 24),

            // 6. Recently Accessed Title Placeholder
            _buildShimmerSectionTitle(showTrailing: true),
            const SizedBox(height: 8),

            // 7. Recently Accessed Grid Placeholder (6 items in the container)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1, // Match the final fixed ratio
                ),
                itemCount: 6,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // REMOVED DECORATION, kept color for the plain block
                        Container(height: 30, width: 30, color: Colors.white), 
                        const SizedBox(height: 12),
                        Container(height: 14, width: 80, color: Colors.white),
                        const SizedBox(height: 4),
                        Container(height: 10, width: 50, color: Colors.white),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // 8. Recent Activity Title/Button Placeholder
            _buildShimmerSectionTitle(showTrailing: true),
            const SizedBox(height: 8),

            // 9. Recent Activity List Placeholder (3 items in the container)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                _buildActivityPlaceholder(),
                const SizedBox(height: 10),
                _buildActivityPlaceholder(),
                const SizedBox(height: 10),
                _buildActivityPlaceholder(),
              ]),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  
  // Placeholder for Section Title
  Widget _buildShimmerSectionTitle({bool showTrailing = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(height: 18, width: 150, color: Colors.white),
          if (showTrailing) Container(height: 16, width: 60, color: Colors.white),
        ],
      ),
    );
  }

  // Placeholder for Upcoming Event
  Widget _buildUpcomingPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(12), // Matched padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date Circle placeholder
          // REMOVED DECORATION, kept color for the plain block
          Container(
            width: 50,
            height: 50,
            color: Colors.white,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(height: 15, width: 180, color: Colors.white),
                const SizedBox(height: 4),
                Container(height: 14, width: 100, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Placeholder for Recent Activity Items
  Widget _buildActivityPlaceholder() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon placeholder
          // REMOVED DECORATION, kept color for the plain block
          Container(width: 20, height: 20, color: Colors.white), 
          const SizedBox(width: 12),
          Expanded(
            child: Container(height: 14, width: double.infinity, color: Colors.white),
          ),
          const SizedBox(width: 16),
          // Timestamp placeholder
          Container(height: 12, width: 50, color: Colors.white),
        ],
      ),
    );
  }
}
