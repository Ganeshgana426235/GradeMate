import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _markNotificationsAsRead();
  }

  Future<void> _markNotificationsAsRead() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    final notificationsRef = _firestore
        .collection('users')
        .doc(user.email)
        .collection('notifications');

    // Get all unread notifications that have passed their timestamp
    final unreadSnapshot = await notificationsRef
        .where('isRead', isEqualTo: false)
        .where('timestamp', isLessThanOrEqualTo: Timestamp.now())
        .get();

    if (unreadSnapshot.docs.isEmpty) {
      return; // No notifications to mark as read
    }

    // Use a batch write to update all documents at once for efficiency
    final batch = _firestore.batch();
    for (final doc in unreadSnapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    try {
      await batch.commit();
      print('${unreadSnapshot.docs.length} notifications marked as read.');
    } catch (e) {
      print('Error marking notifications as read: $e');
    }
  }

  /// Fetches notifications whose timestamp is in the past or present.
  /// Future-dated notifications will not be included in this stream.
  Stream<QuerySnapshot> _getNotificationsStream() {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection('users')
        .doc(user.email)
        .collection('notifications')
        // **CHANGE**: Only fetch notifications that are due
        .where('timestamp', isLessThanOrEqualTo: Timestamp.now())
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getNotificationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text("Error loading notifications."));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined,
                      size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet.',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          final notifications = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final doc = notifications[index];
              final data = doc.data() as Map<String, dynamic>;
              return _buildNotificationTile(data);
            },
          );
        },
      ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> data) {
    final timestamp = data['timestamp'] as Timestamp?;
    final bool isRead = data['isRead'] ?? true;

    return Container(
      color: isRead ? Colors.transparent : Colors.blue.withOpacity(0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        // **CHANGE**: Align items to the center vertically
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey.shade200,
            child: Icon(
              _getIconForNotification(data['type']),
              color: Colors.blue.shade800,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: _buildNotificationText(data),
                ),
              ],
            ),
          ),
          if (timestamp != null)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                _formatTimestamp(timestamp),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getIconForNotification(String? type) {
    if (type == 'reminder') {
      return Icons.alarm;
    }
    // Add more icon types for other notifications (e.g., assignments)
    // if (type == 'assignment') return Icons.assignment;
    return Icons.notifications;
  }

  TextSpan _buildNotificationText(Map<String, dynamic> data) {
    final String type = data['type'] ?? '';
    final String title = data['title'] ?? 'No Title';
    final Timestamp? timestamp = data['timestamp'];

    final boldStyle = const TextStyle(fontWeight: FontWeight.bold);
    final regularStyle = TextStyle(color: Colors.grey.shade700);

    if (type == 'reminder' && timestamp != null) {
      final timeString = DateFormat('hh:mm a').format(timestamp.toDate());
      return TextSpan(
        style: const TextStyle(color: Colors.black87, fontSize: 15),
        children: [
          const TextSpan(text: 'You have a reminder '),
          TextSpan(text: title, style: boldStyle),
          const TextSpan(text: ' at '),
          TextSpan(text: timeString, style: boldStyle),
        ],
      );
    }

    // Default format for other notifications
    return TextSpan(
      style: const TextStyle(color: Colors.black87, fontSize: 15),
      children: [
        TextSpan(text: title, style: boldStyle),
        const TextSpan(text: ' '),
        TextSpan(text: data['body'] ?? '', style: regularStyle),
      ],
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final activityTime = timestamp.toDate();
    final difference = now.difference(activityTime);

    if (difference.inSeconds < 60) {
      return "${difference.inSeconds}s";
    } else if (difference.inMinutes < 60) {
      return "${difference.inMinutes}m";
    } else if (difference.inHours < 24) {
      return "${difference.inHours}h";
    } else if (difference.inDays < 7) {
      return "${difference.inDays}d";
    } else {
      return DateFormat('MMM d').format(activityTime);
    }
  }
}