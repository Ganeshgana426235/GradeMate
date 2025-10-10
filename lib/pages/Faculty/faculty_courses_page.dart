import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:grademate/widgets/bottom_nav_bar.dart';
import 'dart:io';
import 'dart:math';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

class FacultyCoursesPage extends StatefulWidget {
  const FacultyCoursesPage({super.key});

  @override
  State<FacultyCoursesPage> createState() => _FacultyCoursesPageState();
}

class _FacultyCoursesPageState extends State<FacultyCoursesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  int _selectedIndex = 1;
  String? collegeId;
  String? userRole;
  String? userName;
  bool isLoading = true;

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
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
          if (data != null && data.containsKey('collegeId')) {
            setState(() {
              collegeId = data['collegeId'];
              userRole = data['role'];
              userName = data['name'];
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

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 0) {
      context.go('/faculty_home');
    } else if (index == 1) {
      // Stay on this page
    } else if (index == 2) {
      context.go('/faculty_my_files');
    } else if (index == 3) {
      context.go('/faculty_profile');
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

      await _firestore.collection('colleges').doc(collegeId).update({
        'branches': FieldValue.arrayUnion([shortName]),
      });

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
      batch.update(
          collegeDocRef, {'regulations': FieldValue.arrayUnion([regulationName])});

      await batch.commit();

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
        content: Text(
          'This will add the new year to the "$currentRegulation" regulation for ALL branches.',
          style: TextStyle(color: Colors.grey[600]),
        ),
        actions: [
          TextField(
            controller: yearController,
            decoration: const InputDecoration(
              labelText: 'Year Name (e.g., 1st Year)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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
                    await _addYearToAllBranches(yearController.text.trim());
                    Navigator.pop(context);
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add to All'),
              ),
            ],
          )
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

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        String filePath =
            'courses/$collegeId/$currentBranch/$currentRegulation/$currentYear/$currentSubject/$fileName';
        TaskSnapshot uploadTask = await _storage.ref(filePath).putFile(file);
        String downloadURL = await uploadTask.ref.getDownloadURL();

        await _getFilesCollectionRef().add({
          'type': 'file',
          'fileName': fileName,
          'fileURL': downloadURL,
          'size': fileSize,
          'ownerName': userName ?? 'Unknown',
          'ownerEmail': _auth.currentUser?.email,
          'sharedWith': ['Students', 'Faculty'],
          'uploadedBy': _auth.currentUser?.email,
          'timestamp': FieldValue.serverTimestamp(),
        });

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File uploaded successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading file: $e')),
      );
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

  Future<void> _openFile(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open file: $url')),
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
        TextEditingController(text: fileDoc['fileName']);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: renameController,
          decoration: const InputDecoration(labelText: 'New file name'),
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
                fileDoc.reference
                    .update({'fileName': renameController.text.trim()});
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
          content: Text('Permission Denied: You are not the owner of this item.'),
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
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
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

      if (data['type'] == 'file' && data['fileURL'] != null) {
        await _storage.refFromURL(data['fileURL']).delete();
      }

      await doc.reference.delete();

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
                    _updateAccess(doc, isSharedWithStudents, isSharedWithFaculty);
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
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
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

      for (final docId in _selectedItemIds) {
        final doc = allDocs.firstWhere((d) => d.id == docId);
        final data = doc.data() as Map<String, dynamic>;

        if (data['ownerEmail'] == _auth.currentUser?.email) {
          if (data['type'] == 'file' && data['fileURL'] != null) {
            try {
              await _storage.refFromURL(data['fileURL']).delete();
            } catch (e) {
              print(
                  "Could not delete file from storage (might have been already deleted): $e");
            }
          }
          batch.delete(doc.reference);
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
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: Icon(Icons.folder_copy_outlined,
                    color: Colors.blue[800], size: 32),
                title: Text(
                  branch['name'] ?? 'No Name',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: Text(branch['fullname'] ?? 'No full name provided'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() {
                    currentBranch = branch['name'];
                    breadcrumbs.add(branch['name']);
                  });
                },
              ),
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
        return ListView.builder(
          itemCount: regulations.length,
          itemBuilder: (context, index) {
            var regulation = regulations[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: Icon(Icons.gavel_outlined,
                    color: Colors.orange[800], size: 32),
                title: Text(
                  regulation['name'] ?? regulations[index].id,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() {
                    currentRegulation = regulations[index].id;
                    breadcrumbs.add(regulations[index].id);
                  });
                },
              ),
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
        return ListView.builder(
          itemCount: years.length,
          itemBuilder: (context, index) {
            var year = years[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: Icon(Icons.school_outlined,
                    color: Colors.purple[800], size: 32),
                title: Text(
                  year['name'] ?? years[index].id,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() {
                    currentYear = years[index].id;
                    breadcrumbs.add(years[index].id);
                  });
                },
              ),
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
          return ListView.builder(
            itemCount: subjects.length,
            itemBuilder: (context, index) {
              var subject = subjects[index].data() as Map<String, dynamic>;
              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: Icon(Icons.menu_book_outlined,
                      color: Colors.green[800], size: 32),
                  title: Text(
                    subject['name'] ?? subjects[index].id,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    setState(() {
                      currentSubject = subjects[index].id;
                      breadcrumbs.add(subjects[index].id);
                    });
                  },
                ),
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

        final visibleItems = allItems.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final sharedWith = List<String>.from(data['sharedWith'] ?? []);
          final ownerEmail = data['ownerEmail'];
          return sharedWith.contains('Faculty') || ownerEmail == currentUserEmail;
        }).toList();

        if (visibleItems.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.visibility_off_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No files shared with faculty in this folder.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
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

  Widget _buildFileTile(DocumentSnapshot doc) {
    final fileData = doc.data() as Map<String, dynamic>;
    final size = fileData['size'] != null ? _formatBytes(fileData['size']) : '';
    final owner = fileData['ownerName'] ?? 'Unknown';
    final isSelected = _selectedItemIds.contains(doc.id);

    return Card(
      color: isSelected ? Colors.blue.withOpacity(0.2) : null,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListTile(
        leading: isSelected
            ? const Icon(Icons.check_circle, color: Colors.blue, size: 40)
            : Icon(Icons.article_outlined, color: Colors.blue[800], size: 40),
        title: Text(
          fileData['fileName'] ?? 'Untitled File',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('$size - by $owner'),
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(doc.id);
          } else {
            _openFile(fileData['fileURL']);
          }
        },
        onLongPress: () {
          _toggleSelection(doc.id);
        },
        trailing: !_isSelectionMode
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') _showRenameDialog(doc);
                  if (value == 'delete') _confirmDeleteFile(doc);
                  if (value == 'edit_access') _showEditAccessDialog(doc);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(
                      value: 'edit_access', child: Text('Edit Access')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildLinkTile(DocumentSnapshot doc) {
    final linkData = doc.data() as Map<String, dynamic>;
    final url = linkData['url'];
    final videoId = YoutubePlayer.convertUrlToId(url);
    final isSelected = _selectedItemIds.contains(doc.id);

    Widget buildContent() {
      if (videoId != null) {
        final controller = YoutubePlayerController(
          initialVideoId: videoId,
          flags: const YoutubePlayerFlags(autoPlay: false, mute: false),
        );
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Video Link',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              YoutubePlayer(
                  controller: controller, showVideoProgressIndicator: true),
            ],
          ),
        );
      } else {
        return ListTile(
          leading: isSelected
              ? const Icon(Icons.check_circle, color: Colors.blue, size: 40)
              : Icon(Icons.link, color: Colors.green[800], size: 40),
          title: Text(linkData['title'] ?? 'Web Link'),
          subtitle: Text(url ?? '', overflow: TextOverflow.ellipsis),
        );
      }
    }

    return Card(
      color: isSelected ? Colors.blue.withOpacity(0.2) : null,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(doc.id);
          } else if (videoId == null) {
            _openFile(url);
          }
        },
        onLongPress: () {
          _toggleSelection(doc.id);
        },
        child: buildContent(),
      ),
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
      centerTitle: true,
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
          child:
              Text("Error: College ID not found. Please check user data."),
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
        floatingActionButton: userRole == 'Faculty' && !_isSelectionMode
            ? FloatingActionButton(
                onPressed: () {
                  if (currentSubject != null) {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => Wrap(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.upload_file),
                            title: const Text('Upload File'),
                            onTap: () {
                              Navigator.pop(context);
                              _uploadFile();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.add_link),
                            title: const Text('Add Link'),
                            onTap: () {
                              Navigator.pop(context);
                              _showAddLinkDialog();
                            },
                          ),
                        ],
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
                child: const Icon(Icons.add),
              )
            : null,
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
        bottomNavigationBar: BottomNavBar(
          selectedIndex: _selectedIndex,
          onItemTapped: _onItemTapped,
        ),
      ),
    );
  }
}