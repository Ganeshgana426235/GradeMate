import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:grademate/widgets/bottom_nav_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class FacultyProfilePage extends StatefulWidget {
  const FacultyProfilePage({super.key});

  @override
  State<FacultyProfilePage> createState() => _FacultyProfilePageState();
}

class _FacultyProfilePageState extends State<FacultyProfilePage> {
  int _selectedIndex = 3;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  String? _name;
  String? _email;
  String? _department;
  String? _designation;
  String? _profileImageUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        final docSnapshot =
            await _firestore.collection('users').doc(user.email).get();
        if (mounted && docSnapshot.exists) {
          final data = docSnapshot.data();
          setState(() {
            _name = data?['name'];
            _email = data?['email'];
            _department = data?['department'];
            _designation = data?['designation'];
            _profileImageUrl = data?['profileImageUrl'];
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load profile: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- NEW: Function to show options for changing profile picture ---
  void _showImageSourceActionSheet() {
    // A check to see if a custom profile picture is already set
    bool hasValidImageUrl = _profileImageUrl != null && _profileImageUrl!.isNotEmpty && !_profileImageUrl!.contains("placehold.co");

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _uploadProfileImage();
                },
              ),
              if (hasValidImageUrl) // Only show remove option if a picture exists
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _removeProfileImage();
                  },
                ),
            ],
          ),
        );
      },
    );
  }


  Future<void> _uploadProfileImage() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    // --- PERMISSION HANDLING FIX ---
    // This ensures the permission is explicitly requested before picking.
    final status = await Permission.photos.request();

    if (status.isGranted) {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return;

      if(mounted) setState(() => _isLoading = true);

      try {
        final ref = _storage.ref().child('profile_images').child('${user.uid}.jpg');
        await ref.putFile(File(image.path));
        final url = await ref.getDownloadURL();

        await _firestore.collection('users').doc(user.email).update({
          'profileImageUrl': url,
        });

        if (mounted) {
          setState(() {
            _profileImageUrl = url;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture updated successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload image: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else if (status.isPermanentlyDenied) {
      // If permission is permanently denied, open app settings
      openAppSettings();
    } else {
      // Handle other cases where permission is not granted
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo library access is required to upload an image.')),
        );
      }
    }
  }

  // --- NEW: Function to remove the profile picture ---
  Future<void> _removeProfileImage() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    if(mounted) setState(() => _isLoading = true);
    
    try {
      // Set a placeholder or null in Firestore
      const placeholderUrl = 'https://placehold.co/400x400/000000/FFFFFF/png?text=User'; // Example placeholder
      await _firestore.collection('users').doc(user.email).update({
        'profileImageUrl': placeholderUrl,
      });

      // Delete the old image from Firebase Storage
      final ref = _storage.ref().child('profile_images').child('${user.uid}.jpg');
      await ref.delete();

      if (mounted) {
        setState(() {
          _profileImageUrl = placeholderUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture removed.')),
        );
      }
    } catch (e) {
      // Handle cases where the file might not exist in storage etc.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove image: $e')),
        );
      }
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if(mounted){
       context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasValidImageUrl = _profileImageUrl != null && _profileImageUrl!.isNotEmpty && !_profileImageUrl!.contains("placehold.co");

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            context.go('/faculty_home');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () {
              // TODO: Implement settings functionality
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 240,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(30),
                            bottomRight: Radius.circular(30),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 140,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 70,
                              backgroundColor: Colors.white,
                              child: CircleAvatar(
                                radius: 65,
                                backgroundColor: Colors.grey.shade300,
                                backgroundImage: hasValidImageUrl
                                    ? NetworkImage(_profileImageUrl!)
                                    : null,
                                child: !hasValidImageUrl
                                    ? Icon(Icons.person,
                                        size: 70,
                                        color: Colors.grey.shade600)
                                    : null,
                              ),
                            ),
                            Positioned(
                              bottom: 5,
                              right: 5,
                              child: GestureDetector(
                                // --- CHANGE: Calls the new function to show options ---
                                onTap: _showImageSourceActionSheet,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    shape: BoxShape.circle,
                                  ),
                                  // --- CHANGE: Icon changed from edit to camera_alt ---
                                  child: const Icon(Icons.camera_alt,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(24.0, 80.0, 24.0, 20.0),
                    child: Column(
                      children: [
                         Text(
                          _name ?? 'Faculty Name',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_designation ?? 'Designation'}, ${_department ?? 'Department'}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildInfoCard(
                          context,
                          children: [
                            _buildProfileDetail(
                                Icons.person_outline, 'Name', _name ?? 'Not Set'),
                            const Divider(),
                            _buildProfileDetail(Icons.email_outlined,
                                'Email', _email ?? 'Not Set'),
                            const Divider(),
                            _buildProfileDetail(Icons.work_outline,
                                'Designation', _designation ?? 'Not Set'),
                             const Divider(),
                            _buildProfileDetail(Icons.school_outlined,
                                'Department', _department ?? 'Not Set'),
                          ],
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout),
                          label: const Text('Log Out'),
                           style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red.shade700,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: (index) {
          if (index == 0) {
            context.go('/faculty_home');
          } else if (index == 1) {
            context.go('/faculty_courses');
          } else if (index == 2) {
            context.go('/faculty_my_files');
          } else if (index == 3) {
            // Stay on this page
          }
        },
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context,
      {required List<Widget> children}) {
    return Card(
      elevation: 2,
      shadowColor: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15.0),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  Widget _buildProfileDetail(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade600),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}