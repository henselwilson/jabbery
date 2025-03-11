import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:udp/udp.dart';
import 'package:flutter_sound/flutter_sound.dart';

import '../Model/Host.dart';
import '../Model/User.dart';

class LobbyScreen extends StatefulWidget {
  final bool isHost;
  final Host host;
  final User user;


  const LobbyScreen({required this.isHost, required this.host, required this.user});

  @override
  _LobbyScreenState createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  // final VoiceService voiceService = VoiceService();
  List<User> connectedUsers = []; // Stores connected IPs
  UDP? udpSocket;
  static const int discoveryPort = 5000;
  FlutterSoundRecorder? _audioRecorder;
  FlutterSoundPlayer? _audioPlayer;
  bool _isRecording = false;
  String _myIpAddress = '';
  bool _isStreaming = false; // For real-time streaming
  StreamController<Uint8List>? _audioStreamController; // Added for streaming
  Timer? _silenceTimer; // To detect end of stream on receiver
  bool _isPlayerReady = false; // Track if player is ready for streaming

  @override
  void initState() {
    super.initState();
    // voiceService.init();
    // voiceService.targetIp = widget.hostIp;
    getLocalIp();
    _audioRecorder = FlutterSoundRecorder();
    _audioPlayer = FlutterSoundPlayer();
    _initAudio();
    if (widget.isHost) {
      _startReceivingRequests();
    } else {
      _sendJoinRequest();
    }
    _listenForUpdates();
    _listenForMessages();
    _listenForAudio();
    _listenForStreamedAudio(); // New listener for real-time audio
  }

  Future<String?> getLocalIp() async {
    print("MY IP ADDRESS $_myIpAddress");
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            addr.address.startsWith("192.168.")) {
          setState(() {
            _myIpAddress = addr.address;
          });
          print("MY IP ADDRESS $_myIpAddress");
          return addr.address;
        }
      }
    }
    return null;
  }

  Future<void> _initAudio() async {
    await _audioRecorder!.openRecorder();
    await _audioPlayer!.openPlayer();
    await _startPlayerForStream(); // Initial setup
  }

  Future<void> _startPlayerForStream() async {
    if (!_isPlayerReady) {
      await _audioPlayer!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 16000,
      );
      _isPlayerReady = true;
      print("🎵 [CLIENT] Player initialized for streaming");
    }
  }

  Future<void> _stopPlayerForStream() async {
    if (_isPlayerReady) {
      await _audioPlayer!.stopPlayer();
      _isPlayerReady = false;
      print("🛑 [CLIENT] Player stopped");
    }
  }

