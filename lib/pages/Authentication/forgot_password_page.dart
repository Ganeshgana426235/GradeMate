import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:grademate/providers/auth_provider.dart' as AppAuthProvider;

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // Function to handle sending password reset email
  void _handleSendResetLink() async {
    final authProvider = Provider.of<AppAuthProvider.AuthProvider>(context, listen: false);
    try {
      await authProvider.sendPasswordResetEmail(
        _emailController.text.trim(),
      );

      // Show popup message on success
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Success'),
              content: const Text('Password reset link has been sent to your email address. Please check your inbox.'),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(); // Dismiss the dialog
                    context.go('/login'); // Navigate to login page
                  },
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AppAuthProvider.AuthProvider>(context);
    final isLoading = authProvider.isLoading;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0, // No shadow
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            context.go('/login'); // Go back to the login page
          },
        ),
        title: const Text(
          'Password Recovery',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start, // Align content to top
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40), // Spacing from app bar
            const Text(
              'Forgot your password?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Enter your email address below, and we\'ll send you a link to reset your password.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 40),
            // Email Address Input
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2F5), // Light gray background for input
                borderRadius: BorderRadius.circular(12), // Rounded corners
              ),
              child: TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Email Address',
                  border: InputBorder.none, // Remove default border
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 30),
            // Send Reset Link Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: isLoading ? null : _handleSendResetLink,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF87CEEB), // Sky blue color from image
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), // Rounded corners
                  ),
                  elevation: 0,
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Send Reset Link',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const Spacer(), // Pushes content to the top, and the next widget to the bottom
            // Remember your password? Back to Login
            Padding(
              padding: const EdgeInsets.only(bottom: 20.0), // Add some bottom padding
              child: Align(
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: () {
                    context.go('/login'); // Navigate back to login page
                  },
                  child: RichText(
                    text: const TextSpan(
                      text: 'Remember your password? ',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                      ),
                      children: [
                        TextSpan(
                          text: 'Back to Login',
                          style: TextStyle(
                            color: Color(0xFF87CEEB), // Sky blue color
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
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