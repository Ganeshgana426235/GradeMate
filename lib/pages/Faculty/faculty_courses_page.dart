import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:grademate/models/file_models.dart';

class FacultyCoursesPage extends StatefulWidget {
  const FacultyCoursesPage({super.key});

  @override
  State<FacultyCoursesPage> createState() => _FacultyCoursesPageState();
}

class _FacultyCoursesPageState extends State<FacultyCoursesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  String? collegeId;
  String? userRole;
  String? userName;
  bool isLoading = true;

  // **NEW**: To track user's favorite files
  List<String> _favoriteFilePaths = [];

  // Navigation state
  List<String> breadcrumbs = ['Branches'];
  String? currentBranch;
  String? currentRegulation;
  String? currentYear;
  String? currentSubject;

  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';

  // State for multi-select functionality
  bool _isSelectionMode = false;
  final Set<String> _selectedItemIds = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _initializeNotifications();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initializeNotifications() {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    flutterLocalNotificationsPlugin.initialize(initSettings);
  }

  Future<void> _logActivity(String action, Map<String, dynamic> details) async {
    if (_auth.currentUser == null || _auth.currentUser!.email == null) return;
    final userEmail = _auth.currentUser!.email!;
    final activityData = {
      'userEmail': userEmail,
      'userName': userName ?? 'Unknown',
      'action': action,
      'timestamp': FieldValue.serverTimestamp(),
      'details': details,
    };
    try {
      await _firestore.collection('activities').add(activityData);
      await _firestore
          .collection('users')
          .doc(userEmail)
          .collection('activities')
          .add(activityData);
    } catch (e) {
      print("Error logging activity: $e");
    }
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

  Future<void> _loadUserData() async {
    setState(() {
      isLoading = true;
    });
    try {
      final user = _auth.currentUser;
      if (user != null && user.email != null) {
        final userDocRef = _firestore.collection('users').doc(user.email!);
        final userDoc = await userDocRef.get();
        if (userDoc.exists) {
          final data = userDoc.data();
          if (data != null) {
            setState(() {
              collegeId = data['collegeId'];
              userRole = data['role'];
              userName = data['name'];
              // **NEW**: Load favorite paths
              _favoriteFilePaths =
                  List<String>.from(data['favorites'] ?? []);
              isLoading = false;
            });
          } else {
            setState(() => isLoading = false);
          }
        } else {
          setState(() => isLoading = false);
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      print("Exception while loading user data: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // **NEW**: Adds a file's path to the user's recently accessed list.
  Future<void> _addToRecentlyAccessed(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    final userRef = _firestore.collection('users').doc(user.email);
    final fileRefPath = doc.reference.path;

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);
        final data = snapshot.data();

        List<String> recentlyAccessed = data?['recentlyAccessed'] != null
            ? List<String>.from(data!['recentlyAccessed'])
            : [];

        // Remove if it exists, then add to the front
        recentlyAccessed.remove(fileRefPath);
        recentlyAccessed.insert(0, fileRefPath);

        // Keep the list at a reasonable size (e.g., 10 items)
        if (recentlyAccessed.length > 10) {
          recentlyAccessed = recentlyAccessed.sublist(0, 10);
        }

        transaction.update(userRef, {'recentlyAccessed': recentlyAccessed});
      });
    } catch (e) {
      print("Error updating recently accessed: $e");
    }
  }

  // **NEW**: Adds or removes a file's path from the user's favorites list.
  Future<void> _toggleFavorite(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must be logged in to manage favorites.")),
      );
      return;
    }
    final userRef = _firestore.collection('users').doc(user.email);
    final fileRefPath = doc.reference.path;
    final isFavorite = _favoriteFilePaths.contains(fileRefPath);

    try {
      if (isFavorite) {
        await userRef.update({
          'favorites': FieldValue.arrayRemove([fileRefPath])
        });
        setState(() => _favoriteFilePaths.remove(fileRefPath));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from favorites')),
        );
      } else {
        await userRef.update({
          'favorites': FieldValue.arrayUnion([fileRefPath])
        });
        setState(() => _favoriteFilePaths.add(fileRefPath));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to favorites')),
        );
      }
    } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating favorites: $e')),
      );
    }
  }


  void _navigateBack() {
    setState(() {
      if (_isSelectionMode) {
        _isSelectionMode = false;
        _selectedItemIds.clear();
        return;
      }
      if (currentSubject != null) {
        currentSubject = null;
      } else if (currentYear != null) {
        currentYear = null;
      } else if (currentRegulation != null) {
        currentRegulation = null;
      } else if (currentBranch != null) {
        currentBranch = null;
      } else {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/faculty_home');
        }
        return;
      }
      breadcrumbs.removeLast();
    });
  }

  void _navigateToBreadcrumb(int index) {
    setState(() {
      int levelsToGoBack = (breadcrumbs.length - 1) - index;
      for (int i = 0; i < levelsToGoBack; i++) {
        if (currentSubject != null) {
          currentSubject = null;
        } else if (currentYear != null) {
          currentYear = null;
        } else if (currentRegulation != null) {
          currentRegulation = null;
        } else if (currentBranch != null) {
          currentBranch = null;
        }
        breadcrumbs.removeLast();
      }
    });
  }

  Future<void> _showAddBranchDialog() async {
    final shortNameController = TextEditingController();
    final fullNameController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Branch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: shortNameController,
              decoration: const InputDecoration(
                labelText: 'Short Name (e.g., CSE)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: fullNameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (shortNameController.text.isNotEmpty &&
                  fullNameController.text.isNotEmpty) {
                // **MODIFIED**: Trim and convert to uppercase
                await _addBranch(
                  shortNameController.text.trim().toUpperCase(),
                  fullNameController.text.trim(),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addBranch(String shortName, String fullName) async {
    if (collegeId == null) return;
    try {
      await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('branches')
          .doc(shortName)
          .set({
        'name': shortName,
        'fullname': fullName,
      });

      await _firestore
          .collection('colleges')
          .doc(collegeId)
          .update({'branches': FieldValue.arrayUnion([shortName])});

      _logActivity(
          'Created Branch', {'branchName': shortName, 'fullName': fullName});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Branch added successfully'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error adding branch: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showAddRegulationDialog() async {
    final regulationController = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Regulation to ALL Branches'),
        content: TextField(
          controller: regulationController,
          decoration: const InputDecoration(
            labelText: 'Regulation Name (e.g., R24)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (regulationController.text.isNotEmpty) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) =>
                      const Center(child: CircularProgressIndicator()),
                );
                // **MODIFIED**: Trim and convert to uppercase
                await _addRegulationToAllBranches(
                    regulationController.text.trim().toUpperCase());
                Navigator.pop(context); // Pop loading indicator
                Navigator.pop(context); // Pop add dialog
              }
            },
            child: const Text('Add to All'),
          ),
        ],
      ),
    );
  }

  Future<void> _addRegulationToAllBranches(String regulationName) async {
    if (collegeId == null) return;
    try {
      final branchesSnapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('branches')
          .get();

      final allBranchIds = branchesSnapshot.docs.map((doc) => doc.id).toList();

      if (allBranchIds.isEmpty) {
        throw Exception("No branches exist to add regulations to.");
      }

      final batch = _firestore.batch();

      for (final branchId in allBranchIds) {
        final regDocRef = _firestore
            .collection('colleges')
            .doc(collegeId)
            .collection('branches')
            .doc(branchId)
            .collection('regulations')
            .doc(regulationName);
        batch.set(regDocRef, {'name': regulationName});
      }

      final collegeDocRef = _firestore.collection('colleges').doc(collegeId);
      batch.update(collegeDocRef,
          {'regulations': FieldValue.arrayUnion([regulationName])});

      await batch.commit();
      _logActivity('Created Regulation',
          {'regulationName': regulationName, 'scope': 'All Branches'});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Regulation added to all branches successfully'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error adding regulation: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showAddYearDialog() async {
    final yearController = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Year to "$currentRegulation"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This will add the new year to the "$currentRegulation" regulation for ALL branches.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: yearController,
              decoration: const InputDecoration(
                labelText: 'Year Name (e.g., 1st Year)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (yearController.text.isNotEmpty) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) =>
                      const Center(child: CircularProgressIndicator()),
                );
                // **MODIFIED**: Trim and convert to uppercase
                await _addYearToAllBranches(
                    yearController.text.trim().toUpperCase());
                Navigator.pop(context); // Pop loading indicator
                Navigator.pop(context); // Pop add dialog
              }
            },
            child: const Text('Add to All'),
          ),
        ],
      ),
    );
  }

  Future<void> _addYearToAllBranches(String yearName) async {
    if (collegeId == null || currentRegulation == null) return;
    try {
      final branchesSnapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('branches')
          .get();
      final allBranchIds = branchesSnapshot.docs.map((doc) => doc.id).toList();

      if (allBranchIds.isEmpty) {
        throw Exception("No branches exist to add years to.");
      }

      final batch = _firestore.batch();

      for (final branchId in allBranchIds) {
        final yearDocRef = _firestore
            .collection('colleges')
            .doc(collegeId)
            .collection('branches')
            .doc(branchId)
            .collection('regulations')
            .doc(currentRegulation)
            .collection('years')
            .doc(yearName);
        batch.set(yearDocRef, {'name': yearName});
      }

      final collegeDocRef = _firestore.collection('colleges').doc(collegeId);
      batch.update(
          collegeDocRef, {'courseYear': FieldValue.arrayUnion([yearName])});

      await batch.commit();
      _logActivity('Created Year', {
        'yearName': yearName,
        'regulation': currentRegulation,
        'scope': 'All Branches'
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Year added to all branches successfully'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error adding year: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showAddSubjectDialog() async {
    final subjectController = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Subject'),
        content: TextField(
          controller: subjectController,
          decoration: const InputDecoration(
            labelText: 'Subject Name (e.g., Machine Learning)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (subjectController.text.isNotEmpty) {
                // Subjects can be mixed case, so just trim.
                await _addSubject(subjectController.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addSubject(String subjectName) async {
    if (collegeId == null ||
        currentBranch == null ||
        currentRegulation == null ||
        currentYear == null) return;
    try {
      await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('branches')
          .doc(currentBranch)
          .collection('regulations')
          .doc(currentRegulation)
          .collection('years')
          .doc(currentYear)
          .collection('subjects')
          .doc(subjectName)
          .set({
        'name': subjectName,
      });
      _logActivity('Created Subject', {
        'subjectName': subjectName,
        'branch': currentBranch,
        'regulation': currentRegulation,
        'year': currentYear
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject added successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding subject: $e')),
      );
    }
  }

  Future<void> _uploadFile() async {
    try {
      FilePickerResult? result =
          await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null) {
        File file = File(result.files.single.path!);
        String fileName = result.files.single.name;
        int fileSize = result.files.single.size;
        String fileType = result.files.single.extension ?? '';

        String filePath =
            'courses/$collegeId/$currentBranch/$currentRegulation/$currentYear/$currentSubject/$fileName';
        final uploadTask = _storage.ref(filePath).putFile(file);

        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          final progress =
              (snapshot.bytesTransferred / snapshot.totalBytes * 100).toInt();
          _showProgressNotification('Uploading', fileName, progress, 1);
        });

        final snapshot = await uploadTask.whenComplete(() => {});
        final downloadURL = await snapshot.ref.getDownloadURL();

        await _getFilesCollectionRef().add({
          'type': fileType,
          'fileName': fileName,
          'fileURL': downloadURL,
          'size': fileSize,
          'ownerName': userName ?? 'Unknown',
          'ownerEmail': _auth.currentUser?.email,
          'sharedWith': ['Students', 'Faculty'],
          'uploadedBy': _auth.currentUser?.email,
          'timestamp': FieldValue.serverTimestamp(),
        });

        _logActivity('Uploaded File', {'fileName': fileName, 'path': filePath});
        await _showCompletionNotification('Upload Complete', fileName, 1);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File uploaded successfully')),
        );
      }
    } catch (e) {
      await flutterLocalNotificationsPlugin.cancel(1);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading file: $e')),
        );
      }
    }
  }

  Future<void> _showAddLinkDialog() async {
    final linkController = TextEditingController();
    return showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Add a Link'),
              content: TextField(
                controller: linkController,
                decoration: const InputDecoration(
                  labelText: 'Paste URL here',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    if (linkController.text.isNotEmpty) {
                      await _addLink(linkController.text.trim());
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Add Link'),
                )
              ],
            ));
  }

  Future<void> _addLink(String url) async {
    try {
      await _getFilesCollectionRef().add({
        'type': 'link',
        'url': url,
        'title': url,
        'ownerName': userName ?? 'Unknown',
        'ownerEmail': _auth.currentUser?.email,
        'sharedWith': ['Students', 'Faculty'],
        'uploadedBy': _auth.currentUser?.email,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _logActivity('Added Link', {'url': url, 'subject': currentSubject});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding link: $e')),
      );
    }
  }

  CollectionReference _getFilesCollectionRef() {
    return _firestore
        .collection('colleges')
        .doc(collegeId)
        .collection('branches')
        .doc(currentBranch)
        .collection('regulations')
        .doc(currentRegulation)
        .collection('years')
        .doc(currentYear)
        .collection('subjects')
        .doc(currentSubject)
        .collection('files');
  }

  Future<void> _downloadFile(DocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final fileName = data['fileName'];
      final url = data['fileURL'];

      final dio = Dio();
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

      await _showCompletionNotification('Download Complete', fileName, 2);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('File saved to GradeMate folder!'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      await flutterLocalNotificationsPlugin.cancel(2);
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

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing file for sharing...')));
      await dio.download(url, tempFilePath);

      await Share.shareXFiles([XFile(tempFilePath)],
          text: 'Check out this file from GradeMate: $fileName');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to share file: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openExternalUrl(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final url = data['url'];

    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: URL is missing or invalid.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // **NEW**: Add to recently accessed when opened.
    await _addToRecentlyAccessed(doc);

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open URL: $url')),
      );
    }
  }

  Future<void> _showRenameDialog(DocumentSnapshot fileDoc) async {
    final fileData = fileDoc.data() as Map<String, dynamic>;
    final ownerEmail = fileData['ownerEmail'];

    if (ownerEmail != _auth.currentUser?.email) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Permission Denied: You cannot rename this file.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    final renameController =
        TextEditingController(text: fileData['fileName'] ?? fileData['title']);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename ${fileData['type'] == 'link' ? 'Link' : 'File'}'),
        content: TextField(
          controller: renameController,
          decoration: const InputDecoration(labelText: 'New name'),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: const Text('Rename'),
            onPressed: () {
              if (renameController.text.isNotEmpty) {
                final newName = renameController.text.trim();
                final oldName = fileData['fileName'] ?? fileData['title'];
                final fieldToUpdate =
                    fileData['type'] == 'link' ? 'title' : 'fileName';

                fileDoc.reference.update({fieldToUpdate: newName});
                _logActivity('Renamed Item', {
                  'oldName': oldName,
                  'newName': newName,
                  'type': fileData['type']
                });
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteFile(DocumentSnapshot fileDoc) async {
    final fileData = fileDoc.data() as Map<String, dynamic>;
    final ownerEmail = fileData['ownerEmail'];

    if (ownerEmail != _auth.currentUser?.email) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Permission Denied: You are not the owner of this item.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text(
            'Are you sure you want to permanently delete "${fileData['fileName'] ?? fileData['url']}"?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteItem(fileDoc);
    }
  }

  Future<void> _deleteItem(DocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>;

      if (data['type'] != 'link' && data['fileURL'] != null) {
        await _storage.refFromURL(data['fileURL']).delete();
      }

      await doc.reference.delete();

      final itemName = data['fileName'] ?? data['title'] ?? data['url'];
      _logActivity(
          'Deleted Item', {'itemName': itemName, 'type': data['type']});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting item: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showEditAccessDialog(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final ownerEmail = data['ownerEmail'];

    if (ownerEmail != _auth.currentUser?.email) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Permission Denied: You are not the owner.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    List<dynamic> sharedWith = data['sharedWith'] ?? [];
    bool isSharedWithStudents = sharedWith.contains('Students');
    bool isSharedWithFaculty = sharedWith.contains('Faculty');

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Access'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Share with Students'),
                    value: isSharedWithStudents,
                    onChanged: (bool value) {
                      setDialogState(() {
                        isSharedWithStudents = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Share with Faculty'),
                    value: isSharedWithFaculty,
                    onChanged: (bool value) {
                      setDialogState(() {
                        isSharedWithFaculty = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  child: const Text('Save'),
                  onPressed: () {
                    _updateAccess(
                        doc, isSharedWithStudents, isSharedWithFaculty);
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateAccess(DocumentSnapshot doc, bool shareWithStudents,
      bool shareWithFaculty) async {
    try {
      List<String> newSharedWith = [];
      if (shareWithStudents) {
        newSharedWith.add('Students');
      }
      if (shareWithFaculty) {
        newSharedWith.add('Faculty');
      }
      await doc.reference.update({'sharedWith': newSharedWith});

      final itemName = (doc.data() as Map<String, dynamic>)['fileName'] ??
          (doc.data() as Map<String, dynamic>)['title'] ??
          'Unknown Item';
      _logActivity(
          'Edited Access', {'itemName': itemName, 'sharedWith': newSharedWith});

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Access updated successfully'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to update access: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  String _formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  void _toggleSelection(String docId) {
    setState(() {
      if (_selectedItemIds.contains(docId)) {
        _selectedItemIds.remove(docId);
        if (_selectedItemIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _isSelectionMode = true;
        _selectedItemIds.add(docId);
      }
    });
  }

  Future<void> _confirmMultiDelete() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_selectedItemIds.length} Items?'),
        content: const Text(
            'Are you sure you want to permanently delete these items? This action cannot be undone.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final allDocsQuery = await _getFilesCollectionRef().get();
      final allDocs = allDocsQuery.docs;
      final batch = _firestore.batch();
      int deletedCount = 0;
      int permissionErrors = 0;
      final List<String> deletedItemsNames = [];

      for (final docId in _selectedItemIds) {
        final doc = allDocs.firstWhere((d) => d.id == docId);
        final data = doc.data() as Map<String, dynamic>;

        if (data['ownerEmail'] == _auth.currentUser?.email) {
          deletedItemsNames
              .add(data['fileName'] ?? data['title'] ?? 'Unknown Item');
          if (data['type'] != 'link' && data['fileURL'] != null) {
            try {
              await _storage.refFromURL(data['fileURL']).delete();
            } catch (e) {
              print(
                  "Could not delete file from storage (already deleted?): $e");
            }
          }
          batch.delete(doc.reference);
          deletedCount++;
        } else {
          permissionErrors++;
        }
      }

      if (deletedItemsNames.isNotEmpty) {
        _logActivity('Deleted Multiple Items',
            {'count': deletedItemsNames.length, 'items': deletedItemsNames});
      }

      await batch.commit();

      String message = '$deletedCount items deleted.';
      if (permissionErrors > 0) {
        message += ' $permissionErrors items skipped (not owner).';
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ));

      setState(() {
        _isSelectionMode = false;
        _selectedItemIds.clear();
      });
    }
  }

  Widget _buildBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(breadcrumbs.length, (index) {
                  return Row(
                    children: [
                      GestureDetector(
                        onTap: () => _navigateToBreadcrumb(index),
                        child: Text(
                          breadcrumbs[index],
                          style: TextStyle(
                            color: index == breadcrumbs.length - 1
                                ? Colors.blue[800]
                                : Colors.grey[600],
                            fontWeight: index == breadcrumbs.length - 1
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (index < breadcrumbs.length - 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.chevron_right,
                              size: 16, color: Colors.grey[600]),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchesView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('branches')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text("Error: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No branches found. Tap + to add one.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }

        var branches = snapshot.data!.docs;
        if (searchQuery.isNotEmpty) {
          branches = branches.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = data['name']?.toString().toLowerCase() ?? '';
            final fullname = data['fullname']?.toString().toLowerCase() ?? '';
            return name.contains(searchQuery.toLowerCase()) ||
                fullname.contains(searchQuery.toLowerCase());
          }).toList();
        }

        return ListView.builder(
          itemCount: branches.length,
          itemBuilder: (context, index) {
            var branch = branches[index].data() as Map<String, dynamic>;
            return ListTile(
              leading: const Icon(Icons.folder, color: Colors.blue, size: 40),
              title: Text(
                branch['name'] ?? 'No Name',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(branch['fullname'] ?? 'No full name provided'),
              onTap: () {
                setState(() {
                  currentBranch = branch['name'];
                  breadcrumbs.add(branch['name']);
                });
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRegulationsView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('branches')
          .doc(currentBranch)
          .collection('regulations')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text("Error: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.rule_folder_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No regulations found. Tap + to add one.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }

        var regulations = snapshot.data!.docs;
        if (searchQuery.isNotEmpty) {
          regulations = regulations.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = data['name']?.toString().toLowerCase() ?? '';
            return name.contains(searchQuery.toLowerCase());
          }).toList();
        }

        return ListView.builder(
          itemCount: regulations.length,
          itemBuilder: (context, index) {
            var regulation = regulations[index].data() as Map<String, dynamic>;
            return ListTile(
              leading: const Icon(Icons.folder, color: Colors.blue, size: 40),
              title: Text(
                regulation['name'] ?? regulations[index].id,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () {
                setState(() {
                  currentRegulation = regulations[index].id;
                  breadcrumbs.add(regulations[index].id);
                });
              },
            );
          },
        );
      },
    );
  }

  Widget _buildYearsView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('branches')
          .doc(currentBranch)
          .collection('regulations')
          .doc(currentRegulation)
          .collection('years')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text("Error: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No years found. Tap + to add one.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }
        var years = snapshot.data!.docs;
        if (searchQuery.isNotEmpty) {
          years = years.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = data['name']?.toString().toLowerCase() ?? '';
            return name.contains(searchQuery.toLowerCase());
          }).toList();
        }

        return ListView.builder(
          itemCount: years.length,
          itemBuilder: (context, index) {
            var year = years[index].data() as Map<String, dynamic>;
            return ListTile(
              leading: const Icon(Icons.folder, color: Colors.blue, size: 40),
              title: Text(
                year['name'] ?? years[index].id,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () {
                setState(() {
                  currentYear = years[index].id;
                  breadcrumbs.add(years[index].id);
                });
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSubjectsView() {
    return StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('colleges')
            .doc(collegeId)
            .collection('branches')
            .doc(currentBranch)
            .collection('regulations')
            .doc(currentRegulation)
            .collection('years')
            .doc(currentYear)
            .collection('subjects')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text("Error: ${snapshot.error}",
                    style: const TextStyle(color: Colors.red)));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.book_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No subjects found. Tap + to add one.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            );
          }

          var subjects = snapshot.data!.docs;
          if (searchQuery.isNotEmpty) {
            subjects = subjects.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final name = data['name']?.toString().toLowerCase() ?? '';
              return name.contains(searchQuery.toLowerCase());
            }).toList();
          }

          return ListView.builder(
            itemCount: subjects.length,
            itemBuilder: (context, index) {
              var subject = subjects[index].data() as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.folder, color: Colors.blue, size: 40),
                title: Text(
                  subject['name'] ?? subjects[index].id,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  setState(() {
                    currentSubject = subjects[index].id;
                    breadcrumbs.add(subjects[index].id);
                  });
                },
              );
            },
          );
        });
  }

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
          return Center(
              child: Text("Error: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.insert_drive_file_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No content found. Tap + to add files or links.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16)),
              ],
            ),
          );
        }

        final allItems = snapshot.data!.docs;
        final currentUserEmail = _auth.currentUser?.email;

        var visibleItems = allItems.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final sharedWith = List<String>.from(data['sharedWith'] ?? []);
          final ownerEmail = data['ownerEmail'];
          return sharedWith.contains('Faculty') ||
              ownerEmail == currentUserEmail;
        }).toList();

        if (searchQuery.isNotEmpty) {
          visibleItems = visibleItems.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final title =
                (data['fileName'] ?? data['title'])?.toString().toLowerCase() ??
                    '';
            return title.contains(searchQuery.toLowerCase());
          }).toList();
        }

        if (visibleItems.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No items match your search.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: visibleItems.length,
          itemBuilder: (context, index) {
            final doc = visibleItems[index];
            final data = doc.data() as Map<String, dynamic>;

            if (data['type'] == 'link') {
              return _buildLinkTile(doc);
            } else {
              return _buildFileTile(doc);
            }
          },
        );
      },
    );
  }

  IconData _getFileIcon(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.movie;
      case 'zip':
      case 'rar':
        return Icons.archive;
      default:
        return Icons.insert_drive_file;
    }
  }

  Widget _buildFileTile(DocumentSnapshot doc) {
    final fileData = doc.data() as Map<String, dynamic>;
    final size = fileData['size'] != null ? _formatBytes(fileData['size']) : '';
    final owner = fileData['ownerName'] ?? 'Unknown';
    final isSelected = _selectedItemIds.contains(doc.id);
    final isFavorite = _favoriteFilePaths.contains(doc.reference.path);

    return ListTile(
      leading: isSelected
          ? const Icon(Icons.check_circle, color: Colors.blue, size: 40)
          : Icon(_getFileIcon(fileData['type']),
              color: Colors.blue, size: 40),
      title: Text(
        fileData['fileName'] ?? 'Untitled File',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(size.isNotEmpty ? '$owner - $size' : owner),
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(doc.id);
        } else {
          final fileURL = fileData['fileURL'] as String?;
          if (fileURL == null || fileURL.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot open file: URL is missing.'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }

          _addToRecentlyAccessed(doc);
          final file = FileData(
            id: doc.id,
            name: fileData['fileName'] ?? 'Untitled',
            url: fileURL,
            type: fileData['type'] ?? 'unknown',
            size: fileData['size'] ?? 0,
            uploadedAt: fileData['timestamp'] ?? Timestamp.now(),
            ownerId: fileData['uploadedBy'] ?? '',
            ownerName: owner,
          );
          context.push('/file_viewer', extra: file);
        }
      },
      onLongPress: () {
        _toggleSelection(doc.id);
      },
      trailing: !_isSelectionMode
          ? PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'download') _downloadFile(doc);
                if (value == 'share') _shareFile(doc);
                if (value == 'rename') _showRenameDialog(doc);
                if (value == 'delete') _confirmDeleteFile(doc);
                if (value == 'edit_access') _showEditAccessDialog(doc);
                if (value == 'favorite') _toggleFavorite(doc);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'download', child: Text('Download')),
                const PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'favorite', child: Text(isFavorite ? 'Remove from Favorites' : 'Add to Favorites')),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(
                    value: 'edit_access', child: Text('Edit Access')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            )
          : null,
    );
  }

  Widget _buildLinkTile(DocumentSnapshot doc) {
    final linkData = doc.data() as Map<String, dynamic>;
    final owner = linkData['ownerName'] ?? 'Unknown';
    final isSelected = _selectedItemIds.contains(doc.id);
    final isFavorite = _favoriteFilePaths.contains(doc.reference.path);

    return ListTile(
      tileColor: isSelected ? Colors.blue.withOpacity(0.2) : null,
      leading: isSelected
          ? const Icon(Icons.check_circle, color: Colors.blue, size: 40)
          : const Icon(Icons.link, color: Colors.blue, size: 40),
      title: Text(
        linkData['title'] ?? 'Web Link',
        style: const TextStyle(fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(owner),
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(doc.id);
        } else {
          _openExternalUrl(doc);
        }
      },
      onLongPress: () => _toggleSelection(doc.id),
      trailing: !_isSelectionMode
          ? PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'open_external') _openExternalUrl(doc);
                if (value == 'rename') _showRenameDialog(doc);
                if (value == 'delete') _confirmDeleteFile(doc);
                if (value == 'edit_access') _showEditAccessDialog(doc);
                if (value == 'favorite') _toggleFavorite(doc);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                    value: 'open_external', child: Text('Open in Browser')),
                PopupMenuItem(value: 'favorite', child: Text(isFavorite ? 'Remove from Favorites' : 'Add to Favorites')),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(
                    value: 'edit_access', child: Text('Edit Access')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            )
          : null,
    );
  }

  AppBar _buildDefaultAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black),
        onPressed: _navigateBack,
      ),
      title: Text(
        breadcrumbs.last,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        if (userRole == 'Faculty' && !_isSelectionMode)
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.black),
            onPressed: () {
              if (currentSubject != null) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Add Content"),
                    content: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      height: MediaQuery.of(context).size.height * 0.2,
                      child: GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        children: [
                          _buildAddItem(Icons.upload_file, 'Upload File', () {
                            Navigator.pop(context);
                            _uploadFile();
                          }),
                          _buildAddItem(Icons.add_link, 'Add Link', () {
                            Navigator.pop(context);
                            _showAddLinkDialog();
                          }),
                        ],
                      ),
                    ),
                  ),
                );
              } else if (currentYear != null) {
                _showAddSubjectDialog();
              } else if (currentRegulation != null) {
                _showAddYearDialog();
              } else if (currentBranch != null) {
                _showAddRegulationDialog();
              } else {
                _showAddBranchDialog();
              }
            },
          )
      ],
      centerTitle: true,
    );
  }

  Widget _buildAddItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: Colors.blue[800]),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: Colors.blue[700],
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () {
          setState(() {
            _isSelectionMode = false;
            _selectedItemIds.clear();
          });
        },
      ),
      title: Text('${_selectedItemIds.length} selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: _confirmMultiDelete,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (collegeId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Courses")),
        body: const Center(
          child: Text("Error: College ID not found. Please check user data."),
        ),
      );
    }

    return PopScope(
      canPop: currentBranch == null && !_isSelectionMode,
      onPopInvoked: (bool didPop) {
        if (!didPop) _navigateBack();
      },
      child: Scaffold(
        appBar: _isSelectionMode && currentSubject != null
            ? _buildSelectionAppBar()
            : _buildDefaultAppBar(),
        body: Column(
          children: [
            _buildBreadcrumbs(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search, color: Colors.grey),
                    hintText: 'Search',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    setState(() {
                      searchQuery = value;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: currentSubject != null
                  ? _buildFilesView()
                  : currentYear != null
                      ? _buildSubjectsView()
                      : currentRegulation != null
                          ? _buildYearsView()
                          : currentBranch != null
                              ? _buildRegulationsView()
                              : _buildBranchesView(),
            ),
          ],
        ),
      ),
    );
  }
}