// Updated Real-Time Streaming Methods
  // Real-Time Streaming Methods
  void _startStreaming() async {
    if (_isStreaming || _isRecording) return;
    setState(() => _isStreaming = true);

    _audioStreamController = StreamController<Uint8List>();
    _audioStreamController!.stream.listen(_sendStreamedAudio);

    await _audioRecorder!.startRecorder(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 16000,
      toStream: _audioStreamController!.sink,
    );
  }

  void _stopStreaming() async {
    if (!_isStreaming) return;
    setState(() => _isStreaming = false);
    await _audioRecorder!.stopRecorder();
    await _audioStreamController?.close();

    // Send stop signal
    Uint8List stopSignal = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
    for (User user in connectedUsers) {
      if (user.ipAddress != _myIpAddress) {
        UDP sender = await UDP.bind(Endpoint.any());
        await sender.send(stopSignal,
            Endpoint.unicast(InternetAddress(user.ipAddress), port: Port(6006)));
        sender.close();
      }
    }

    _audioStreamController = null;
  }

  void _sendStreamedAudio(Uint8List audioChunk) async {
    if (audioChunk.isEmpty) return;

    for (User user in connectedUsers) {
      if (user.ipAddress != _myIpAddress) {
        UDP sender = await UDP.bind(Endpoint.any());
        await sender.send(audioChunk,
            Endpoint.unicast(InternetAddress(user.ipAddress), port: Port(6006)));
        sender.close();
      }
    }
  }

  void _listenForStreamedAudio() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6006)));
    print("🔄 [CLIENT] Listening for streamed audio on port 6006...");

    receiver.asStream().listen((datagram) async {
      if (datagram != null && datagram.data.isNotEmpty) {
        Uint8List audioData = datagram.data;

        // Check for stop signal
        if (audioData.length == 4 &&
            audioData[0] == 0xFF &&
            audioData[1] == 0xFF &&
            audioData[2] == 0xFF &&
            audioData[3] == 0xFF) {
          await _stopPlayerForStream();
          _silenceTimer?.cancel();
          return;
        }

        // Ensure player is ready before feeding data
        await _startPlayerForStream();

        // Reset silence timer
        _silenceTimer?.cancel();
        _silenceTimer = Timer(Duration(milliseconds: 100), () async {
          await _stopPlayerForStream();
          print(
              "🔇 [CLIENT] No audio data received for 500ms, stopping player...");
        });

        // Feed audio data
        try {
          await _audioPlayer!.feedFromStream(audioData);
        } catch (e) {
          print("⚠️ [CLIENT] Error feeding audio stream: $e");
        }
      }
    });
  }

  void _listenForAudio() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6005)));
    print("🔄 [CLIENT] Listening for audio on port 6005...");

    receiver.asStream().listen((datagram) async {
      if (datagram != null && datagram.data.isNotEmpty) {
        Uint8List audioData = datagram.data;
        await _playAudio(audioData);
      }
    });
  }

  Future<void> _playAudio(Uint8List audioData) async {
    String tempPath = '${Directory.systemTemp.path}/audio.aac';
    await File(tempPath).writeAsBytes(audioData);
    await _audioPlayer!.startPlayer(fromURI: tempPath, codec: Codec.aacADTS);
  }

  void _startRecording() async {
    if (_isRecording) return;

    setState(() {
      _isRecording = true;
    });

    await _audioRecorder!
        .startRecorder(toFile: 'audio.aac', codec: Codec.aacADTS);

    _audioRecorder!.onProgress!.listen((RecordingDisposition disposition) {
      // Handle recording progress if needed
    });
  }

  void _stopRecording() async {
    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
    });

    String? path = await _audioRecorder!.stopRecorder();
    if (path != null) {
      Uint8List audioData = await File(path).readAsBytes();
      _sendAudioData(audioData);
    }
  }

  void _sendAudioData(Uint8List audioData) async {
    for (User user in connectedUsers) {
      if (user.ipAddress != _myIpAddress) {
        // Skip your own IP
        UDP sender = await UDP.bind(Endpoint.any());
        await sender.send(
            audioData, Endpoint.unicast(InternetAddress(user.ipAddress), port: Port(6005)));
        sender.close();
      }
    }
  }

  // void _listenForAudio() async {
  //   UDP receiver = await UDP.bind(Endpoint.any(port: Port(6005)));
  //   print("🔄 [CLIENT] Listening for audio on port 6005...");
  //
  //   receiver.asStream().listen((datagram) async {
  //     if (datagram != null && datagram.data.isNotEmpty) {
  //       Uint8List audioData = datagram.data;
  //       await _playAudio(audioData);
  //     }
  //   });
  // }
  //
  // Future<void> _playAudio(Uint8List audioData) async {
  //   String tempPath = '${Directory.systemTemp.path}/audio.aac';
  //   await File(tempPath).writeAsBytes(audioData);
  //   await _audioPlayer!.startPlayer(fromURI: tempPath, codec: Codec.aacADTS);
  // }

  // Future<void> _playAudio(Uint8List audioData) async {
  //   String tempPath = '${Directory.systemTemp.path}/audio.aac';
  //   await File(tempPath).writeAsBytes(audioData);
  //   await _audioPlayer!.startPlayer(fromURI: tempPath, codec: Codec.aacADTS);
  // }

  void _startReceivingRequests() async {
    udpSocket =
        await UDP.bind(Endpoint.any(port: Port(6002))); // Host listens on 6002
    print("🔵 [HOST] Listening for join requests on port 6002...");

    // Add the host itself to the list
    String hostIp = widget.host.ipAddress;
    if (!connectedUsersContains(hostIp)) {
      setState(() {
        connectedUsers.add(User(ipAddress: hostIp, userName: widget.host.hostName));
      });
    }

    udpSocket!.asStream().listen((datagram) async {
      if (datagram != null) {
        String message = String.fromCharCodes(datagram.data);
        String userIp = datagram.address.address;

        if (message == "JABBERY_DISCOVER") {
          print(
              "📡 [HOST] Discovery request received from $userIp, responding...");

          UDP sender = await UDP.bind(Endpoint.any());
          await sender.send(
              hostIp.codeUnits,
              Endpoint.unicast(InternetAddress(userIp),
                  port: Port(discoveryPort)));
          sender.close();
        } else if (message.startsWith("JABBERY_JOIN")) {
          print("✅ [HOST] Join request received from: $userIp");
          String userName = message.split("|")[2];
          if (!connectedUsersContains(userIp)) {
            setState(() {
              connectedUsers.add(User(ipAddress: userIp, userName: userName));
            });
          }
          _broadcastUserList();

          // ✅ Send confirmation to new client
          UDP sender = await UDP.bind(Endpoint.any());
          await sender.send("JOINED".codeUnits,
              Endpoint.unicast(InternetAddress(userIp), port: Port(6003)));
          sender.close();
        }
      }
    });
  }

  void _sendJoinRequest() async {
    print(
        "📩 [CLIENT] Sending join request to: ${widget.host.ipAddress}:6002"); // Debug log

    if (widget.host.ipAddress.isEmpty) {
      print("❌ Invalid Host IP");
      return;
    }

    UDP sender = await UDP.bind(Endpoint.any());
    while (connectedUsers.isEmpty) {
      await sender.send(Uint8List.fromList("JABBERY_JOIN|$widget".codeUnits),
          Endpoint.unicast(InternetAddress(widget.host.ipAddress), port: Port(6002)));
      await Future.delayed(Duration(milliseconds: 500));
    }
    sender.close();
    print("📩 [CLIENT] Join request sent to ${widget.host.hostName} at ${widget.host.ipAddress}");
  }

  void _broadcastUserList() async {
    if (connectedUsers.isEmpty) return;

    String userList = connectedUsers.join('|');
    Uint8List data = Uint8List.fromList(userList.codeUnits);

    print("📢 [HOST] Sending updated user list: $userList");

    for (User user in connectedUsers) {
      UDP sender = await UDP.bind(Endpoint.any());
      await sender.send(
          data, Endpoint.unicast(InternetAddress(user.ipAddress), port: Port(6003)));
      sender.close();
    }
  }

  void _listenForUpdates() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6003)));
    print("🔄 [CLIENT] Listening for user list updates on port 6003...");

    receiver.asStream().listen((datagram) {
      if (datagram != null && datagram.data.isNotEmpty) {
        String receivedData = String.fromCharCodes(datagram.data);
        print("receivedData $receivedData");

        List<User> updatedUsers = [];

        List<String> dataParts = receivedData.split('|');

        if (dataParts.length % 2 == 0) {
          for (int i = 0; i < dataParts.length; i += 2) {
            String ipAddress = dataParts[i];
            String userName = dataParts[i + 1];
            updatedUsers.add(User(ipAddress: ipAddress, userName: userName));
          }
        } else {
          print("⚠️ [CLIENT] Malformed user list data: $receivedData");
        }

        print("🔄 [CLIENT] Received updated user list: $updatedUsers");

        setState(() {
          connectedUsers = updatedUsers;
        });
      }
    });
  }

  TextEditingController messageController = TextEditingController();
  List<String> messages = []; // Stores received messages

  void _sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    Uint8List data = Uint8List.fromList(message.codeUnits);
    print("📢 Sending message: $message");

    // Ensure message is sent to all users, including the host
    for (User user in connectedUsers) {
      UDP sender = await UDP.bind(Endpoint.any());
      await sender.send(
          data, Endpoint.unicast(InternetAddress(user.ipAddress), port: Port(6004)));
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
      // resizeToAvoidBottomInset :false,
      extendBodyBehindAppBar: true,
      // appBar: AppBar(title: Text(''), automaticallyImplyLeading: false),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF6767), Color(0xFF11E0DC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            SizedBox(height: kToolbarHeight),
            Text("Connected Users",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (connectedUsers.isEmpty)
              Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  "No users connected yet",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              )
            else
              Column(
                children: connectedUsers.map((user) {
                  String userIp = user.ipAddress;
                  String userName = user.userName;
                  bool isHost = userIp == widget.host.ipAddress;
                  bool isMe = userIp == _myIpAddress;

                  String displayText;
                  if (isHost && isMe) {
                    displayText = "You";
                  } else if (isHost) {
                    displayText = "Host";
                  } else if (isMe) {
                    displayText = "You";
                  } else {
                    displayText = "User";
                  }

                  return Container(
                    margin: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isHost ? Icons.cell_tower	 : Icons.person,
                          color: isHost ? Colors.blueGrey : Colors.blueGrey,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          "$displayText: $userName",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),

              ),

            // SizedBox(height: 0),
            // Text("Chat Messages",
            //     style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Expanded(
              child: Container(
                margin: EdgeInsets.all(10),
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: messages.isEmpty
                    ? Center(
                        child: Text("No messages yet",
                            style: TextStyle(color: Colors.grey)))
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
                            child: Text(messages[index],
                                style: TextStyle(fontSize: 14)),
                          );
                        },
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: messageController,
                        decoration: InputDecoration(
                          hintText: "Type a message...",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _sendMessage(messageController.text),
                      icon: Icon(Icons.send, color: Colors.blueAccent),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  "Voice Message",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Recording Button
                    IconButton(
                      onPressed:
                          _isRecording ? _stopRecording : _startRecording,
                      icon: Icon(
                        _isRecording ? Icons.stop_circle : Icons.mic,
                        size: 36,
                        color:
                            _isRecording ? Colors.redAccent : Colors.blueAccent,
                      ),
                      tooltip:
                          _isRecording ? 'Stop Recording' : 'Start Recording',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        padding: EdgeInsets.all(12),
                        shape: CircleBorder(),
                        shadowColor: Colors.black.withOpacity(0.2),
                        elevation: 4,
                      ),
                    ),
                    SizedBox(width: 16),
                    // Push-to-Talk Button
                    IconButton(
                      onPressed:
                          _isStreaming ? _stopStreaming : _startStreaming,
                      icon: Icon(
                        _isStreaming ? Icons.cancel : Icons.record_voice_over,
                        size: 36,
                        color: _isStreaming
                            ? Colors.orangeAccent
                            : Colors.greenAccent,
                      ),
                      tooltip: _isStreaming ? 'Stop Talking' : 'Push to Talk',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        padding: EdgeInsets.all(12),
                        shape: CircleBorder(),
                        shadowColor: Colors.black.withOpacity(0.2),
                        elevation: 4,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            SizedBox(height: kToolbarHeight),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    udpSocket?.close();
    // _audioStreamController.close();

    _audioRecorder!.closeRecorder();
    _audioPlayer!.closePlayer();
    super.dispose();
  }

  bool connectedUsersContains(String ip) {
    for (User user in connectedUsers) {
      if (user.ipAddress == ip) {
        return true;
      }
    }
    return false;
  }
}
