import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
// NOTE: We are replacing image_picker logic with file_picker. You must ensure file_picker is in pubspec.yaml
import 'package:file_picker/file_picker.dart'; 
import 'package:permission_handler/permission_handler.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';

// Ensure ImagePicker is only used if absolutely necessary, but we'll import it 
// in case it's used elsewhere (we'll remove the unused import here for clarity)
// import 'package:image_picker/image_picker.dart'; 


class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({super.key});

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // Removed ImagePicker instance, now using FilePicker statically.
  // final ImagePicker _picker = ImagePicker(); 

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
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
                title: const Text('Choose from Gallery (File Picker)'),
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

    // Use FilePicker to select an image file
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File picker error: $e')),
        );
      }
      return;
    }

    if (result == null || result.files.single.path == null) {
      return; // User canceled the picker
    }
    
    final filePath = result.files.single.path!;
    final fileExtension = result.files.single.extension?.toLowerCase() ?? 'jpg';

    if (mounted) setState(() => _isLoading = true);

    try {
      final ref =
          _storage.ref().child('profile_images').child('${user.uid}.$fileExtension'); 
      await ref.putFile(File(filePath));
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
        // Attempt to delete the file regardless of extension
        final ref =
            _storage.ref().child('profile_images').child('${user.uid}');
        // We cannot reliably delete without the extension, so we rely on the DB update.
      } catch (storageError) {
        //prin("Could not delete from storage (it may not exist): $storageError");
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
  
  // --- NEW: Edit Profile Data Request Dialog and Submission ---
  Future<void> _showEditProfileDialog() async {
    final Map<String, String> fields = {
      'name': 'Name',
      'phone': 'Phone',
      'college': 'College',
      'branch': 'Branch',
      'regulation': 'Regulation',
      'year': 'Year',
      'rollNo': 'Roll No',
    };
    String? selectedField;
    final valueController = TextEditingController();
    final user = _auth.currentUser;

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to submit a request.')),
        );
      }
      return;
    }

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isButtonEnabled = selectedField != null && valueController.text.trim().isNotEmpty;
            
            return AlertDialog(
              title: const Text('Request Profile Update'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select the detail you want to change:', style: GoogleFonts.inter(fontSize: 14)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedField,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Field to Update',
                      ),
                      items: fields.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedField = value;
                          valueController.clear();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: valueController,
                      onChanged: (value) => setDialogState(() {}), // Trigger state rebuild for button
                      decoration: InputDecoration(
                        labelText: 'New Value for ${fields[selectedField] ?? 'Selected Field'}',
                        border: const OutlineInputBorder(),
                      ),
                      enabled: selectedField != null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isButtonEnabled
                      ? () {
                          _submitProfileUpdateRequest(selectedField!, valueController.text.trim());
                          Navigator.of(context).pop();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A67FE),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Submit Request'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitProfileUpdateRequest(String field, String newValue) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    final fieldName = {
      'name': 'Name', 'phone': 'Phone', 'college': 'College', 
      'branch': 'Branch', 'regulation': 'Regulation', 'year': 'Year', 'rollNo': 'Roll No'
    }[field] ?? 'Unknown Field';
    
    final ticketData = {
      'title': 'Profile Update Request: $fieldName',
      'body': 'User $_name requested to change $fieldName to: "$newValue". Please verify and update their profile.',
      'userEmail': user.email,
      'userName': _name ?? 'Student',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'Profile Update Pending',
      'requestedField': field,
      'newValue': newValue,
    };
    
    try {
      await _firestore.collection('help_support_tickets').add(ticketData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update request submitted successfully! It will be reviewed, and we will update you soon.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit request: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  // --- NEW: Password Change Dialog and Submission ---
  Future<void> _showPasswordChangeDialog() async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final user = _auth.currentUser;

    if (user == null || user.email == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication required to change password.')),
        );
      }
      return;
    }

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                decoration: const InputDecoration(labelText: 'Old Password', border: OutlineInputBorder()),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder()),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                decoration: const InputDecoration(labelText: 'Confirm New Password', border: OutlineInputBorder()),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _updatePassword(
                user,
                oldPasswordController.text,
                newPasswordController.text,
                confirmPasswordController.text,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A67FE),
                foregroundColor: Colors.white,
              ),
              child: const Text('Update Password'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updatePassword(User user, String oldPassword, String newPassword, String confirmPassword) async {
    if (newPassword != confirmPassword) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New passwords do not match.'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (newPassword.length < 6) {
        if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password must be at least 6 characters long.'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    try {
      // Re-authenticate user with their current password
      final cred = EmailAuthProvider.credential(email: user.email!, password: oldPassword);
      await user.reauthenticateWithCredential(cred);

      // Update the password
      await user.updatePassword(newPassword);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully!'), backgroundColor: Colors.green),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        String message = 'Failed to update password.';
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          message = 'The old password you entered is incorrect.';
        } else if (e.code == 'requires-recent-login') {
          message = 'Please log out and log back in to change your password.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unexpected error occurred: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }


  // --- NEW: Help & Support Dialog and Submission (MOVED HERE TO FIX SCOPE ERROR) ---
  Future<void> _submitHelpTicket(String title, String body) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;
    
    final ticketData = {
      'title': title,
      'body': body,
      'userEmail': user.email,
      'userName': _name ?? 'Student',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'Open',
    };
    
    try {
      await _firestore.collection('help_support_tickets').add(ticketData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket submitted successfully! It will be reviewed, and we will update you soon.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit ticket: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }


  // --- NEW: Help & Support Dialog (REMAINS THE SAME) ---
  Future<void> _showHelpSupportDialog() async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    int charCount = 0;
    const int maxChars = 500;
    final user = _auth.currentUser;

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to submit a ticket.')),
        );
      }
      return;
    }

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Submit Help Ticket'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Ticket Title / Subject',
                        border: OutlineInputBorder(),
                        hintText: 'e.g., File upload error'
                      ),
                      maxLength: 100, // Reasonable max length for title
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: bodyController,
                      keyboardType: TextInputType.multiline,
                      minLines: 4,
                      maxLines: 8,
                      onChanged: (value) {
                        setDialogState(() {
                          charCount = value.length;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Details / Description',
                        border: const OutlineInputBorder(),
                        hintText: 'Describe your issue...',
                        counterText: '$charCount/$maxChars',
                      ),
                      maxLength: maxChars,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: titleController.text.trim().isNotEmpty && bodyController.text.trim().isNotEmpty
                      ? () {
                          _submitHelpTicket(titleController.text.trim(), bodyController.text.trim());
                          Navigator.of(context).pop();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A67FE),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- NEW: Account Settings Sheet containing Password Change ---
  void _showAccountSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Account Settings',
                  style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              // Password Change Option
              ListTile(
                leading: const Icon(Icons.lock_outline, color: Color(0xFF6A67FE)),
                title: const Text('Change Password'),
                subtitle: const Text('Update your login credentials'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context); // Close sheet
                  _showPasswordChangeDialog(); // Open password dialog
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
}

  // --- NEW: FAQ Dialog (REMAINS THE SAME) ---
  void _showFaqsDialog() {
    final faqs = [
      {'q': 'How do I upload files?', 'a': 'You can upload files directly from the My Files section by tapping the upload icon in the top right corner. Ensure your file is study-related.'},
      {'q': 'Why can\'t I see my course materials?', 'a': 'Course materials are shared by your faculty. If you are missing courses, please ensure your college, branch, and regulation details are correct on this profile page. Contact your faculty if the issue persists.'},
      {'q': 'How is my profile image used?', 'a': 'Your profile image is used for personalized identification within the app and is visible to faculty members for communication purposes. It is not shared externally.'},
      {'q': 'Where are my uploaded files stored?', 'a': 'All your files are securely stored on our cloud storage service, linked to your user account. You can access them anytime via the My Files tab.'},
      {'q': 'How do I add a file to a reminder?', 'a': 'In the Subject Files page or My Files page, tap the options menu (...) next to a file and select "Add to Reminder". You can set the date, time, and description there.'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Frequently Asked Questions',
                    style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: faqs.length,
                    itemBuilder: (context, index) {
                      final faq = faqs[index];
                      return ExpansionTile(
                        title: Text(faq['q']!, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16)),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0),
                            child: Text(faq['a']!, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade700)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool hasValidImageUrl = _profileImageUrl != null &&
        _profileImageUrl!.isNotEmpty &&
        !_profileImageUrl!.contains("placehold.co");

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: _isLoading
          ? const _ProfilePageShimmer() // Show Shimmer during loading
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  // --- HEADER SECTION (Top Card and Profile Details) ---
                  _buildHeaderSection(context, hasValidImageUrl),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        
                        // --- STUDENT DETAILS CARD ---
                        Text(
                          'Student details',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildStudentDetailsCard(context),
                        
                        const SizedBox(height: 24),
                        
                        // --- SUPPORT & INFO CARD ---
                        Text(
                          'Support & info',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildSupportInfoCard(context),

                        const SizedBox(height: 24),
                        
                        // --- LOGOUT BUTTON ---
                        _buildLogoutButton(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ----------------------------------------------------------------------
  // UI COMPONENT BUILDERS
  // ----------------------------------------------------------------------
  
  // UPDATED: Builds the entire top section with profile image and background
  Widget _buildHeaderSection(BuildContext context, bool hasValidImageUrl) {
    // Define the size for the inner CircleAvatar (image) and the outer background
    const double imageRadius = 55; // Increased size
    const double backgroundRadius = imageRadius + 15; // Outer circle size
    const Color primaryBlue = Color(0xFF6A67FE);
    const Color darkBlueBackground = Color(0xFF1B4370); // Darker blue for the entire background container

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 40, bottom: 20, left: 16, right: 16),
      decoration: const BoxDecoration(
        color: primaryBlue, // Applying the primary blue color to the entire top section
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
      ),
      child: Column(
        children: [
          // AppBar actions: REMOVED NOTIFICATION AND SETTINGS ICONS
          const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Placeholder to maintain top padding if needed
            ],
          ),
          
          // Profile Picture with Background and increased size
          GestureDetector(
            onTap: _showImageSourceActionSheet,
            child: Stack(
              alignment: Alignment.center, // Center the stack contents
              children: [
                // 1. Outer Circular Background (Deep blue to give a patterned effect)
                // We use a dark color here to simulate the circuit board pattern on a bright blue background.
                Container(
                  width: backgroundRadius * 2, // Diameter
                  height: backgroundRadius * 2, // Diameter
                  decoration: BoxDecoration(
                    color: darkBlueBackground, // Darker blue for the background circle
                    shape: BoxShape.circle,
                  ),
                ),
                // 2. Inner CircleAvatar for the actual image
                CircleAvatar(
                  radius: imageRadius, // Increased radius
                  backgroundColor: Colors.white, // Inner background color
                  child: CircleAvatar(
                    radius: imageRadius - 2, // Slight border effect
                    backgroundImage: hasValidImageUrl
                        ? NetworkImage(_profileImageUrl!)
                        : null,
                    // Fallback Icon is now white to contrast with dark blue circle
                    child: !hasValidImageUrl
                        ? Icon(Icons.person, size: imageRadius, color: Colors.white.withOpacity(0.8))
                        : null,
                  ),
                ),
                // 3. Edit Icon
                Positioned(
                  bottom: 0,
                  right: (backgroundRadius - imageRadius) + 4, // Position relative to the inner circle
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: primaryBlue, // Primary Blue for the camera icon
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.edit, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Name and Details (Text colors changed to white for contrast)
          Text(
            _name ?? 'Alex Johnson',
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            '${_year ?? '3rd Year'} • ${_branch ?? 'Computer Science'}',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.white.withOpacity(0.8)),
          ),
          
          const SizedBox(height: 16),
          
          // Status Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatusBadge(Icons.check_circle_outline, 'Verified', Colors.white), // Use white for badges against blue background
              const SizedBox(width: 12),
              _buildStatusBadge(Icons.calendar_today_outlined, 'Regulation ${_regulation ?? 'R21'}', Colors.white.withOpacity(0.8)),
            ],
          ),
          
          const SizedBox(height: 16),

          // Edit Profile Button: Now opens request dialog
          SizedBox(
            width: 180,
            child: ElevatedButton.icon(
              onPressed: _showEditProfileDialog,
              icon: const Icon(Icons.edit, size: 20),
              label: const Text('Edit profile', style: TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white, // White button for contrast
                foregroundColor: primaryBlue, // Blue text on white button
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Minor adjustment to badge building function for better contrast on the blue background
  Widget _buildStatusBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15), // Slightly more opaque white background for badge
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)), // Light border
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(fontSize: 12, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // NEW: Builds the Student Details Card
  Widget _buildStudentDetailsCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          children: [
            _buildDetailTile(Icons.person_outline, 'Name', _name ?? 'Alex Johnson', trailingIcon: Icons.edit),
            _buildDetailTile(Icons.email_outlined, 'Email', _email ?? 'alex.johnson@university.edu', trailingIcon: Icons.mail_outline),
            _buildDetailTile(Icons.phone_outlined, 'Phone', _phone ?? '+1 555 0134', trailingIcon: Icons.call_outlined),
            _buildDetailTile(Icons.account_balance_outlined, 'College', _collegeName ?? 'School of Engineering', trailingIcon: Icons.bookmark_outline),
            _buildDetailTile(Icons.school_outlined, 'Branch', _branch ?? 'Computer Science', trailingIcon: Icons.link),
            _buildDetailTile(Icons.rule_outlined, 'Regulation', _regulation ?? 'R21', trailingIcon: Icons.sticky_note_2_outlined),
            _buildDetailTile(Icons.calendar_today_outlined, 'Year', _year ?? '3rd Year', trailingIcon: Icons.camera_alt_outlined),
            _buildDetailTile(Icons.badge_outlined, 'Roll No', _rollNo ?? 'CS21A045', trailingIcon: Icons.tag),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailTile(IconData leadingIcon, String label, String value, {IconData? trailingIcon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          if (trailingIcon != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(trailingIcon, color: Colors.grey.shade600, size: 18),
            ),
        ],
      ),
    );
  }

  // NEW: Builds the Support & Info Card
  Widget _buildSupportInfoCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildSupportItem(
            Icons.help_outline,
            'FAQs',
            'Common questions and answers',
            () => _showFaqsDialog(), 
          ),
          _buildSupportItem(
            Icons.support_agent,
            'Help & Support',
            'Contact support or open a ticket',
            () => _showHelpSupportDialog(),
          ),
          // REMOVED Privacy & Security
          _buildSupportItem(
            Icons.account_circle_outlined,
            'Account Settings',
            'Change password, preferences',
            () => _showAccountSettingsSheet(), // NEW: Opens the settings sheet
          ),
        ],
      ),
    );
  }

  Widget _buildSupportItem(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6A67FE), size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 13),
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
  
  Widget _buildLogoutButton() {
    return OutlinedButton.icon(
      onPressed: _logout,
      icon: Icon(Icons.logout, color: Colors.red.shade600),
      label: Text('Log Out', style: GoogleFonts.inter(fontSize: 16)),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red.shade600,
        backgroundColor: Colors.red.shade50,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.red.shade200),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// SHIMMER EFFECT WIDGET (FINAL ASSERTION FIX)
// ----------------------------------------------------------------------

class _ProfilePageShimmer extends StatelessWidget {
  const _ProfilePageShimmer();

  Widget _buildDetailPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 14, width: 80, color: Colors.white),
              const SizedBox(height: 4),
              Container(height: 16, width: 150, color: Colors.white),
            ],
          ),
          // Clean container using BoxDecoration
          Container(
            width: 30, 
            height: 30, 
            decoration: BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.circular(8)
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSupportPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          // Clean container using BoxDecoration
          Container(width: 24, height: 24, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 16, width: 120, color: Colors.white),
              const SizedBox(height: 4),
              Container(height: 13, width: 180, color: Colors.white),
            ],
          ),
          const Spacer(),
          Container(width: 16, height: 16, color: Colors.white),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header Section Placeholder
            // FINAL FIX for assertion error: Ensure no Container in this entire
            // widget has BOTH a `color` property and a `decoration` property.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 40, bottom: 20, left: 16, right: 16),
              // We rely solely on BoxDecoration, placing color inside it.
              decoration: const BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(25),
                  bottomRight: Radius.circular(25),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // Profile Picture Placeholder
                  Container(
                    width: 90,
                    height: 90,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Name Placeholder - uses color property
                  Container(height: 20, width: 150, color: Colors.white),
                  const SizedBox(height: 4),
                  // Subtitle Placeholder - uses color property
                  Container(height: 14, width: 120, color: Colors.white),
                  const SizedBox(height: 16),
                  // Badges and Button Placeholder
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 80, height: 24, color: Colors.white, margin: const EdgeInsets.only(right: 12)),
                      Container(width: 120, height: 24, color: Colors.white),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Button Placeholder - uses BoxDecoration
                  Container(height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30))),
                ],
              ),
            ),
            
            // Student Details Card Placeholder
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 18, width: 150, color: Colors.white, margin: const EdgeInsets.only(bottom: 8)),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                    child: Column(
                      children: List.generate(8, (index) => _buildDetailPlaceholder()),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Support & Info Card Placeholder
                  Container(height: 18, width: 150, color: Colors.white, margin: const EdgeInsets.only(bottom: 8)),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                    child: Column(
                      // Only 3 items now
                      children: List.generate(3, (index) => _buildSupportPlaceholder()),
                    ),
                  ),
                  
                  const SizedBox(height: 24),

                  // Logout Button Placeholder
                  Container(height: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}