import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/services.dart'; // For platform channels
import 'package:permission_handler/permission_handler.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For encoding data to base64
import 'package:image/image.dart' as img;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: FirstPage(),
      debugShowCheckedModeBanner: false, // Add this line
    );
  }
}

class FirstPage extends StatefulWidget {
  const FirstPage({super.key});

  @override
  _FirstPageState createState() => _FirstPageState();
}

class _FirstPageState extends State<FirstPage> {
  File? _image;
  String? _pickedImageName; // Store only the filename
  bool _isProcessing = false;

  // Pick image from gallery
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        // Preserve the original filename
        final segments = pickedFile.path.split(RegExp(r'[\\/]+'));
        _pickedImageName = segments.last;
      });
    }
  }

  // Request storage permissions
  // Function to request storage permissions
  bool _isRequestingPermission = false;

  Future<bool> _requestPermission() async {
    if (_isRequestingPermission) {
      print("Permission request already running.");
      return false; // Prevent concurrent permission requests
    }

    _isRequestingPermission = true; // Set flag to prevent duplicate calls
    try {
      if (Platform.isAndroid) {
        if (await Permission.manageExternalStorage.isGranted) {
          return true; // Android 11+ already granted
        }

        if (await Permission.storage.isGranted) {
          return true; // Android <11 already granted
        }

        // Request MANAGE_EXTERNAL_STORAGE for Android 11+
        if (await Permission.manageExternalStorage.request().isGranted) {
          return true;
        }

        // Request READ/WRITE permissions for Android <11
        if (await Permission.storage.request().isGranted) {
          return true;
        }

        // If permissions are permanently denied, open settings
        if (await Permission.manageExternalStorage.isPermanentlyDenied ||
            await Permission.storage.isPermanentlyDenied) {
          await openAppSettings();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text("Please enable storage access manually in settings."),
            ),
          );
        }
      }
      return false; // Default: Permission denied
    } finally {
      _isRequestingPermission = false; // Reset flag
    }
  }

  Future<bool> _requestManageStoragePermission() async {
    // Attempt to request the MANAGE_EXTERNAL_STORAGE permission
    var status = await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      return true;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("You need to enable storage access in Settings.")),
      );
      await openAppSettings();
      return false;
    }
  }

  void _openAppSettings() async {
    if (await Permission.manageExternalStorage.isPermanentlyDenied ||
        await Permission.storage.isPermanentlyDenied) {
      await openAppSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please enable storage permission in settings.")),
      );
    }
  }

  // Save the picked image to the app's document directory using only the filename
