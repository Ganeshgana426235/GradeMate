import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:video_player/video_player.dart';
import 'package:grademate/models/file_models.dart';

class FileViewerPage extends StatefulWidget {
  final FileData file;
  const FileViewerPage({super.key, required this.file});

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> {
  late VideoPlayerController _videoController;
  late final WebViewController _webViewController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeViewer();
  }

  void _initializeViewer() {
    final fileType = widget.file.type?.toLowerCase();

    if (fileType == 'mp4' || fileType == 'mov' || fileType == 'avi') {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.file.url))
        ..initialize().then((_) {
          setState(() {
            _isVideoInitialized = true;
          });
        });
    } else if (fileType == 'doc' || fileType == 'docx' || fileType == 'ppt' || fileType == 'pptx' || fileType == 'xls' || fileType == 'xlsx') {
      final docUrl = 'https://docs.google.com/gview?embedded=true&url=${widget.file.url}';
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(docUrl));
    }
  }

  @override
  void dispose() {
    final fileType = widget.file.type?.toLowerCase();
    if (fileType == 'mp4' || fileType == 'mov' || fileType == 'avi') {
      _videoController.dispose();
    }
    super.dispose();
  }

  Widget _buildViewer() {
    final fileType = widget.file.type?.toLowerCase();
    switch (fileType) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Image.network(widget.file.url);
      case 'pdf':
        return SfPdfViewer.network(widget.file.url);
      case 'mp4':
      case 'mov':
      case 'avi':
        if (_isVideoInitialized) {
          return Center(
            child: AspectRatio(
              aspectRatio: _videoController.value.aspectRatio,
              child: VideoPlayer(_videoController),
            ),
          );
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      case 'doc':
      case 'docx':
      case 'ppt':
      case 'pptx':
      case 'xls':
      case 'xlsx':
        return WebViewWidget(controller: _webViewController);
      default:
        return Center(child: Text('Unsupported file type: ${widget.file.type}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileType = widget.file.type?.toLowerCase();
    final isVideo = fileType == 'mp4' || fileType == 'mov' || fileType == 'avi';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            context.pop();
          },
        ),
      ),
      body: _buildViewer(),
      floatingActionButton: isVideo
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _videoController.value.isPlaying ? _videoController.pause() : _videoController.play();
                });
              },
              child: Icon(
                _videoController.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
    );
  }
}