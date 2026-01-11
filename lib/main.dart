import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock app to portrait orientation
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(const SimPicApp());
  });
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
