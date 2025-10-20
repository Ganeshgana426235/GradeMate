import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data'; 
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:grademate/models/file_models.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart'; // NEW: Added for camera functionality

// Primary accent color for consistency
const Color _kPrimaryColor = Color(0xFF6A67FE);
const Color _kDarkBlueBackground = Color(0xFF1B4370);

class FacultyCoursesPage extends StatefulWidget {
  const FacultyCoursesPage({super.key});

  @override
  State<FacultyCoursesPage> createState() => _FacultyCoursesPageState();
}

class _FacultyCoursesPageState extends State<FacultyCoursesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker(); // NEW: Image picker instance
  
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  String? collegeId;
  String? userRole;
  String? userName;
  bool isLoading = true;

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

  final List<String> _availableYears = [
    '1ST YEAR',
    '2ND YEAR',
    '3RD YEAR',
    '4TH YEAR'
  ];

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

  // UPDATED: Centralized method for triggering notifications with new 'type'
  Future<void> _createNotificationTrigger(String type, String title, {String? body}) async {
    if (collegeId == null ||
        currentBranch == null ||
        currentRegulation == null ||
        currentYear == null ||
        currentSubject == null) {
      print("Notification Trigger failed: Missing required course context.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Notification trigger failed: Missing branch, regulation, or year context.'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('notifications_queue')
          .add({
        'type': type, // 'file', 'link', or 'REMINDER'
        'title': title, // file name or reminder title
        'body': body, // reminder body (only for REMINDER type)
        'collegeId': collegeId,
        'branch': currentBranch,
        'regulation': currentRegulation,
        'year': currentYear,
        'subject': currentSubject,
        'uploaderEmail': _auth.currentUser?.email,
        'uploaderName': userName ?? 'Faculty',
        'timestamp': FieldValue.serverTimestamp(),
      });
      print("FCM: Notification trigger created for serverless function. Type: $type");
    } catch (e) {
      print("Error creating notification trigger: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error creating notification trigger: $e'),
            backgroundColor: Colors.red),
      );
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

        recentlyAccessed.remove(fileRefPath);
        recentlyAccessed.insert(0, fileRefPath);

        if (recentlyAccessed.length > 10) {
          recentlyAccessed = recentlyAccessed.sublist(0, 10);
        }

        transaction.update(userRef, {'recentlyAccessed': recentlyAccessed});
      });
    } catch (e) {
      print("Error updating recently accessed: $e");
    }
  }

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

      final collegeRegulationsSnapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .get();

      final allRegulationNames = List<String>.from(
          collegeRegulationsSnapshot.data()?['regulations'] ?? []);

      if (allRegulationNames.isEmpty) {
         throw Exception("No regulations exist to add years to. Please add a regulation first.");
      }


      final batch = _firestore.batch();

      for (final branchDoc in allBranchIds) {
        final regDocRef = _firestore
            .collection('colleges')
            .doc(collegeId)
            .collection('branches')
            .doc(branchDoc)
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
    String? selectedYear;
    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add Year'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will add the selected year to ALL regulations across ALL branches.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedYear,
                  decoration: const InputDecoration(
                    labelText: 'Select Year',
                    border: OutlineInputBorder(),
                  ),
                  items: _availableYears.map((String year) {
                    return DropdownMenuItem<String>(
                      value: year,
                      child: Text(year),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setDialogState(() {
                      selectedYear = newValue;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: selectedYear != null
                    ? () async {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) =>
                              const Center(child: CircularProgressIndicator()),
                        );
                        _addYearToAllRegulations(selectedYear!);
                        Navigator.pop(context); // Pop loading indicator
                        Navigator.pop(context); // Pop add dialog
                      }
                    : null,
                child: const Text('Add to All'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addYearToAllRegulations(String yearName) async {
    if (collegeId == null) return;
    try {
      final branchesSnapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('branches')
          .get();
      final allBranches = branchesSnapshot.docs;

      if (allBranches.isEmpty) {
        throw Exception("No branches exist to add years to.");
      }

      final collegeRegulationsSnapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .get();

      final allRegulationNames = List<String>.from(
          collegeRegulationsSnapshot.data()?['regulations'] ?? []);

      if (allRegulationNames.isEmpty) {
         throw Exception("No regulations exist to add years to. Please add a regulation first.");
      }


      final batch = _firestore.batch();

      for (final branchDoc in allBranches) {
        final branchId = branchDoc.id;

        for (final regName in allRegulationNames) {
          final yearDocRef = _firestore
              .collection('colleges')
              .doc(collegeId)
              .collection('branches')
              .doc(branchId)
              .collection('regulations')
              .doc(regName)
              .collection('years')
              .doc(yearName);
          
          batch.set(yearDocRef, {'name': yearName});
        }
      }

      final collegeDocRef = _firestore.collection('colleges').doc(collegeId);
      batch.update(
          collegeDocRef, {'courseYear': FieldValue.arrayUnion([yearName])});

      await batch.commit();
      _logActivity('Created Year', {
        'yearName': yearName,
        'scope': 'All Branches, All Regulations'
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Year added to all branches and regulations successfully'),
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
    if (currentSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please navigate into a subject folder first.')),
      );
      return;
    }

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
        
        await _createNotificationTrigger('file', fileName); // Triggers NEW MATERIAL notification

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

  // NEW METHOD: Handle image capture and upload
  Future<void> _uploadImageFromCamera(String fileName) async {
    if (currentSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please navigate into a subject folder first.')),
      );
      return;
    }

    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      
      if (photo == null) return;
      
      File file = File(photo.path);
      String fullFileName = '$fileName.jpg'; // Force .jpg extension
      int fileSize = await file.length();

      String filePath =
          'courses/$collegeId/$currentBranch/$currentRegulation/$currentYear/$currentSubject/$fullFileName';
      final uploadTask = _storage.ref(filePath).putFile(file);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes * 100).toInt();
        _showProgressNotification('Uploading', fullFileName, progress, 1);
      });

      final snapshot = await uploadTask.whenComplete(() => {});
      final downloadURL = await snapshot.ref.getDownloadURL();

      await _getFilesCollectionRef().add({
        'type': 'jpg',
        'fileName': fullFileName,
        'fileURL': downloadURL,
        'size': fileSize,
        'ownerName': userName ?? 'Unknown',
        'ownerEmail': _auth.currentUser?.email,
        'sharedWith': ['Students', 'Faculty'],
        'uploadedBy': _auth.currentUser?.email,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _logActivity('Uploaded Image', {'fileName': fullFileName, 'path': filePath});
      await _showCompletionNotification('Upload Complete', fullFileName, 1);
      
      await _createNotificationTrigger('image', fullFileName); 

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image uploaded successfully')),
      );

    } catch (e) {
      await flutterLocalNotificationsPlugin.cancel(1);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }
    }
  }

  // NEW METHOD: Dialog to get filename before opening camera
  Future<void> _showCameraUploadDialog() async {
    final TextEditingController nameController = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name Your Photo'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'File Name (e.g., Class Notes 1)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context); // Close dialog
                _uploadImageFromCamera(nameController.text.trim());
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddLinkDialog() async {
    final linkController = TextEditingController();
    final nameController = TextEditingController(); // Added name controller
    return showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Add a Link'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Link Name (e.g., Official Syllabus)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: linkController,
                    decoration: const InputDecoration(
                      labelText: 'Paste URL here',
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
                    if (linkController.text.isNotEmpty && nameController.text.isNotEmpty) {
                      await _addLink(nameController.text.trim(), linkController.text.trim());
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Add Link'),
                )
              ],
            ));
  }

  Future<void> _addLink(String title, String url) async {
    if (currentSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please navigate into a subject folder first.')),
      );
      return;
    }
    
    try {
      await _getFilesCollectionRef().add({
        'type': 'link',
        'url': url,
        'title': title,
        'ownerName': userName ?? 'Unknown',
        'ownerEmail': _auth.currentUser?.email,
        'sharedWith': ['Students', 'Faculty'],
        'uploadedBy': _auth.currentUser?.email,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _logActivity('Added Link', {'title': title, 'url': url, 'subject': currentSubject});
      
      await _createNotificationTrigger('link', title); // Triggers NEW MATERIAL notification
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding link: $e')),
      );
    }
  }
  
  // NEW METHOD: Shows the dialog for faculty to send a reminder
  Future<void> _showSendReminderDialog(String fileName) async {
    final titleController = TextEditingController(text: "Reminder for '$fileName'");
    final bodyController = TextEditingController(text: "Please review the file '$fileName' before the upcoming test/assignment.");

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Course Reminder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To: Students of $currentBranch, $currentRegulation, $currentYear (Approximate: All students matching course context)',
              style: GoogleFonts.inter(color: Colors.grey[700], fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Notification Title (e.g., Test Preparation)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: bodyController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notification Body (Message)',
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
              if (titleController.text.isNotEmpty && bodyController.text.isNotEmpty) {
                await _sendReminderNotification(titleController.text, bodyController.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Send Reminder'),
          ),
        ],
      ),
    );
  }
  
  // NEW METHOD: Triggers the FCM reminder notification via the queue
  Future<void> _sendReminderNotification(String title, String body) async {
     if (currentSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject context is missing for reminder.')),
      );
      return;
    }
    
    try {
      // Use 'REMINDER' type which the Cloud Function is configured to handle
      await _createNotificationTrigger('REMINDER', title, body: body); 
      
      _logActivity('Sent Faculty Reminder', {
        'title': title, 
        'bodySnippet': body.substring(0, min(body.length, 50)), 
        'subject': currentSubject
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder successfully queued for students!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error queuing reminder: $e'), backgroundColor: Colors.red),
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
  
  // NEW: Collection Reference for Student Material Requests
  CollectionReference _getRequestsCollectionRef() {
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
        .collection('addRequests');
  }

  Future<void> _downloadFile(DocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final fileName = data['fileName'];
      final url = data['fileURL'] ?? data['url'];

      if (url == null) throw Exception("File URL is missing.");

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
      final fileName = data['fileName'] ?? data['title'];
      final url = data['fileURL'] ?? data['url'];

      if (data['type'] == 'link' || url == null) {
        await Share.share('Check out this link from GradeMate: ${data['url']}');
        return;
      }

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
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
            'Are you sure you want to permanently delete "${fileData['fileName'] ?? fileData['title'] ?? fileData['url']}"?'),
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
          deletedCount++;
        } else {
          permissionErrors++;
        }
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

  // --- UI/UX Revisions START ---

  Widget _buildBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(breadcrumbs.length, (index) {
                  final isLast = index == breadcrumbs.length - 1;
                  return Row(
                    children: [
                      GestureDetector(
                        onTap: isLast ? null : () => _navigateToBreadcrumb(index),
                        child: Text(
                          breadcrumbs[index],
                          style: GoogleFonts.inter(
                            color: isLast ? Colors.black87 : _kPrimaryColor,
                            fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (!isLast)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.chevron_right,
                              size: 16, color: Colors.grey[400]),
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

  // New generic tile builder for course hierarchy (Branch, Reg, Year, Subject)
  Widget _buildCourseFolderTile(String name, String subtitle, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          // FIX: Removed boxShadows
        ),
        child: Row(
          children: [
            Icon(icon, color: _kPrimaryColor, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
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
            return _buildCourseFolderTile(
              branch['name'] ?? 'No Name',
              branch['fullname'] ?? 'No full name provided',
              Icons.computer_outlined,
              () {
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
            return _buildCourseFolderTile(
              regulations[index].id,
              'Regulation for ${currentBranch}',
              Icons.rule_outlined,
              () {
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
            final yearName = years[index].id;
            return _buildCourseFolderTile(
              yearName,
              '$currentRegulation - $currentBranch',
              Icons.calendar_today_outlined,
              () {
                setState(() {
                  currentYear = yearName;
                  breadcrumbs.add(yearName);
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
              final subjectName = subjects[index].id;
              return _buildCourseFolderTile(
                subjectName,
                '$currentYear - $currentRegulation',
                Icons.menu_book_outlined,
                () {
                  setState(() {
                    currentSubject = subjectName;
                    breadcrumbs.add(subjectName);
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
                Icon(Icons.insert_drive_file_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  searchQuery.isNotEmpty
                      ? 'No items match your search.'
                      : 'No content found. Tap + to add files or links.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
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
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.movie_outlined;
      case 'zip':
      case 'rar':
        return Icons.archive_outlined;
      case 'link':
        return Icons.link_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Widget _buildFileTile(DocumentSnapshot doc) {
    final fileData = doc.data() as Map<String, dynamic>;
    final size = fileData['size'] != null ? _formatBytes(fileData['size']) : '';
    final owner = fileData['ownerName'] ?? 'Unknown';
    final isSelected = _selectedItemIds.contains(doc.id);
    final isFavorite = _favoriteFilePaths.contains(doc.reference.path);
    final isOwner = fileData['ownerEmail'] == _auth.currentUser?.email;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: isSelected ? _kPrimaryColor.withOpacity(0.1) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: isSelected
            ? Icon(Icons.check_circle, color: _kPrimaryColor, size: 30)
            : Icon(_getFileIcon(fileData['type']),
                color: _kPrimaryColor, size: 30),
        title: Text(
          fileData['fileName'] ?? 'Untitled File',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          size.isNotEmpty ? '$owner - $size' : owner,
          style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 13),
        ),
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
          if (isOwner) _toggleSelection(doc.id);
        },
        trailing: !_isSelectionMode
            ? PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: Colors.grey[600]),
                onSelected: (value) {
                  if (value == 'download') _downloadFile(doc);
                  if (value == 'share') _shareFile(doc);
                  if (value == 'rename') _showRenameDialog(doc);
                  if (value == 'delete') _confirmDeleteFile(doc);
                  if (value == 'edit_access') _showEditAccessDialog(doc);
                  if (value == 'favorite') _toggleFavorite(doc);
                  if (value == 'send_reminder') _showSendReminderDialog(fileData['fileName'] ?? 'this file'); // NEW REMINDER ACTION
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'download', child: Text('Download')),
                  const PopupMenuItem(value: 'share', child: Text('Share')),
                  PopupMenuItem(value: 'favorite', child: Text(isFavorite ? 'Remove from Favorites' : 'Add to Favorites')),
                  if (isOwner) ...[
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'edit_access', child: Text('Edit Access')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                  // NEW REMINDER OPTION
                  const PopupMenuItem(value: 'send_reminder', child: Text('Send Reminder to Students')), 
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildLinkTile(DocumentSnapshot doc) {
    final linkData = doc.data() as Map<String, dynamic>;
    final owner = linkData['ownerName'] ?? 'Unknown';
    final isSelected = _selectedItemIds.contains(doc.id);
    final isFavorite = _favoriteFilePaths.contains(doc.reference.path);
    final isOwner = linkData['ownerEmail'] == _auth.currentUser?.email;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: isSelected ? _kPrimaryColor.withOpacity(0.1) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: isSelected
            ? Icon(Icons.check_circle, color: _kPrimaryColor, size: 30)
            : const Icon(Icons.link, color: Colors.blueAccent, size: 30),
        title: Text(
          linkData['title'] ?? 'Web Link',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          owner,
          style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 13),
        ),
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(doc.id);
          } else {
            _openExternalUrl(doc);
          }
        },
        onLongPress: () {
          if (isOwner) _toggleSelection(doc.id);
        },
        trailing: !_isSelectionMode
            ? PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: Colors.grey[600]),
                onSelected: (value) {
                  if (value == 'open_external') _openExternalUrl(doc);
                  if (value == 'rename') _showRenameDialog(doc);
                  if (value == 'delete') _confirmDeleteFile(doc);
                  if (value == 'edit_access') _showEditAccessDialog(doc);
                  if (value == 'favorite') _toggleFavorite(doc);
                  if (value == 'send_reminder') _showSendReminderDialog(linkData['title'] ?? 'this link'); // NEW REMINDER ACTION
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'open_external', child: Text('Open in Browser')),
                  PopupMenuItem(value: 'favorite', child: Text(isFavorite ? 'Remove from Favorites' : 'Add to Favorites')),
                  if (isOwner) ...[
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'edit_access', child: Text('Edit Access')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                  // NEW REMINDER OPTION
                  const PopupMenuItem(value: 'send_reminder', child: Text('Send Reminder to Students')),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildAddItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Card(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: _kPrimaryColor),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  // --- UI/UX Revisions END ---
  
  // --- NEW FEATURE: Material Request Management ---
  
  // FIX: Changed signature to accept tempStoragePath for robustness
  Future<String> _transferFileToPermanentLocation(String tempFileUrl, String finalFileName, String? tempStoragePath) async {
    try {
      Reference tempRef;
    
      // 1. Get the original storage reference (using the Path or URL)
      if (tempStoragePath != null && tempStoragePath.isNotEmpty) {
        tempRef = _storage.ref().child(tempStoragePath);
      } else {
        tempRef = _storage.refFromURL(tempFileUrl);
      }
      
      // 2. Define the permanent destination path
      final String permanentFilePath = 
          'courses/$collegeId/$currentBranch/$currentRegulation/$currentYear/$currentSubject/$finalFileName';
      
      final Reference permanentRef = _storage.ref().child(permanentFilePath);

      // 3. Download the file data using the public URL
      final String downloadUrl = await tempRef.getDownloadURL();
      final response = await Dio().get(downloadUrl, options: Options(responseType: ResponseType.bytes));
      
      // 4. Re-upload (copy) the data to the new permanent location
      final uploadTask = permanentRef.putData(response.data as Uint8List);
      await uploadTask.whenComplete(() => null);
      
      // 5. Get the new public URL
      final newFileUrl = await permanentRef.getDownloadURL();

      // 6. Delete the temporary file
      await tempRef.delete();
      print("Temp storage file deleted successfully after transfer.");


      return newFileUrl; // Success
      
    } catch (e) {
      print("STORAGE TRANSFER ERROR: $e");
      // Fallback: If transfer fails, return the old URL (or throw, but returning the old URL is safer for testing)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('File transfer failed: $e. File might be inaccessible. (Temp URL used)'),
        backgroundColor: Colors.orange,
      ));
      // Returning the temporary URL as a fail-safe string.
      return tempFileUrl;
    }
  }

  // New method to handle file acceptance
  Future<void> _acceptMaterialRequest(DocumentSnapshot requestDoc) async {
    final requestData = requestDoc.data() as Map<String, dynamic>;

    // Required fields from the request (safe access)
    final fileName = requestData['fileName'] ?? 'Untitled.pdf';
    final requesterName = requestData['requesterName'] ?? 'Student';
    final requesterEmail = requestData['requestedBy'] ?? 'student@example.com';
    final fileType = requestData['fileExtension'] ?? requestData['type'] ?? 'unknown';
    final tempFileUrl = requestData['fileURL'] as String?;
    final fileSize = requestData['size'] ?? 0;
    final tempStoragePath = requestData['storagePath'] as String?; // NEW: Get storage path

    // FIX: Check if the widget is still mounted before proceeding after an async operation.
    if (!mounted) return;
    
    if (tempFileUrl == null || tempFileUrl.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: File URL is missing in request.'), backgroundColor: Colors.red));
       return;
    }

    // 1. Transfer file and get new permanent URL
    // FIX: Use a more readable and unique final file name
    final finalFileName = '${fileName.replaceAll(' ', '_').replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '')}_${DateTime.now().millisecondsSinceEpoch}.${fileType}';

    final newFileUrl = await _transferFileToPermanentLocation(tempFileUrl, finalFileName, tempStoragePath);

    // FIX: Re-check mounted status after the potentially long file transfer operation.
    if (!mounted) return;

    try {
      // 2. Create new document in the subject's main file collection
      await _getFilesCollectionRef().add({
        'type': fileType, 
        'fileName': finalFileName, // Use the new unique file name
        'fileURL': newFileUrl,     // Use the new permanent public URL
        'size': fileSize,
        
        // Ownership details remain with the student (requester)
        'ownerName': requesterName, 
        'ownerEmail': requesterEmail, 
        'uploadedBy': requesterEmail, 
        
        'sharedWith': ['Students', 'Faculty'],
        'approvedBy': _auth.currentUser?.email, 
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 3. Delete the request document
      await requestDoc.reference.delete();

      // 4. Log activity
      _logActivity('Accepted Material Request', {
        'fileName': finalFileName,
        'requester': requesterName,
        'subject': currentSubject
      });
      
      // 5. Trigger new material notification (new logic handles the student path)
      await _createNotificationTrigger('file', finalFileName); 

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File "$finalFileName" approved and added to subject materials.'), backgroundColor: Colors.green),
        );
        // FIX: Ensure Navigator pop is the LAST UI action and check mounted status before it.
        if (Navigator.canPop(context)) Navigator.pop(context); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accepting file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  // New method to handle file rejection
  Future<void> _rejectMaterialRequest(DocumentSnapshot requestDoc) async {
    final requestData = requestDoc.data() as Map<String, dynamic>;
    final tempFileUrl = requestData['fileURL'] as String?;
    final tempStoragePath = requestData['storagePath'] as String?; // NEW: Get storage path
    
    // FIX: Check mounted status early
    if (!mounted) return;

    // Delete the request document
    try {
      // If rejection, we should also delete the temporary file from storage
      if ((tempFileUrl != null && tempFileUrl.isNotEmpty) || (tempStoragePath != null && tempStoragePath.isNotEmpty)) {
         try {
           Reference tempRef;
           if (tempStoragePath != null && tempStoragePath.isNotEmpty) {
             tempRef = _storage.ref().child(tempStoragePath);
           } else if (tempFileUrl != null) {
             // Fallback for older documents that might not have storagePath
             tempRef = _storage.refFromURL(tempFileUrl);
           } else {
             // Should not happen if data is well-formed
             throw Exception("No file reference found for rejection.");
           }
           await tempRef.delete();
           print("Temp storage file deleted successfully on rejection.");
         } catch (e) {
           print("Failed to delete temp storage file on rejection: $e");
         }
      }

      await requestDoc.reference.delete();
      
      _logActivity('Rejected Material Request', {
        'fileName': requestData['fileName'],
        'requester': requestData['requesterName'],
        'subject': currentSubject
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File "${requestData['fileName']}" rejected and removed from requests.'), backgroundColor: Colors.orange),
        );
        // FIX: Ensure Navigator pop is the LAST UI action.
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error rejecting file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // NEW METHOD: Open file from request dialog
  void _openRequestFile(Map<String, dynamic> data) {
    final fileURL = data['fileURL'] as String?;
    final fileName = data['fileName'] as String?;
    final fileType = data['fileType'] as String?;

    if (fileURL == null || fileURL.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open file: URL is missing.')),
      );
      return;
    }

    // FIX: Pass the correct FileData object
    final file = FileData(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // Temporary ID for viewing
      name: fileName ?? 'Request File',
      url: fileURL,
      type: fileType ?? 'unknown',
      size: data['size'] ?? 0,
      uploadedAt: data['timestamp'] ?? Timestamp.now(),
      ownerId: data['requestedBy'] ?? 'request',
      ownerName: data['requesterName'] ?? 'Student',
    );
    
    // Use push to open the viewer with the temporary file object
    context.push('/file_viewer', extra: file);
  }

  // New method to show the material requests dialog
  void _showMaterialRequestsDialog() {
    if (currentSubject == null) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Material Requests: $currentSubject',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
          ),
          content: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 400),
            child: StreamBuilder<QuerySnapshot>(
              stream: _getRequestsCollectionRef()
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error fetching requests: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No new material requests.',
                      style: GoogleFonts.inter(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final fileName = data['fileName'] ?? data['title'] ?? 'Untitled';
                    final requester = data['requesterName'] ?? 'A Student';
                    final fileType = data['fileExtension'] ?? data['type'] ?? 'file';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1,
                      child: ListTile(
                        leading: Icon(_getFileIcon(fileType), color: _kPrimaryColor),
                        title: Text(
                          fileName,
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('Requested by $requester'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // NEW: Open File Button
                            IconButton(
                              icon: const Icon(Icons.open_in_new, color: Colors.blue),
                              tooltip: 'Open File',
                              onPressed: () => _openRequestFile(data),
                            ),
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                              tooltip: 'Accept',
                              onPressed: () => _acceptMaterialRequest(doc),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                              tooltip: 'Reject',
                              onPressed: () => _rejectMaterialRequest(doc),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
  
  // --- END NEW FEATURE ---


  AppBar _buildDefaultAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1, // Added shadow for better distinction
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black),
        onPressed: _navigateBack,
      ),
      title: Text(
        breadcrumbs.last,
        style: GoogleFonts.inter(
          color: Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        // NEW: Material Requests Icon
        if (currentSubject != null && !_isSelectionMode)
          StreamBuilder<QuerySnapshot>(
            stream: _getRequestsCollectionRef().snapshots(),
            builder: (context, snapshot) {
              final count = snapshot.data?.docs.length ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.people_alt_outlined, color: Colors.black),
                    onPressed: _showMaterialRequestsDialog,
                  ),
                    // Badge to show pending requests count
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          '$count',
                          style: GoogleFonts.inter(
                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          
        // Add Content Button
        if (userRole == 'Faculty' && !_isSelectionMode)
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: _kPrimaryColor),
            onPressed: () {
              if (currentSubject != null) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Add Content"),
                    content: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: GridView.count(
                        crossAxisCount: 2,
                        childAspectRatio: 1.5,
                        shrinkWrap: true,
                        children: [
                          _buildAddItem(Icons.upload_file, 'Upload File', () {
                            Navigator.pop(context);
                            _uploadFile();
                          }),
                          _buildAddItem(Icons.camera_alt, 'Camera', () { // NEW CAMERA OPTION
                            Navigator.pop(context);
                            _showCameraUploadDialog();
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

  AppBar _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: _kPrimaryColor,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: () {
          setState(() {
            _isSelectionMode = false;
            _selectedItemIds.clear();
          });
        },
      ),
      title: Text('${_selectedItemIds.length} selected', style: const TextStyle(color: Colors.white)),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.white),
          onPressed: _confirmMultiDelete,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: _navigateBack,
          ),
          title: Text(
            breadcrumbs.last,
            style: GoogleFonts.inter(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            _buildBreadcrumbs(),
            // Search field placeholder
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Expanded(
              child: _FacultyCoursesShimmer(),
            ),
          ],
        ),
      
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
                color: Colors.grey[100], // Lighter background for search bar
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  icon: Icon(Icons.search, color: Colors.grey[600]),
                  hintText: 'Search in ${breadcrumbs.last}',
                  hintStyle: GoogleFonts.inter(color: Colors.grey[600]),
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

// ----------------------------------------------------------------------
// SHIMMER EFFECT WIDGET (Updated for new layout)
// ----------------------------------------------------------------------

class _FacultyCoursesShimmer extends StatelessWidget {
  const _FacultyCoursesShimmer();

  Widget _buildPlaceholderBox({double width = double.infinity, double height = 16, double radius = 8}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildItemTilePlaceholder({bool withSubtitle = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.only(right: 16),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPlaceholderBox(
                  height: 14,
                  width: 180,
                  radius: 6,
                ),
                if (withSubtitle)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: _buildPlaceholderBox(
                      height: 12,
                      width: 120,
                      radius: 6,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
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
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        itemCount: 10,
        itemBuilder: (context, index) {
          return Column(
            children: [
              _buildItemTilePlaceholder(
                withSubtitle: index % 3 != 0,
              ),
              const Divider(height: 1, indent: 60, endIndent: 20, color: Colors.white),
            ],
          );
        },
      ),
    );
  }
}
