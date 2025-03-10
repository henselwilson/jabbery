import 'package:flutter/material.dart';

import '../Services/network_service.dart';
import 'lobby_screen.dart';


class HomeScreen extends StatelessWidget {
  final NetworkService networkService = NetworkService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('MotoVox')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            ElevatedButton(
              onPressed: () async {
                String hostIp = await networkService.startHosting(); // Get host IP
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LobbyScreen(
                      isHost: true,
                      hostIp: hostIp, // Pass host IP
                    ),
                  ),
                );
              },
              child: Text('Create Lobby'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                String? hostAddress = await networkService.findHost();
                // String? hostAddress = "100.103.163.65";
                if (hostAddress != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LobbyScreen(
                        isHost: false,
                        hostIp: hostAddress, // Pass the found host IP
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No lobbies found.")));
                }
              },
              child: Text('Join Lobby'),
            ),
          ],
        ),
      ),
    );
  }
}
