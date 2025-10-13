import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({super.key});

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  String? _name;
  String? _email;
  String? _branch;
  String? _year;
  String? _profileImageUrl;
  bool _isLoading = true;

  // --- UPDATED & NEW FIELDS ---
  String? _collegeName;
  String? _regulation;
  String? _rollNo;
  String? _phone;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        // Step 1: Fetch the user's document
        final userDocSnapshot =
            await _firestore.collection('users').doc(user.email).get();

        if (mounted && userDocSnapshot.exists) {
          final data = userDocSnapshot.data();

          // Load direct fields from the user document
          _name = data?['name'];
          _email = data?['email'];
          _branch = data?['branch'];
          _year = data?['year'];
          _profileImageUrl = data?['profileImageUrl'];
          _regulation = data?['regulation'];
          _rollNo = data?['rollNo'];
          _phone = data?['phone'];

          // Step 2: Fetch the college name using collegeId
          final String? collegeId = data?['collegeId'];
          if (collegeId != null && collegeId.isNotEmpty) {
            final collegeDocSnapshot =
                await _firestore.collection('colleges').doc(collegeId).get();
            if (collegeDocSnapshot.exists) {
              _collegeName = collegeDocSnapshot.data()?['name'];
            }
          }

          // Step 3: Update the state with all fetched data
          setState(() {});
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

  void _showImageSourceActionSheet() {
    bool hasValidImageUrl = _profileImageUrl != null &&
        _profileImageUrl!.isNotEmpty &&
        !_profileImageUrl!.contains("placehold.co");

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
              if (hasValidImageUrl)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Remove Photo',
                      style: TextStyle(color: Colors.red)),
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

    final status = await Permission.photos.request();

    if (status.isGranted) {
      final XFile? image =
          await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return;

      if (mounted) setState(() => _isLoading = true);

      try {
        final ref =
            _storage.ref().child('profile_images').child('${user.uid}.jpg');
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
            const SnackBar(
                content: Text('Profile picture updated successfully!')),
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
      openAppSettings();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Photo library access is required to upload an image.')),
        );
      }
    }
  }

  Future<void> _removeProfileImage() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      const placeholderUrl =
          'https://placehold.co/400x400/000000/FFFFFF/png?text=User';
      await _firestore.collection('users').doc(user.email).update({
        'profileImageUrl': placeholderUrl,
      });

      try {
        final ref =
            _storage.ref().child('profile_images').child('${user.uid}.jpg');
        await ref.delete();
      } catch (storageError) {
        print("Could not delete from storage (it may not exist): $storageError");
      }


      if (mounted) {
        setState(() {
          _profileImageUrl = placeholderUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture removed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasValidImageUrl = _profileImageUrl != null &&
        _profileImageUrl!.isNotEmpty &&
        !_profileImageUrl!.contains("placehold.co");

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
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
                                onTap: _showImageSourceActionSheet,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    shape: BoxShape.circle,
                                  ),
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
                          _name ?? 'Student Name',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_year ?? 'Year'}, ${_branch ?? 'Branch'}',
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
                            // --- CARD DETAILS REORDERED AND UPDATED ---
                            _buildProfileDetail(Icons.person_outline, 'Name',
                                _name ?? 'Not Set'),
                            const Divider(),
                            _buildProfileDetail(Icons.email_outlined, 'Email',
                                _email ?? 'Not Set'),
                            const Divider(),
                            _buildProfileDetail(Icons.phone_outlined, 'Phone',
                                _phone ?? 'Not Set'),
                            const Divider(),
                            _buildProfileDetail(Icons.account_balance_outlined,
                                'College', _collegeName ?? 'Not Set'),
                            const Divider(),
                            _buildProfileDetail(Icons.school_outlined,
                                'Branch', _branch ?? 'Not Set'),
                            const Divider(),
                            _buildProfileDetail(Icons.rule_outlined,
                                'Regulation', _regulation ?? 'Not Set'),
                            const Divider(),
                            _buildProfileDetail(Icons.calendar_today_outlined,
                                'Year', _year ?? 'Not Set'),
                            const Divider(),
                            _buildProfileDetail(Icons.badge_outlined,
                                'Roll No', _rollNo ?? 'Not Set'),
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
                // --- LABEL CONVERTED TO UPPERCASE ---
                label.toUpperCase(),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  fontWeight: FontWeight.bold, // Making label bold
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