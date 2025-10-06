import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:grademate/models/file_models.dart';

class FileDetailsPage extends StatefulWidget {
  final FileData file;
  const FileDetailsPage({super.key, required this.file});

  @override
  State<FileDetailsPage> createState() => _FileDetailsPageState();
}

class _FileDetailsPageState extends State<FileDetailsPage> {
  bool _isDownloading = false;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }
  
  void _initializeNotifications() {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidInitializationSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
      InitializationSettings(android: androidInitializationSettings);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }
  
  Future<void> _showProgressNotification(int progress) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'download_channel_id',
      'Download Progress',
      channelDescription: 'Shows the progress of file downloads',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: 0,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Downloading ${widget.file.name}',
      'Download in progress: $progress%',
      platformChannelSpecifics,
    );
  }

  Future<void> _showCompletionNotification(String fileName) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'download_completion_channel_id',
      'Download Complete',
      channelDescription: 'Notifies when a download is finished',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      1,
      'Download Complete',
      'The file "$fileName" has been downloaded successfully.',
      platformChannelSpecifics,
    );
  }

  Future<void> _downloadFile() async {
    setState(() {
      _isDownloading = true;
    });

    try {
      final dio = Dio();
      final Directory? baseDownloadDir = await getExternalStorageDirectory();
      if (baseDownloadDir == null) {
        _showSnackBar('❌ Failed to find a valid download directory.', isError: true);
        return;
      }
      final Directory gradeMateDir = Directory('${baseDownloadDir.path}${Platform.pathSeparator}GradeMate');

      if (!await gradeMateDir.exists()) {
        try {
          await gradeMateDir.create(recursive: true);
        } catch (e) {
          _showSnackBar('❌ Failed to create folder. Cannot download.', isError: true);
          return;
        }
      }
      
      final filePath = '${gradeMateDir.path}${Platform.pathSeparator}${widget.file.name}';
      
      await dio.download(
        widget.file.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toInt();
            _showProgressNotification(progress);
          }
        },
      );

      await _showCompletionNotification(widget.file.name);
      
    } catch (e) {
      _showSnackBar('❌ Error during download: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  Future<void> _shareFile() async {
    try {
      final dio = Dio();
      final dir = await getTemporaryDirectory();
      final tempFilePath = '${dir.path}/${widget.file.name}';
      
      await dio.download(widget.file.url, tempFilePath);

      await Share.shareXFiles([XFile(tempFilePath)], text: 'Check out this file from GradeMate: ${widget.file.name}');

    } catch (e) {
      _showSnackBar('❌ Failed to share file: $e', isError: true);
    }
  }
  
  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            context.pop();
          },
        ),
        title: const Text(
          'File Preview',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insert_drive_file, size: 50, color: Colors.blue[800]),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.file.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.file.type.toUpperCase(),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    context.push('/file_viewer', extra: widget.file);
                  },
                  icon: const Icon(Icons.open_in_new, color: Colors.blue),
                  label: const Text('Open', style: TextStyle(color: Colors.blue)),
                ),
              ],
            ),
            const SizedBox(height: 32),

            const Text(
              'Details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Uploaded', widget.file.ownerName ?? 'N/A'),
            _buildDetailRow('Date & Time', DateFormat('yMMMd, HH:mm').format(widget.file.uploadedAt.toDate())),
            _buildDetailRow('Size', '${(widget.file.size / (1024 * 1024)).toStringAsFixed(2)} MB'),
            _buildDetailRow('File Type', widget.file.type.toUpperCase()),
            _buildDetailRow('Shared with', widget.file.sharedWith.isEmpty ? 'Not Shared' : widget.file.sharedWith.join(', ')),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _isDownloading ? null : _downloadFile,
                child: _isDownloading
                    ? const CircularProgressIndicator()
                    : const Text('Download'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: OutlinedButton(
                onPressed: _isDownloading ? null : _shareFile,
                child: const Text('Share'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(value),
        ],
      ),
    );
  }
}