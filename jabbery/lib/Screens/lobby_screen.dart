import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:udp/udp.dart';

class LobbyScreen extends StatefulWidget {
  final bool isHost;
  final String hostIp; // Host's IP

  const LobbyScreen({required this.isHost, required this.hostIp});

  @override
  _LobbyScreenState createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  // final VoiceService voiceService = VoiceService();
  List<String> connectedUsers = []; // Stores connected IPs
  UDP? udpSocket;
  bool isTalking = false; // Indicator for push-to-talk
  static const int discoveryPort = 5000;

  @override
  void initState() {
    super.initState();
    // voiceService.init();
    // voiceService.targetIp = widget.hostIp;

    if (widget.isHost) {
      _startReceivingRequests();
    } else {
      _sendJoinRequest();
    }
    _listenForUpdates();
    _listenForMessages();
  }

  void _startReceivingRequests() async {
    udpSocket = await UDP.bind(Endpoint.any(port: Port(6002))); // Host listens on 6002
    print("🔵 [HOST] Listening for join requests on port 6002...");

    // Add the host itself to the list

    String hostIp = widget.hostIp;
    if (!connectedUsers.contains(hostIp)) {
      setState(() {
        connectedUsers.add(hostIp);
      });
    }

    udpSocket!.asStream().listen((datagram) async {
      if (datagram != null) {
        String message = String.fromCharCodes(datagram.data);
        String userIp = datagram.address.address;

        if (message == "MotoVox_DISCOVER") {
          print("📡 [HOST] Discovery request received from $userIp, responding...");

          UDP sender = await UDP.bind(Endpoint.any());
          await sender.send(hostIp.codeUnits, Endpoint.unicast(
              InternetAddress(userIp), port: Port(discoveryPort)
          ));
          sender.close();
        }
        else if (message == "JOIN") {
          print("✅ [HOST] Join request received from: $userIp");

          if (!connectedUsers.contains(userIp)) {
            setState(() {
              connectedUsers.add(userIp);
            });
          }
          _broadcastUserList();

          // ✅ Send confirmation to new client
          UDP sender = await UDP.bind(Endpoint.any());
          await sender.send("JOINED".codeUnits, Endpoint.unicast(
              InternetAddress(userIp), port: Port(6003)
          ));
          sender.close();
        }
      }
    });
  }



  void _sendJoinRequest() async {
    print("📩 [CLIENT] Sending join request to: ${widget.hostIp}:6002"); // Debug log

    if (widget.hostIp.isEmpty) {
      print("❌ Invalid Host IP");
      return;
    }

    UDP sender = await UDP.bind(Endpoint.any());
    for (int i = 0; i < 3; i++) {
      await sender.send(Uint8List.fromList("JOIN".codeUnits), Endpoint.unicast(InternetAddress(widget.hostIp), port: Port(6002)));
      await Future.delayed(Duration(milliseconds: 500));
    }
    sender.close();
    print("📩 [CLIENT] Join request sent to ${widget.hostIp}");
  }

  void _broadcastUserList() async {
    if (connectedUsers.isEmpty) return;

    String userList = connectedUsers.join(',');
    Uint8List data = Uint8List.fromList(userList.codeUnits);

    print("📢 [HOST] Sending updated user list: $userList");

    for (String ip in connectedUsers) {
      UDP sender = await UDP.bind(Endpoint.any());
      await sender.send(data, Endpoint.unicast(InternetAddress(ip), port: Port(6003)));
      sender.close();
    }
  }


  void _listenForUpdates() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6003)));
    print("🔄 [CLIENT] Listening for user list updates on port 6003...");

    receiver.asStream().listen((datagram) {
      if (datagram != null && datagram.data.isNotEmpty) {
        String receivedData = String.fromCharCodes(datagram.data);
        List<String> updatedUsers = receivedData.split(',');

        print("🔄 [CLIENT] Received updated user list: $updatedUsers"); // Debug log

        setState(() {
          connectedUsers = updatedUsers;
        });

        print("🔄 [CLIENT] State updated with: $connectedUsers");
      }
    }, onError: (error) {
      print("❌ [CLIENT] Error receiving user list updates: $error");
    });
  }

  TextEditingController messageController = TextEditingController();
  List<String> messages = []; // Stores received messages

  void _sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    Uint8List data = Uint8List.fromList(message.codeUnits);
    print("📢 Sending message: $message");

    // Ensure message is sent to all users, including the host
    for (String ip in connectedUsers) {
      UDP sender = await UDP.bind(Endpoint.any());
      await sender.send(data, Endpoint.unicast(InternetAddress(ip), port: Port(6004)));
      sender.close();
    }

    // setState(() {
    //   messages.add("You: $message"); // Show sent message in chat
    // });

    messageController.clear();
  }


  void _listenForMessages() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6004)));
    print("🔄 [CLIENT] Listening for messages on port 6004...");

    receiver.asStream().listen((datagram) {
      if (datagram != null && datagram.data.isNotEmpty) {
        String receivedMessage = String.fromCharCodes(datagram.data);
        print("💬 New message received: $receivedMessage");

        setState(() {
          messages.add(receivedMessage);
        });
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isHost ? 'Host Lobby' : 'Joined Lobby')),
      body: Column(
        children: [
          SizedBox(height: 10),
          Text("Connected Users", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

          connectedUsers.isEmpty
              ? Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("No users connected yet", style: TextStyle(color: Colors.grey)),
          )
              : Column(
            children: connectedUsers.map((ip) {
              return Container(
                margin: EdgeInsets.symmetric(vertical: 5, horizontal: 20),
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  ip == widget.hostIp ? "👑 Host: $ip" : "🔹 User: $ip",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              );
            }).toList(),
          ),

          SizedBox(height: 20),
          Text("Chat Messages", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

          Expanded(
            child: Container(
              margin: EdgeInsets.all(10),
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: messages.isEmpty
                  ? Center(child: Text("No messages yet", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: EdgeInsets.symmetric(vertical: 5),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: messages[index].startsWith("You:")
                          ? Colors.green[100] // Sent message
                          : Colors.white, // Received message
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(messages[index], style: TextStyle(fontSize: 14)),
                  );
                },
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => _sendMessage(messageController.text),
                  child: Text("Send"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    udpSocket?.close();
    super.dispose();
  }
}