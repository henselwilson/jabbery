import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'Screens/HomePage.dart';
import 'Screens/TurnOnHotspotScreen.dart';

void main()async {
  runApp(const MyApp());
  await Permission.microphone.request();

}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(

        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: HomeScreen(),
    );
  }
}
