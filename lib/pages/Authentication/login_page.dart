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

  // The path to your static image asset
  final String _imageAssetPath = 'lib/pages/Authentication/login_image.png'; 
  
  @override
  void initState() {
    super.initState();
    // Removed complex ImageStreamListener logic as Image.asset handles static images efficiently
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

  // UPDATED: Changed update() to set(..., merge: true) to ensure the document path exists.
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
        // Include relevant identifying data to ensure proper query filtering in CF.
        'branch': studentBranch, 
        'regulation': studentRegulation,
        'year': studentYear,
        'collegeId': collegeId,
        'role': 'Student',
      };
      
      final SetOptions mergeOption = SetOptions(merge: true);


      // 1. Update the 'users' collection (Top Level - General Profile)
      // We use set with merge here just in case the document was created by an auth trigger but is incomplete.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userEmail)
          .set(studentTokenUpdateData, mergeOption);

      // 2. Update the 'colleges/{id}/Students/{uid}' collection (General College Student List)
      // CRITICAL FIX: Use set(..., merge: true)
      await FirebaseFirestore.instance
          .collection('colleges').doc(collegeId)
          .collection('Students').doc(uid)
          .set(studentTokenUpdateData, mergeOption);

      // 3. Update the specific course collection (Targeted Notifications)
      // CRITICAL FIX: Use set(..., merge: true)
      await FirebaseFirestore.instance
          .collection('colleges').doc(collegeId)
          .collection('branches').doc(studentBranch) 
          .collection('regulations').doc(studentRegulation) 
          // Note: The correct collection name here is 'students' (lowercase)
          .collection('Students').doc(uid) 
          .set(studentTokenUpdateData, mergeOption);

      print('FCM Token successfully updated at 3 locations for $userEmail.');

    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }

  // [UNCHANGED FUNCTION]
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
              // Pass the fetched user data to ensure _updateFCMToken has required course context
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
    
    // [Image Widget using FrameBuilder for Shimmer]
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
        Container(
          color: Colors.black.withOpacity(0.1),
        ),
        const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 20.0),
              child: Text(
                'LOGIN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.white,
      // 🐛 FIX: Wrapped the body in a SingleChildScrollView
      body: SingleChildScrollView( 
        // 🐛 FIX: ConstrainedBox ensures the content takes up at least the full screen height
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: size.height,
          ),
          child: Column(
            // Use MainAxisAlignment.start if you want content to start from the top
            // Use MainAxisAlignment.spaceBetween if you want the two sections (header/form) to be spaced out
            mainAxisAlignment: MainAxisAlignment.start, 
            children: [
              // 1. Header Area
              Container(
                height: size.height * 0.35,
                width: double.infinity,
                color: const Color(0xFF2F4F4F),
                child: imageWidget,
              ),
              
              // 2. Form Area
              // Note: Removed the unnecessary Expanded widget from this area
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  // Use MainAxisAlignment.center to vertically center the form elements in the remaining space
                  mainAxisAlignment: MainAxisAlignment.center, 
                  mainAxisSize: MainAxisSize.min, // Allows the column to only take necessary vertical space
                  children: [
                    const SizedBox(height: 40), // Added top spacing back
                    const Text(
                      'Welcome Back',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'Email',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          hintText: 'Password',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                    ),
                    const SizedBox(height: 15),
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
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF87CEEB),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
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
                    GestureDetector(
                      onTap: () {
                        context.go('/register'); // Navigate to the new RegisterPage
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
                                color: Color(0xFF87CEEB),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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
