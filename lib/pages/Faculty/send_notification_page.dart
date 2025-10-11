import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SendNotificationPage extends StatefulWidget {
  const SendNotificationPage({super.key});

  @override
  State<SendNotificationPage> createState() => _SendNotificationPageState();
}

class _SendNotificationPageState extends State<SendNotificationPage> {
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Navigate to the home page when the back button is pressed
        context.go('/faculty_home');
        // Return false to prevent the default back button action (closing the app)
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/faculty_home'),
          ),
          title: const Text('Send Notification'),
          centerTitle: true,
        ),
        body: const Center(
          child: Text(
            'Send Notification Page',
            style: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }
}

