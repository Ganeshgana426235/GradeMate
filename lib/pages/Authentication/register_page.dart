import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart'; // NEW IMPORT for opening mail app

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:email_validator/email_validator.dart';

import 'package:grademate/models/college_data.dart'; // Import the updated CollegeData model

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Controllers for Registration Form
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _collegeController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _rollNoController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController(); // NEW
  final TextEditingController _designationController = TextEditingController(); // NEW

  // State variables for UI
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoadingDropdowns = true; // For initial college data loading
  bool _isRegistering = false; // To prevent multiple registration taps

  // Dropdown data for College, Branch, Regulation, and Course Year
  List<CollegeData> _availableColleges = []; // List of CollegeData objects for autocomplete
  CollegeData? _selectedCollegeData; // Stores the currently selected college's full data

  List<String> _branchesForSelectedCollege = []; // Dynamically updated branches
  List<String> _regulationsForSelectedCollege = []; // Dynamically updated regulations
  List<String> _courseYearsForSelectedCollege = []; // Dynamically updated course years

  String? _selectedCourseYear; // For Course Year dropdown selection
  String? _selectedRegulation; // For Regulation dropdown selection

  // Role/Profession for registration
  String _selectedRegisterRole = 'Student'; // Default role for registration

  // Error messages
  final Map<String, String?> _registerErrors = {}; // Specific errors for registration fields

  // UI Primary Color (using the original sky blue)
  static const Color _primaryColor = Color(0xFF87CEEB);

  @override
  void initState() {
    super.initState();
    _fetchDropdownData(); // Fetch college data on page load
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _collegeController.dispose();
    _branchController.dispose();
    _rollNoController.dispose();
    _departmentController.dispose(); // NEW
    _designationController.dispose(); // NEW
    super.dispose();
  }

  // Helper function to create the new clean InputDecoration style
  InputDecoration _buildInputDecoration({
    required String hintText,
    required String labelText,
    required IconData icon,
    String? errorText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      labelStyle: TextStyle(
        color: errorText != null ? Colors.red : Colors.black54,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, color: _primaryColor),
      suffixIcon: suffixIcon,
      errorText: errorText,
      contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
      // Apply the same border style for all states for the clean outline look
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: _primaryColor, width: 2.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Colors.red, width: 2.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Colors.red, width: 2.0),
      ),
    );
  }

  // NEW FUNCTION: Launches the mail app with pre-filled details
  Future<void> _launchCollegeReportEmail() async {
    const String email = 'support@grademate.in';
    const String subject = 'College Adding Request';
    const String body = 'Please enter the full name of the college you would like to register:\n\nCollege Name: ';
    
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      if (mounted) {
        _showSnackbar('Could not open email application. Please contact $email manually.', success: false);
      }
    }
  }

  // Fetches colleges from Firestore for dropdowns
  Future<void> _fetchDropdownData() async {
    debugPrint('Fetching college data...');
    try {
      final colSnap = await FirebaseFirestore.instance.collection('colleges').get();

      if (mounted) {
        setState(() {
          _availableColleges = colSnap.docs.map((doc) {
            debugPrint('Processing college doc: ${doc.id}, data: ${doc.data()}');
            return CollegeData.fromFirestore(doc);
          }).toList();
          _availableColleges.sort((a, b) => a.fullName.compareTo(b.fullName)); // Sort by full name
          _isLoadingDropdowns = false;
          debugPrint('Fetched ${_availableColleges.length} colleges.');
        });
      }
    } catch (e) {
      if (mounted) _showSnackbar("Error loading college data: $e", success: false);
      if (mounted) setState(() => _isLoadingDropdowns = false);
      debugPrint('Error fetching dropdown data: $e');
    }
  }

  void _updateDependentDropdowns(CollegeData? collegeData) {
    debugPrint('Updating dependent dropdowns for college: ${collegeData?.fullName}');
    setState(() {
      _selectedCollegeData = collegeData;
      _branchesForSelectedCollege = collegeData?.branches ?? [];
      _regulationsForSelectedCollege = collegeData?.regulations ?? [];
      _courseYearsForSelectedCollege = collegeData?.courseYear ?? [];

      // Clear previous selections if the new college doesn't contain them
      if (!_branchesForSelectedCollege.contains(_branchController.text.trim().toLowerCase())) {
        _branchController.clear();
      }
      if (_selectedRegulation != null && !_regulationsForSelectedCollege.contains(_selectedRegulation!)) {
        _selectedRegulation = null;
      }
      if (_selectedCourseYear != null && !_courseYearsForSelectedCollege.contains(_selectedCourseYear!)) {
        _selectedCourseYear = null;
      }

      _branchesForSelectedCollege.sort();
      _regulationsForSelectedCollege.sort();
      _courseYearsForSelectedCollege.sort();

      debugPrint('  - Branches: $_branchesForSelectedCollege');
      debugPrint('  - Regulations: $_regulationsForSelectedCollege');
      debugPrint('  - Course Years: $_courseYearsForSelectedCollege');
    });
  }

  void _showSnackbar(String msg, {bool success = true}) {
    if (context.mounted) {
      final color = success ? Colors.green : Colors.red;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color),
      );
    }
  }

  // Validates registration form fields
  bool _validateRegisterForm() {
    setState(() {
      _registerErrors.clear();
    });

    bool isValid = true;

    if (_nameController.text.trim().isEmpty) {
      _registerErrors['name'] = 'Name is required.';
      isValid = false;
    }
    if (_emailController.text.trim().isEmpty) {
      _registerErrors['email'] = 'Email is required.';
      isValid = false;
    } else if (!EmailValidator.validate(_emailController.text.trim())) {
      _registerErrors['email'] = 'Enter a valid email address.';
      isValid = false;
    }
    if (_passwordController.text.isEmpty) {
      _registerErrors['password'] = 'Password is required.';
      isValid = false;
    } else if (_passwordController.text.length < 8 ||
        !RegExp(r'[A-Z]').hasMatch(_passwordController.text) ||
        !RegExp(r'[a-z]').hasMatch(_passwordController.text) ||
        !RegExp(r'[0-9]').hasMatch(_passwordController.text) ||
        !RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(_passwordController.text)) {
      _registerErrors['password'] = 'Min 8 chars, 1 uppercase, 1 lowercase, 1 digit, 1 symbol.';
      isValid = false;
    }
    if (_confirmPasswordController.text.isEmpty) {
      _registerErrors['confirmPassword'] = 'Confirm password is required.';
      isValid = false;
    } else if (_passwordController.text != _confirmPasswordController.text) {
      _registerErrors['confirmPassword'] = 'Passwords do not match.';
      isValid = false;
    }
    if (!RegExp(r'^\d{10}$').hasMatch(_phoneController.text.trim())) {
      _registerErrors['phone'] = 'Enter a valid 10-digit phone number.';
      isValid = false;
    }
    if (_collegeController.text.trim().isEmpty || _selectedCollegeData == null) {
      _registerErrors['college'] = 'College is required and must be selected from suggestions.';
      isValid = false;
    } else {
      // Email domain validation based on selected college
      final enteredEmail = _emailController.text.trim().toLowerCase();
      final emailParts = enteredEmail.split('@');
      if (emailParts.length == 2) {
        final enteredDomain = '@${emailParts[1]}';
        if (enteredDomain != _selectedCollegeData!.emailDomain.toLowerCase()) {
          _registerErrors['email'] = 'Email domain must match ${_selectedCollegeData!.emailDomain} for ${_selectedCollegeData!.fullName}.';
          isValid = false;
        }
      } else {
        _registerErrors['email'] = 'Enter a valid email address.';
        isValid = false;
      }
    }


    // Student-specific validations
    if (_selectedRegisterRole == 'Student') {
      if (_branchController.text.trim().isEmpty) {
        _registerErrors['branch'] = 'Branch is required.';
        isValid = false;
      } else if (!_branchesForSelectedCollege.contains(_branchController.text.trim().toLowerCase())) {
         _registerErrors['branch'] = 'Selected branch is not valid for this college.';
         isValid = false;
      }
      if (_selectedRegulation == null || _selectedRegulation!.isEmpty) {
        _registerErrors['regulation'] = 'Regulation is required.';
        isValid = false;
      } else if (!_regulationsForSelectedCollege.contains(_selectedRegulation!.toLowerCase())) {
        _registerErrors['regulation'] = 'Selected regulation is not valid for this college.';
        isValid = false;
      }
      if (_selectedCourseYear == null || _selectedCourseYear!.isEmpty) {
        _registerErrors['courseYear'] = 'Academic Year is required.';
        isValid = false;
      } else if (!_courseYearsForSelectedCollege.contains(_selectedCourseYear!)) {
        _registerErrors['courseYear'] = 'Selected Academic Year is not valid for this college.';
        isValid = false;
      }

      // Roll Number validation logic change
      if (_selectedCollegeData?.code != '**') {
        if (_rollNoController.text.trim().isEmpty) {
          _registerErrors['rollNo'] = 'Roll No is required for this college.';
          isValid = false;
        } else {
          // Check for code if it's not the special case
          final rollNo = _rollNoController.text.trim();
          if (rollNo.length >= 4) {
            final rollNoCode = rollNo.substring(2, 4).toLowerCase();
            if (rollNoCode != _selectedCollegeData!.code!.toLowerCase()) {
              _registerErrors['rollNo'] = 'Roll No code ($rollNoCode) does not match college code (${_selectedCollegeData!.code}).';
              isValid = false;
            }
          } else {
            _registerErrors['rollNo'] = 'Roll No must be at least 4 characters long for validation.';
            isValid = false;
          }
        }
      } else {
        // If college code is '**', roll number is optional.
        // We only validate if the user has entered something.
        if (_rollNoController.text.trim().isNotEmpty && _rollNoController.text.trim().length < 4) {
          _registerErrors['rollNo'] = 'Roll No must be at least 4 characters long.';
          isValid = false;
        }
      }
    } else if (_selectedRegisterRole == 'Faculty') {
      // Faculty-specific validations
      if (_departmentController.text.trim().isEmpty) {
        _registerErrors['department'] = 'Department is required.';
        isValid = false;
      }
      if (_designationController.text.trim().isEmpty) {
        _registerErrors['designation'] = 'Designation is required.';
        isValid = false;
      }
    }

    return isValid;
  }

  // Handles user registration
  Future<void> _handleRegister() async {
    if (_isRegistering) return;
    if (!_validateRegisterForm()) {
      if (mounted) setState(() {});
      return;
    }

    setState(() => _isRegistering = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final collegeId = _selectedCollegeData!.id; // Get the Firestore ID of the college
    final role = _selectedRegisterRole;

    try {
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await userCredential.user!.sendEmailVerification();

      // Placeholder for FCM Token.
      const String fcmToken = 'PLACEHOLDER_FCM_TOKEN'; 

      Map<String, dynamic> userData = {
        'uid': userCredential.user!.uid,
        'name': name,
        'email': email,
        'phone': phone,
        'collegeId': collegeId, // Store college Firestore ID
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
        'profileImageUrl': 'https://placehold.co/150x150/cccccc/000000?text=Profile', // Default placeholder image URL
        'isSubscribed': false,
        'files': [], 
        'folders': [], 
      };

      if (role == 'Student') {
        final studentBranch = _branchController.text.trim().toUpperCase();
        final studentRegulation = _selectedRegulation!.toUpperCase();
        final studentYear = _selectedCourseYear!.toUpperCase();
        
        userData.addAll({
          // Save student details to the main user doc (in CAPITALS as requested)
          'branch': studentBranch, 
          'regulation': studentRegulation,
          'year': studentYear,
          'rollNo': _rollNoController.text.trim(),
        });

        final studentRegistrationData = {
          'uid': userCredential.user!.uid,
          'name': name,
          'year': studentYear,
          'fcmToken': fcmToken,
          'regulation': studentRegulation, // Added for new structure
          'branch': studentBranch, // Added for new structure
        };
        
        // --- 1. NEW REQUIREMENT: Store Student details directly under /colleges/{collegeId}/Students/{uid} ---
        await FirebaseFirestore.instance
            .collection('colleges').doc(collegeId)
            .collection('Students').doc(userCredential.user!.uid)
            .set(studentRegistrationData);
        // ---------------------------------------------------------------------------------------------------
        
        // --- 2. PREVIOUS REQUIREMENT: Store Student details in the deeply nested structure ---
        // Path: colleges/{collegeId}/branches/{BRANCH_NAME}/regulations/{REGULATION_NAME}/Students/{uid}
        await FirebaseFirestore.instance
            .collection('colleges').doc(collegeId)
            .collection('branches').doc(studentBranch) 
            .collection('regulations').doc(studentRegulation) 
            .collection('Students').doc(userCredential.user!.uid) 
            .set(studentRegistrationData);
        // ------------------------------------------------------------------------------------------
      } else if (role == 'Faculty') {
        userData.addAll({
          'department': _departmentController.text.trim(),
          'designation': _designationController.text.trim(),
        });
      }

      // Set the main user document in the 'users' collection 
      await FirebaseFirestore.instance.collection('users').doc(email).set(userData);

      if (mounted) {
        // Clear any existing snackbars before showing the dialog
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        // Show popup message and then handle navigation
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Registration Successful'),
              content: const Text('Please verify your email address and then log in.'),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(); // Dismiss the dialog
                  },
                ),
              ],
            );
          },
        ).then((_) {
          // This code runs AFTER the dialog is dismissed
          if (mounted) {
            // Clear form fields
            _nameController.clear();
            _emailController.clear();
            _passwordController.clear();
            _confirmPasswordController.clear();
            _phoneController.clear();
            _collegeController.clear();
            _branchController.clear();
            _rollNoController.clear();
            _departmentController.clear();
            _designationController.clear();
            setState(() {
              _selectedCourseYear = null;
              _selectedRegulation = null;
              _branchesForSelectedCollege = [];
              _regulationsForSelectedCollege = [];
              _courseYearsForSelectedCollege = [];
              _selectedRegisterRole = 'Student'; // Reset to default
              _selectedCollegeData = null; // Clear selected college data
            });

            // Navigate to login page
            context.go('/login');
          }
        });
      }
    } on FirebaseAuthException catch (e) {
      String message = "Registration failed";
      if (e.code == 'email-already-in-use') {
        message = "Email already in use. Please use a different email or log in.";
      } else if (e.code == 'weak-password') {
        message = "Password is too weak. Please choose a stronger password.";
      } else if (e.code == 'invalid-email') {
        message = "The email address is not valid.";
      } else if (e.code == 'network-request-failed') {
        message = "No internet connection. Please check your network.";
      }
      if (mounted) _showSnackbar(message, success: false);
    } catch (e) {
      if (mounted) _showSnackbar("An unexpected error occurred: ${e.toString()}", success: false);
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDropdowns) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            context.go('/login'); // Navigate back to login
          },
        ),
        title: const Text(
          'Register New Account', // Slightly updated title
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Role Selection (Updated UI to match image style)
            const Text(
              'Select your Role/Profession',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: ['Student', 'Faculty'].map((role) {
                  bool isSelected = _selectedRegisterRole == role;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedRegisterRole = role;
                          // Clear student/faculty-specific fields when switching roles
                          if (role == 'Faculty') {
                            _branchController.clear();
                            _selectedCourseYear = null;
                            _selectedRegulation = null;
                            _rollNoController.clear();
                          } else {
                            _departmentController.clear();
                            _designationController.clear();
                          }
                          _branchesForSelectedCollege = [];
                          _regulationsForSelectedCollege = [];
                          _courseYearsForSelectedCollege = [];
                          _registerErrors.clear(); // Clear errors on role change
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _primaryColor // Solid primary color when selected
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? _primaryColor : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              role == 'Student' ? Icons.person_outline : Icons.school_outlined,
                              color: isSelected ? Colors.white : Colors.black54, // White icon when selected
                            ),
                            const SizedBox(height: 4),
                            Text(
                              role,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.black87, // White text when selected
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Name Input
            TextField(
              controller: _nameController,
              decoration: _buildInputDecoration(
                hintText: 'Enter your full name',
                labelText: 'Full name',
                icon: Icons.person_outline,
                errorText: _registerErrors['name'],
              ),
            ),
            const SizedBox(height: 16),

            // Email Input
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: _buildInputDecoration(
                hintText: 'Enter your email',
                labelText: 'Email',
                icon: Icons.email_outlined,
                errorText: _registerErrors['email'],
              ),
            ),
            const SizedBox(height: 16),

            // Password Input
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: _buildInputDecoration(
                hintText: 'Enter your password',
                labelText: 'Password',
                icon: Icons.lock_outline,
                errorText: _registerErrors['password'],
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.black54),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Confirm Password Input
            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              decoration: _buildInputDecoration(
                hintText: 'Confirm your password',
                labelText: 'Confirm Password',
                icon: Icons.lock_outline,
                errorText: _registerErrors['confirmPassword'],
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: Colors.black54),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Phone Input
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: _buildInputDecoration(
                hintText: 'Enter your phone number',
                labelText: 'Phone',
                icon: Icons.phone_android_outlined,
                errorText: _registerErrors['phone'],
              ),
            ),
            const SizedBox(height: 16),

            // College Autocomplete
            Autocomplete<CollegeData>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text == '') return const Iterable<CollegeData>.empty();
                return _availableColleges.where((CollegeData college) {
                  return college.fullName.toLowerCase().contains(textEditingValue.text.toLowerCase());
                });
              },
              displayStringForOption: (CollegeData option) => option.fullName,
              onSelected: (CollegeData selection) {
                _collegeController.text = selection.fullName;
                _registerErrors.remove('college');
                _updateDependentDropdowns(selection); // Update all dependent fields
              },
              fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                controller.text = _collegeController.text;
                controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                controller.addListener(() {
                  if (_collegeController.text != controller.text) {
                    _collegeController.text = controller.text;
                    // Find matching college data as user types
                    final matchingCollege = _availableColleges.firstWhere(
                      (college) => college.fullName.toLowerCase() == _collegeController.text.toLowerCase(),
                      orElse: () => CollegeData(id: '', name: '', fullName: '', emailDomain: ''), // Return dummy if no match
                    );
                    if (matchingCollege.id.isNotEmpty) { // Check if a real match was found
                      _updateDependentDropdowns(matchingCollege);
                    } else {
                      _updateDependentDropdowns(null); // Clear if no match
                    }
                  }
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onEditingComplete: onEditingComplete,
                  decoration: _buildInputDecoration(
                    hintText: 'Select your college',
                    labelText: 'College',
                    icon: Icons.school_outlined,
                    errorText: _registerErrors['college'],
                  ),
                );
              },
            ),
            
            // NEW UI ELEMENT: Report College Not Found Link
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: _launchCollegeReportEmail,
                child: const Text(
                  'Report college not found',
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),


            // Student-specific fields
            if (_selectedRegisterRole == 'Student') ...[
              // Branch Autocomplete
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text == '') return const Iterable<String>.empty();
                  return _branchesForSelectedCollege.where((String option) {
                    return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                  });
                },
                onSelected: (String selection) {
                  _branchController.text = selection;
                  _registerErrors.remove('branch');
                },
                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                  controller.text = _branchController.text;
                  controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                  controller.addListener(() {
                    if (_branchController.text != controller.text) {
                      _branchController.text = controller.text;
                    }
                  });
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    decoration: _buildInputDecoration(
                      hintText: 'Select your branch',
                      labelText: 'Branch',
                      icon: Icons.account_tree_outlined,
                      errorText: _registerErrors['branch'],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Academic Year Dropdown
              DropdownButtonFormField<String>(
                value: _selectedCourseYear,
                hint: Text(
                  'Select Academic Year',
                  style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w500),
                ),
                decoration: _buildInputDecoration(
                  hintText: '',
                  labelText: 'Year',
                  icon: Icons.calendar_today_outlined,
                  errorText: _registerErrors['courseYear'],
                ),
                items: _courseYearsForSelectedCollege.map((String year) {
                  return DropdownMenuItem<String>(
                    value: year,
                    child: Text(year),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCourseYear = newValue;
                    _registerErrors.remove('courseYear');
                  });
                },
                isExpanded: true,
              ),
              const SizedBox(height: 16),

              // Regulation Dropdown
              DropdownButtonFormField<String>(
                value: _selectedRegulation,
                hint: Text(
                  'Select Regulation',
                  style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w500),
                ),
                decoration: _buildInputDecoration(
                  hintText: '',
                  labelText: 'Regulation',
                  icon: Icons.rule_folder_outlined,
                  errorText: _registerErrors['regulation'],
                ),
                items: _regulationsForSelectedCollege.map((String regulation) {
                  return DropdownMenuItem<String>(
                    value: regulation,
                    child: Text(regulation),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedRegulation = newValue;
                    _registerErrors.remove('regulation');
                  });
                },
                isExpanded: true,
              ),
              const SizedBox(height: 16),

              // Roll Number Input
              TextField(
                controller: _rollNoController,
                decoration: _buildInputDecoration(
                  hintText: 'Enter your roll number',
                  labelText: 'Roll No',
                  icon: Icons.numbers_outlined,
                  errorText: _registerErrors['rollNo'],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Faculty-specific fields
            if (_selectedRegisterRole == 'Faculty') ...[
              TextField(
                controller: _departmentController,
                decoration: _buildInputDecoration(
                  hintText: 'e.g., Computer Science',
                  labelText: 'Department',
                  icon: Icons.business_outlined,
                  errorText: _registerErrors['department'],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _designationController,
                decoration: _buildInputDecoration(
                  hintText: 'e.g., Professor',
                  labelText: 'Designation',
                  icon: Icons.work_outline,
                  errorText: _registerErrors['designation'],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Register Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isRegistering ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  disabledBackgroundColor: _primaryColor.withOpacity(0.5),
                ),
                child: _isRegistering
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Register',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // Already have an account? Sign in
            Center(
              child: GestureDetector(
                onTap: () {
                  context.go('/login');
                },
                child: RichText(
                  text: const TextSpan(
                    text: 'Already have an account? ',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 16,
                    ),
                    children: [
                      TextSpan(
                        text: 'Sign in',
                        style: TextStyle(
                          color: _primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
