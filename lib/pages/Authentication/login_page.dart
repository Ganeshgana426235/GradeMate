import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart'; 
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shimmer/shimmer.dart'; 

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  // The path to your static image asset (Restored)
  final String _imageAssetPath = 'lib/pages/Authentication/login_image.png'; 
  
  // UI Primary Color (using the original sky blue from RegisterPage)
  static const Color _primaryColor = Color(0xFF87CEEB);
  
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // Helper function to create the new clean InputDecoration style (Copied from RegisterPage)
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

  // [LOGIC UNCHANGED]
  Future<void> _updateFCMToken(String userEmail, String uid, String collegeId, Map<String, dynamic> userData) async {
    final role = userData['role'] as String?;
    if (role != 'Student') return; 

    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      
      if (fcmToken == null) return;

      final studentBranch = (userData['branch'] as String?)?.toUpperCase() ?? 'UNKNOWN_BRANCH';
      final studentRegulation = (userData['regulation'] as String?)?.toUpperCase() ?? 'UNKNOWN_REGULATION';
      final studentYear = (userData['year'] as String?)?.toUpperCase() ?? 'UNKNOWN_YEAR';

      final studentTokenUpdateData = {
        'fcmToken': fcmToken,
        'branch': studentBranch, 
        'regulation': studentRegulation,
        'year': studentYear,
        'collegeId': collegeId,
        'role': 'Student',
      };
      
      final SetOptions mergeOption = SetOptions(merge: true);


      await FirebaseFirestore.instance
          .collection('users')
          .doc(userEmail)
          .set(studentTokenUpdateData, mergeOption);

      await FirebaseFirestore.instance
          .collection('colleges').doc(collegeId)
          .collection('Students').doc(uid)
          .set(studentTokenUpdateData, mergeOption);

      await FirebaseFirestore.instance
          .collection('colleges').doc(collegeId)
          .collection('branches').doc(studentBranch) 
          .collection('regulations').doc(studentRegulation) 
          .collection('Students').doc(uid) 
          .set(studentTokenUpdateData, mergeOption);

      print('FCM Token successfully updated at 3 locations for $userEmail.');

    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }

  // [LOGIC UNCHANGED]
  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user;
      if (user != null && user.emailVerified) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.email!).get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          final role = userData?['role'] as String?;
          final uid = user.uid;
          final email = user.email!;
          final collegeId = userData?['collegeId'] as String?; 

          if (role != null && collegeId != null) {
            
            if (role == 'Student') {
              await _updateFCMToken(email, uid, collegeId, userData!); 
            }
            
            final userBox = Hive.box<String>('userBox');
            userBox.put('uid', uid);
            userBox.put('email', email);
            userBox.put('role', role); 

            _emailController.clear();
            _passwordController.clear();
            if (role == 'Student') {
              context.go('/student_home');
            } else if (role == 'Faculty') {
              context.go('/faculty_home');
            } else {
              _showSnackbar('Unknown user role. Please contact support.');
            }
          } else {
            _showSnackbar('User data incomplete (role or college ID missing). Please contact support.');
            await FirebaseAuth.instance.signOut();
          }
        } else {
          _showSnackbar('User data not found. Please contact support.');
          await FirebaseAuth.instance.signOut();
        }
      } else {
        _showSnackbar('Please verify your email then login. Also, please check spam messages.');
        await FirebaseAuth.instance.signOut();
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Login failed.';
      if (e.code == 'user-not-found') {
        message = 'No user found for that email.';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Wrong password or invalid credentials.';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is not valid.';
      } else if (e.code == 'network-request-failed') {
        message = 'No internet connection. Please check your network.';
      } else {
        message = 'An unexpected error occurred: ${e.code}';
      }
      _showSnackbar(message);
    } catch (e) {
      _showSnackbar('An unexpected error occurred: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // [RETAINED WIDGET: Shimmer Loading Placeholder]
  Widget _buildShimmerPlaceholder(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.8), // Dark color
      highlightColor: const Color.fromARGB(255, 249, 250, 251).withOpacity(0.5), // Lighter color for animation
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white, // The shimmering effect will be applied to this color
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 15),
            Container(
              width: 200,
              height: 25,
              color: Colors.white, // Shimmer text line 1
            ),
            const SizedBox(height: 5),
            Container(
              width: 150,
              height: 15,
              color: Colors.white, // Shimmer text line 2
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    
    final size = MediaQuery.of(context).size;
    
    // [Image Widget using FrameBuilder for Shimmer - RE-INTEGRATED]
    final imageWidget = Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _imageAssetPath,
          fit: BoxFit.cover, 
          gaplessPlayback: true, 
          frameBuilder: (BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return child; 
            }
            return _buildShimmerPlaceholder(context);
          },
          errorBuilder: (context, error, stackTrace) {
            print('Error rendering Image asset: $error');
            return _buildShimmerPlaceholder(context); 
          },
        ),
        // Dark overlay for contrast
        Container(
          color: Colors.black.withOpacity(0.3), // Slightly darker overlay
        ),
        const Center(
            child: Text(
              'SIGN IN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32, // Slightly larger
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.white,
      // Removed AppBar to allow the image header to reach the top
      body: SingleChildScrollView( 
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: size.height,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Area (Image)
              Container(
                height: size.height * 0.35, // Maintain height
                width: double.infinity,
                color: const Color(0xFF2F4F4F),
                child: imageWidget,
              ),
              
              // 2. Form Area (Using the RegisterPage's Padding and styling)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Welcome Back',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    // Email Input (New Style)
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _buildInputDecoration(
                        hintText: 'Enter your email',
                        labelText: 'Email',
                        icon: Icons.email_outlined,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Password Input (New Style)
                    TextField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      decoration: _buildInputDecoration(
                        hintText: 'Enter your password',
                        labelText: 'Password',
                        icon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                            color: Colors.black54,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    // Forgot Password Link
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {
                          context.go('/forgot_password');
                        },
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Login Button (New Style)
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor, // Use the shared primary color
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          disabledBackgroundColor: _primaryColor.withOpacity(0.5),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'Login',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Sign Up Link (New Style)
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          context.go('/register'); 
                        },
                        child: RichText(
                          text: const TextSpan(
                            text: 'Don\'t have an account? ',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                            ),
                            children: [
                              TextSpan(
                                text: 'Sign Up',
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
                    const SizedBox(height: 20), // Added bottom spacing
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}