// Variable to track if the image has already been saved
  bool _isImageSavedFlag = false;

  Future<void> _saveImage() async {
    if (_image == null || _pickedImageName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No image selected to save.")),
      );
      return;
    }

    try {
      // Request permissions
      final hasPermission = await _requestPermission();
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Storage permission is required to save images."),
        ));
        return;
      }

      // Check if the image is already saved
      if (_isImageSavedFlag) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("This image has already been saved."),
        ));
        return;
      }

      // Read the image file as bytes
      Uint8List imageBytes = await _image!.readAsBytes();

      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final uniqueFileName =
          '${_pickedImageName!.split('.').first}_$timestamp.jpg';

      final result = await ImageGallerySaver.saveImage(
        imageBytes,
        quality: 100,
        name: uniqueFileName,
      );

      if (result['isSuccess']) {
        final savedPath = result['filePath'];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Image saved successfully at: $savedPath"),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Failed to save the image."),
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Error saving image: $e"),
      ));
    }
  }

  // Show user manual
  // Show user manual
  void _showUserManual(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("User Manual"),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text("Please connect a network before use it."),
                SizedBox(height: 20),
                Text("Main Page"),
                SizedBox(height: 10),
                Text("1. [Open Image] Button: Used to upload the image."),
                Text(
                    "2. [Save Image] Button: Used to save the uploaded image to the gallery."),
                Text(
                    "3. [License Plate Recognition] Button: Used to run the license plate recognizer."),
                Text("4. The image can be viewed at Gallery."),
                SizedBox(height: 20),
                Text("Recognition Result"),
                SizedBox(height: 10),
                Text(
                    "1. [Save Processed Image] Button: Used to save the processed image after being processed by the recognizer."),
                Text(
                    "2. The recognizer run at the server with python and flask."),
                SizedBox(height: 100),
                Text(
                    "App is developed by 1/2425 image processing group 6 for project. Thanks for using."),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool> _isImageSaved() async {
    if (_pickedImageName == null) return false;

    try {
      // Use the app's external directory
      final directory = await getExternalStorageDirectory();
      final appDirectory =
          Directory('${directory?.path}/license_plate_recognition/YourAppName');

      print("Checking files in: ${appDirectory.path}");

      // Check if the directory exists
      if (!await appDirectory.exists()) {
        print("Directory does not exist.");
        return false;
      }

      // Compare filenames in the directory
      List<FileSystemEntity> files = appDirectory.listSync();
      for (var file in files) {
        final fileName = file.uri.pathSegments.last; // Extract the filename
        if (fileName == _pickedImageName) {
          print("File matched: $fileName");
          return true; // Match found
        }
      }

      print("No matching file found.");
      return false;
    } catch (e) {
      print("Error checking saved image: $e");
      return false;
    }
  }

  // Run License Plate Recognition
  Future<void> _runLicensePlateRecognition() async {
    if (_image == null || _pickedImageName == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please select an image first."),
      ));
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Ensure the image file exists
      final savedImagePath = _image!.path;
      print("File path: $savedImagePath");

      bool fileExists = await File(savedImagePath).exists();
      if (!fileExists) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("The image file was not found. Please save it first."),
        ));
        return;
      }

      // Create a multipart request
      final uri = Uri.parse(
          'https://smiling-mammoth-presumably.ngrok-free.app/process-image');
      var request = http.MultipartRequest('POST', uri);
      var file = await http.MultipartFile.fromPath('file', savedImagePath);
      request.files.add(file);

      // Send the request
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      print("Response status: ${response.statusCode}");
      print("Response body: ${response.body}");

      Uint8List processedImageBytes = await _image!.readAsBytes();
      String recognizedText = "No license plate or text detected";

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result.containsKey('processed_image_base64')) {
          processedImageBytes = base64Decode(result['processed_image_base64']);
        }
        if (result.containsKey('recognized_text')) {
          recognizedText = result['recognized_text'].join(', ');
        }
      }

      // Use a unique file name to avoid cache issues
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final processedImagePath =
          '${(await getTemporaryDirectory()).path}/processed_image_$timestamp.jpg';

      final processedImage = File(processedImagePath);
      await processedImage.writeAsBytes(processedImageBytes);

      // Navigate to the next screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SecondPage(
            processedImage: processedImage,
            recognizedText: recognizedText,
            inputFileName: _pickedImageName!,
          ),
        ),
      );
    } catch (e) {
      print("Error: $e");
      final fallbackImage = File(_image!.path);
      final fallbackText = "No text detected due to an error.";

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SecondPage(
            processedImage: fallbackImage,
            recognizedText: fallbackText,
            inputFileName: _pickedImageName!,
          ),
        ),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  bool _isProcessingRecognition = false; // For License Plate Recognition
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('License plate recognition'),
      ),
      body: Center(
        child: SingleChildScrollView(
          // To prevent overflow when showing images
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ElevatedButton(
                onPressed: () => _showUserManual(context),
                child: const Text("User Manual"),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _pickImage,
                child: const Text("Open Image"),
              ),
              const SizedBox(height: 20),
              _image == null
                  ? const Text('No image selected.')
                  : Column(
                      children: [
                        Text("Selected Image: $_pickedImageName"),
                        const SizedBox(height: 10),
                        Container(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.5,
                            maxWidth: MediaQuery.of(context).size.width * 0.9,
                          ),
                          child: Image.file(
                            _image!,
                            fit: BoxFit
                                .contain, // Maintain the original aspect ratio
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _saveImage,
                          child: const Text("Save Image"),
                        ),
                      ],
                    ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  setState(() {
                    _isProcessingRecognition = true;
                  });
                  await _runLicensePlateRecognition();
                  setState(() {
                    _isProcessingRecognition = false;
                  });
                },
                child: _isProcessingRecognition
                    ? const CircularProgressIndicator()
                    : const Text("License Plate Recognition"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SecondPage extends StatefulWidget {
  final File processedImage;
  final String recognizedText;
  final String inputFileName; // Add this parameter

  const SecondPage({
    super.key,
    required this.processedImage,
    required this.recognizedText,
    required this.inputFileName, // Initialize
  });

  @override
  _SecondPageState createState() => _SecondPageState();
}

class _SecondPageState extends State<SecondPage> {
  bool _isSaving = false;

  // Function to request storage permissions
  Future<bool> _requestPermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }

  // Save processed image to gallery with just the filename
  Future<void> _saveProcessedImage() async {
    if (widget.processedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No processed image to save.")),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Use the input file name passed from Page1
      final String inputFileName = widget.inputFileName;

      // Remove existing "processed_" prefix if already present
      final String cleanInputFileName = inputFileName.startsWith('processed_')
          ? inputFileName.replaceFirst('processed_', '')
          : inputFileName;

      // Create the new filename: processed_{inputFileName}.jpg
      final String saveFileName =
          'processed_${cleanInputFileName.split('.').first}.jpg';

      // Read the processed image file as bytes
      Uint8List imageBytes = await widget.processedImage.readAsBytes();

      // Save the processed image using ImageGallerySaver
      final result = await ImageGallerySaver.saveImage(
        imageBytes,
        quality: 100,
        name: saveFileName,
      );

      if (result['isSuccess']) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Processed image saved as: $saveFileName"),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Failed to save the processed image."),
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Error saving processed image: $e"),
      ));
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
      ),
      body: Center(
        child: SingleChildScrollView(
          // To prevent overflow when showing images
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Image.file(
                widget.processedImage,
                height: 200,
              ),
              const SizedBox(height: 20),
              Text(
                "Recognized License Plate: ${widget.recognizedText}",
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              _isSaving
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _saveProcessedImage,
                      child: const Text("Save Processed Image"),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
