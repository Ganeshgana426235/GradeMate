import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:grademate/models/file_models.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

class StudentCoursesPage extends StatefulWidget {
  const StudentCoursesPage({super.key});

  @override
  State<StudentCoursesPage> createState() => _StudentCoursesPageState();
}

class _StudentCoursesPageState extends State<StudentCoursesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  // User Profile Data
  String? _collegeId;
  String? _branch;
  String? _regulation;
  bool _isLoading = true;
  String _searchQuery = '';

  // State for internal navigation
  String? _currentYearId;
  String? _currentSubjectId;
  String? _currentSubjectName;
  String? _expandedYearId;

  List<String> _breadcrumbs = ['Courses'];
  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _loadUserData();
  }

  // --- Core Data Loading ---
  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(user.email).get();
        if (!mounted) return;
        if (userDoc.exists) {
          final data = userDoc.data();
          setState(() {
            _collegeId = data?['collegeId'];
            _branch = data?['branch']?.toString().toUpperCase();
            _regulation = data?['regulation']?.toString().toUpperCase();
          });
        }
      } catch (e) {
        print("Error loading user data for courses: $e");
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // --- View Logic & Navigation ---
  void _navigateToSubject(String yearId, String subjectId, String subjectName) {
    setState(() {
      _currentYearId = yearId;
      _currentSubjectId = subjectId;
      _currentSubjectName = subjectName;
      _breadcrumbs = ['Courses', yearId, subjectName];
    });
  }

  void _navigateBackToCourses() {
    setState(() {
      _currentYearId = null;
      _currentSubjectId = null;
      _currentSubjectName = null;
      _breadcrumbs = ['Courses'];
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isViewingFiles = _currentSubjectId != null;

    return PopScope(
      canPop: !isViewingFiles,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _navigateBackToCourses();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: isViewingFiles
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: _navigateBackToCourses,
                )
              : null,
          title: Text(
            isViewingFiles ? _currentSubjectName! : 'Courses',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              _buildBreadcrumbs(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 20.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                    decoration: InputDecoration(
                      icon: Padding(
                        padding: const EdgeInsets.only(left: 12.0),
                        child: Icon(Icons.search, color: Colors.grey.shade600),
                      ),
                      hintText: isViewingFiles
                          ? 'Search files...'
                          : 'Search subjects...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child:
                    isViewingFiles ? _buildFilesView() : _buildCoursesView(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 4.0,
        runSpacing: 4.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: List.generate(_breadcrumbs.length, (index) {
          final isLast = index == _breadcrumbs.length - 1;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _breadcrumbs[index],
                style: TextStyle(
                  color: isLast
                      ? Theme.of(context).primaryColor
                      : Colors.grey.shade600,
                  fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Icon(Icons.chevron_right,
                      size: 16, color: Colors.grey.shade400),
                ),
            ],
          );
        }),
      ),
    );
  }

  // --- Widget for Courses (Years and Subjects) ---
  Widget _buildCoursesView() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : (_collegeId == null || _branch == null || _regulation == null)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "Could not load course data.\nPlease check that your profile has a College, Branch, and Regulation assigned.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            : StreamBuilder<QuerySnapshot>(
                stream: _getYearsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          "No academic years found for your profile.\n\nPlease check if data exists at this exact path in Firestore (it is case-sensitive):\n\ncolleges/$_collegeId/\nbranches/$_branch/\nregulations/$_regulation/\nyears",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    );
                  }

                  final yearDocs = snapshot.data!.docs;
                  yearDocs.sort((a, b) => a.id.compareTo(b.id));

                  if (_isFirstLoad && yearDocs.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _expandedYearId = yearDocs.first.id;
                          if (_breadcrumbs.length == 1) {
                            _breadcrumbs = ['Courses', yearDocs.first.id];
                          }
                          _isFirstLoad = false;
                        });
                      }
                    });
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: yearDocs.length,
                    itemBuilder: (context, index) {
                      final yearDoc = yearDocs[index];
                      return _buildYearExpansionSection(yearDoc);
                    },
                  );
                },
              );
  }

  Widget _buildYearExpansionSection(DocumentSnapshot yearDoc) {
    final String yearId = yearDoc.id;
    final bool isManuallyExpanded = _expandedYearId == yearId;
    final Color primaryColor = Theme.of(context).primaryColor;

    return Column(
      children: [
        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8.0),
          color: isManuallyExpanded ? primaryColor.withOpacity(0.05) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.0),
            side: BorderSide(
                color: isManuallyExpanded
                    ? primaryColor.withOpacity(0.3)
                    : Colors.grey.shade200),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(15.0),
            onTap: () {
              setState(() {
                if (_searchQuery.isEmpty) {
                  if (isManuallyExpanded) {
                    _expandedYearId = null;
                    if (_currentSubjectId == null) _breadcrumbs = ['Courses'];
                  } else {
                    _expandedYearId = yearId;
                    if (_currentSubjectId == null)
                      _breadcrumbs = ['Courses', yearId];
                  }
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    yearId.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Icon(
                    isManuallyExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: primaryColor,
                  ),
                ],
              ),
            ),
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: yearDoc.reference.collection('subjects').snapshots(),
          builder: (context, subjectSnapshot) {
            final subjectDocs = subjectSnapshot.data?.docs ?? [];
            final bool hasMatch = subjectDocs.any((doc) {
              final subjectName =
                  (doc.data() as Map<String, dynamic>)['name']
                          ?.toString()
                          .toLowerCase() ??
                      '';
              return subjectName.contains(_searchQuery);
            });

            if (_searchQuery.isNotEmpty && !hasMatch) {
              return const SizedBox.shrink();
            }

            final bool isEffectivelyExpanded =
                isManuallyExpanded || (_searchQuery.isNotEmpty && hasMatch);

            return AnimatedSwitcher(
              duration: const Duration(seconds: 1),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              transitionBuilder:
                  (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    child: child,
                  ),
                );
              },
              child: isEffectivelyExpanded
                  ? _buildSubjectsList(subjectDocs, yearId,
                      subjectSnapshot.connectionState)
                  : const SizedBox.shrink(key: ValueKey('empty')),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSubjectsList(List<QueryDocumentSnapshot> subjectDocs,
      String yearName, ConnectionState state) {
    if (state == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.all(20.0),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: subjectDocs.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20.0),
              child: Center(
                child: Text(
                  "No subjects have been added for this year yet.",
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            )
          : AnimationLimiter(
              child: Column(
                children: List.generate(
                  subjectDocs.length,
                  (index) {
                    final doc = subjectDocs[index];
                    return AnimationConfiguration.staggeredList(
                      position: index,
                      duration: const Duration(milliseconds: 375),
                      child: SlideAnimation(
                        verticalOffset: 50.0,
                        child: FadeInAnimation(
                          child: _buildCourseTile(doc, yearName),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  Widget _buildCourseTile(DocumentSnapshot subjectDoc, String yearName) {
    final subjectData = subjectDoc.data() as Map<String, dynamic>;
    final subjectName = subjectData['name'] ?? subjectDoc.id;

    return Card(
      margin: const EdgeInsets.only(top: 8.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToSubject(yearName, subjectDoc.id, subjectName),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, color: Colors.grey.shade600),
              const SizedBox(width: 16),
              Expanded(child: Text(subjectName)),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  // --- Widget for Files View ---
  Widget _buildFilesView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getFilesCollectionRef()
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No files or links found."));
        }

        final allItems = snapshot.data!.docs;
        final currentUserEmail = _auth.currentUser?.email;

        var visibleItems = allItems.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final sharedWith = List<String>.from(data['sharedWith'] ?? []);
          final ownerEmail = data['ownerEmail'];
          return sharedWith.contains('Students') ||
              ownerEmail == currentUserEmail;
        }).toList();

        if (_searchQuery.isNotEmpty) {
          visibleItems = visibleItems.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final title =
                (data['fileName'] ?? data['title'])?.toString().toLowerCase() ??
                    '';
            return title.contains(_searchQuery);
          }).toList();
        }

        if (visibleItems.isEmpty) {
          return Center(
              child: Text(_searchQuery.isEmpty
                  ? "No content has been shared for this subject yet."
                  : "No files match your search."));
        }

        return ListView.builder(
          itemCount: visibleItems.length,
          itemBuilder: (context, index) {
            final doc = visibleItems[index];
            final data = doc.data() as Map<String, dynamic>;
            return data['type'] == 'link'
                ? _buildLinkTile(doc)
                : _buildFileTile(doc);
          },
        );
      },
    );
  }

  Widget _buildFileTile(DocumentSnapshot doc) {
    final fileData = doc.data() as Map<String, dynamic>;
    final size =
        fileData['size'] != null ? _formatBytes(fileData['size']) : '';
    final owner = fileData['ownerName'] ?? 'Unknown';

    FileData createFileObject() {
      return FileData(
        id: doc.id,
        name: fileData['fileName'] ?? 'Untitled',
        url: fileData['fileURL'] ?? '',
        type: fileData['type'] ?? 'unknown',
        size: fileData['size'] ?? 0,
        uploadedAt: fileData['timestamp'] ?? Timestamp.now(),
        ownerId: fileData['uploadedBy'] ?? '',
        ownerName: owner,
      );
    }

    return ListTile(
      leading: Icon(
        _getFileIcon(fileData['type']),
        color: _getColorForFileType(fileData['type']),
        size: 40,
      ),
      title: Text(
        fileData['fileName'] ?? 'Untitled File',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(size.isNotEmpty ? '$owner - $size' : owner),
      onTap: () {
        context.push('/file_viewer', extra: createFileObject());
      },
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'open') {
            context.push('/file_viewer', extra: createFileObject());
          } else if (value == 'add_to_favorites') {
            _addToFavorites(doc);
          } else if (value == 'download') {
            _downloadFile(doc);
          } else if (value == 'share') {
            _shareFile(doc);
          } else if (value == 'details') {
            context.push('/file_details', extra: createFileObject());
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'open', child: Text('Open File')),
          const PopupMenuItem(
              value: 'add_to_favorites', child: Text('Add to Favorites')),
          const PopupMenuItem(value: 'download', child: Text('Download')),
          const PopupMenuItem(value: 'share', child: Text('Share')),
          const PopupMenuItem(value: 'details', child: Text('Details')),
        ],
      ),
    );
  }

  Widget _buildLinkTile(DocumentSnapshot doc) {
    final linkData = doc.data() as Map<String, dynamic>;
    final url = linkData['url'];
    final owner = linkData['ownerName'] ?? 'Unknown';

    return ListTile(
      leading: Icon(
        Icons.link,
        color: _getColorForFileType('link'),
        size: 40,
      ),
      title: Text(
        linkData['title'] ?? 'Web Link',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(owner),
      onTap: () => _openExternalUrl(url),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'open_external') {
            _openExternalUrl(url);
          } else if (value == 'add_to_favorites') {
            _addToFavorites(doc);
          } else if (value == 'share') {
            Share.share('Check out this link: $url');
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
              value: 'open_external', child: Text('Open in Browser')),
          const PopupMenuItem(
              value: 'add_to_favorites', child: Text('Add to Favorites')),
          const PopupMenuItem(value: 'share', child: Text('Share Link')),
        ],
      ),
    );
  }

  // --- Helper and Utility Functions ---

  Future<void> _addToFavorites(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to add favorites.')),
      );
      return;
    }

    try {
      final userRef = _firestore.collection('users').doc(user.email);
      await userRef.update({
        'favorites': FieldValue.arrayUnion([doc.reference.path])
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added to Favorites!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding to favorites: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Stream<QuerySnapshot> _getYearsStream() {
    if (_collegeId == null || _branch == null || _regulation == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection('colleges')
        .doc(_collegeId)
        .collection('branches')
        .doc(_branch)
        .collection('regulations')
        .doc(_regulation)
        .collection('years')
        .snapshots();
  }

  CollectionReference _getFilesCollectionRef() {
    return _firestore
        .collection('colleges')
        .doc(_collegeId)
        .collection('branches')
        .doc(_branch)
        .collection('regulations')
        .doc(_regulation)
        .collection('years')
        .doc(_currentYearId)
        .collection('subjects')
        .doc(_currentSubjectId)
        .collection('files');
  }

  Color _getColorForFileType(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf': return Colors.red.shade700;
      case 'doc': case 'docx': return Colors.blue.shade800;
      case 'ppt': case 'pptx': return Colors.orange.shade700;
      case 'xls': case 'xlsx': return Colors.green.shade700;
      case 'jpg': case 'jpeg': case 'png': case 'gif': return Colors.purple.shade600;
      case 'mp4': case 'mov': case 'avi': return Colors.teal.shade600;
      case 'zip': case 'rar': return Colors.brown.shade600;
      case 'link': return Colors.indigo.shade600;
      default: return Colors.grey.shade700;
    }
  }

  IconData _getFileIcon(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': case 'docx': return Icons.description;
      case 'ppt': case 'pptx': return Icons.slideshow;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'jpg': case 'jpeg': case 'png': case 'gif': return Icons.image;
      case 'mp4': case 'mov': case 'avi': return Icons.movie;
      case 'zip': case 'rar': return Icons.archive;
      default: return Icons.insert_drive_file;
    }
  }

  String _formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  Future<void> _openExternalUrl(String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _downloadFile(DocumentSnapshot doc) async {
    final dio = Dio();
    try {
      final data = doc.data() as Map<String, dynamic>;
      final fileName = data['fileName'];
      final url = data['fileURL'];

      final Directory? downloadsDir = await getExternalStorageDirectory();
      if (downloadsDir == null) {
        throw Exception('Could not get download directory.');
      }

      final gradeMateDir = Directory('${downloadsDir.path}/GradeMate');
      if (!await gradeMateDir.exists()) {
        await gradeMateDir.create(recursive: true);
      }

      final filePath = '${gradeMateDir.path}/$fileName';

      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toInt();
            _showProgressNotification('Downloading', fileName, progress, 2);
          }
        },
      );
      
      if (!mounted) return;
      await _showCompletionNotification('Download Complete', fileName, 2);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('File saved to GradeMate folder!'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      await flutterLocalNotificationsPlugin.cancel(2);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error downloading file: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _shareFile(DocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final fileName = data['fileName'];
      final url = data['fileURL'];

      final dio = Dio();
      final dir = await getTemporaryDirectory();
      final tempFilePath = '${dir.path}/$fileName';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing file for sharing...')));
      
      await dio.download(url, tempFilePath);
      if (!mounted) return;

      await Share.shareXFiles([XFile(tempFilePath)],
          text: 'Check out this file from GradeMate: $fileName');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to share file: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  void _initializeNotifications() {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    flutterLocalNotificationsPlugin.initialize(initSettings);
  }

  Future<void> _showProgressNotification(String title, String fileName,
      int progress, int notificationId) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'progress_channel_id',
      'Progress Channel',
      channelDescription: 'Shows progress of uploads/downloads',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      ongoing: true,
      autoCancel: false,
    );
    final NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      '$fileName: $progress%',
      platformDetails,
    );
  }

  Future<void> _showCompletionNotification(
      String title, String fileName, int notificationId) async {
    await flutterLocalNotificationsPlugin.cancel(notificationId);
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'completion_channel_id',
      'Completion Channel',
      channelDescription: 'Notifies when an operation is finished',
      importance: Importance.high,
      priority: Priority.high,
    );
    final NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      '"$fileName" has finished successfully.',
      platformDetails,
    );
  }
}