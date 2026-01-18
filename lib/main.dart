import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/camera_screen.dart';
import 'models/app_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize settings
  await appSettings.init();
  
  // Lock app to portrait orientation and hide status bar
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  
  runApp(const SimPicApp());
}

class SimPicApp extends StatelessWidget {
  const SimPicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimPic - AI Photo Coach',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: CameraScreen(),
    );
  }
}
