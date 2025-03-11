import 'package:flutter/material.dart';
import '../Services/network_service.dart'; // Import your NetworkService class
import '../Model/Host.dart';
import 'lobby_screen.dart';
import '../Model/User.dart';


class ChooseLobbyScreen extends StatefulWidget {
  final List<Host?> availableHosts;

  const ChooseLobbyScreen({required this.availableHosts});

  @override
  _ChooseLobbyScreenState createState() => _ChooseLobbyScreenState();
}

class _ChooseLobbyScreenState extends State<ChooseLobbyScreen> {
  final NetworkService networkService = NetworkService(); // Create instance
  List<Host> availableHosts = []; // List to store found lobbies
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHosts();
  }

  Future<void> _fetchHosts() async {
    try {
      setState(() {
        availableHosts = widget.availableHosts.whereType<Host>().toList();
        isLoading = false;
      });
    } catch (e) {
      print("Error finding hosts: $e");
      setState(() => isLoading = false);
    }
  }

  void _showNameDialog(Host host, String myIp) {
    TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Enter Your Name"),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(hintText: "Your name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // Close dialog
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              String userName = nameController.text.trim();
              if (userName.isNotEmpty) {
                Navigator.pop(context); // Close dialog
                _joinLobby(host, User(ipAddress: myIp, userName: userName));
              }
            },
            child: Text("Join"),
          ),
        ],
      ),
    );
  }

  void _joinLobby(Host host, User user) async {
    Navigator.push(
      context,
        MaterialPageRoute(
          builder: (context) => LobbyScreen(
              isHost: false,
              host: host, // Pass host to LobbyScreen
              user: user,
          ),
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Choose a Lobby")),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : availableHosts.isEmpty
          ? Center(child: Text("No available lobbies found"))
          : ListView.builder(
        itemCount: availableHosts.length,
        itemBuilder: (context, index) {
          String hostIp = availableHosts[index].ipAddress;
          String hostName = availableHosts[index].hostName;
          String myIp = networkService.getLocalIp().toString();

          return ListTile(
            title: Text("Lobby: $hostName"),
            leading: Icon(Icons.wifi),
            onTap: () => _showNameDialog(Host(ipAddress: hostIp, hostName: hostName), myIp),
          );
        },
      ),
    );
  }
}
