import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:grademate/providers/auth_provider.dart';


class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    // Safely access user email, it might be null if not authenticated
    final userEmail = authProvider.isAuthenticated ? authProvider.currentUser?.email : 'Guest';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome Home!'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authProvider.signOut();
              // GoRouter's redirect will handle navigation back to login
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Hello, ${userEmail ?? 'User'}!', // Handle null userEmail gracefully
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const Text(
              'You are successfully logged in.',
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                // Example of navigating to another part of your app
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Exploring app features...')),
                );
              },
              child: const Text('Explore App'),
            ),
          ],
        ),
      ),
    );
  }
}