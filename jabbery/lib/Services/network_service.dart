import 'dart:io';
import 'dart:async';
import 'package:udp/udp.dart';
import '../Model/Host.dart';

class NetworkService {
  static const int discoveryPort = 5000;
  UDP? _udpSender;
  UDP? _udpReceiver;
  StreamSubscription? _udpSubscription;

  Future<String> startHosting() async {
    _udpSender = await UDP.bind(Endpoint.any());
    _udpReceiver = await UDP.bind(Endpoint.any(port: Port(discoveryPort)));

    String? localIp = await getLocalIp();
    if (localIp == null) {
      throw Exception("Could not determine local IP");
    }
    print("🔵 [HOST] Hosting Lobby...");
    print("🔹 Local IP: $localIp");
    print("🔹 Broadcasting on port: $discoveryPort");

    Timer.periodic(Duration(seconds: 2), (timer) async {
      String response = "JABBERY_HOST|$localIp"; // ✅ Include host IP
      int sentBytes = await _udpSender!.send(
        response.codeUnits,
        Endpoint.broadcast(port: Port(discoveryPort)), // ✅ Explicit broadcast
      );
      print(
          "✅ [HOST] Sent $sentBytes bytes to 192.168.39.255:$discoveryPort with message: $response");
    });

    // _udpReceiver!.asStream().listen((datagram) {
    //   if (datagram == null || datagram.data.isEmpty) {
    //     print("⚠️ [HOST] Received empty or null datagram, ignoring...");
    //     return;
    //   }
    //
    //   String message = String.fromCharCodes(datagram.data); // ✅ Now safe
    //   String senderIp = datagram.address.address; // ✅ Extract sender IP safely
    //
    //   print("📩 [HOST] Received: $message from $senderIp");
    //
    //   if (message == "JABBERY_DISCOVER") {
    //     print("📡 [HOST] Responding to discovery request...");
    //     String response = "JABBERY_HOST|$localIp";
    //     _udpSender!.send(
    //         response.codeUnits,
    //         Endpoint.unicast(InternetAddress(senderIp),
    //             port: Port(discoveryPort)));
    //   }
    // });
    return localIp;
  }

  Future<List<Host?>> findHosts() async {
    bool listenForHosts = true;
    _udpReceiver = await UDP.bind(Endpoint.any(port: Port(discoveryPort)));

    print("🔍 [CLIENT] Listening for lobbies on port $discoveryPort...");

    Set<Host> discoveredHosts = {}; // Store multiple hosts

    // ✅ Get client’s own local IP
    String? myIp = await getLocalIp();
    print("🟢 [CLIENT] My IP: $myIp");

    // ✅ Get broadcast address
    String? broadcastIp = await getBroadcastAddress();
    if (broadcastIp == null) {
      print("❌ [CLIENT] Could not determine broadcast address");
      return [];
    }
    print("📢 [CLIENT] Sending discovery requests to $broadcastIp:$discoveryPort");

    _udpSubscription = _udpReceiver!.asStream().listen((datagram) {
      if (datagram != null) {
        String message = String.fromCharCodes(datagram.data);
        String senderIp = datagram.address.address;

        if (senderIp == myIp) {
          print("⚠️ [CLIENT] Ignoring own broadcast from $senderIp");
          return;
        }

        print("✅ [CLIENT] Received: $message from $senderIp");

        if (message.startsWith("JABBERY_HOST|")) {
          String hostIp = message.split("|")[1];
          String hostName = message.split("|")[2];
          Host host = Host(ipAddress: hostIp,hostName: hostName);
          discoveredHosts.add(host);
          listenForHosts = true;
        }
      }
    });

    int maxTries=3;
    int attempt=1;
    // ✅ Send multiple discovery requests for better reliability
    // UDP sender = await UDP.bind(Endpoint.any());
    while (discoveredHosts.isEmpty || listenForHosts || attempt>maxTries) {
      print("Listening for Hosts");
      listenForHosts = false;
      // int sentBytes = await sender.send(
      //   "JABBERY_DISCOVER".codeUnits,
      //   Endpoint.broadcast(port: Port(discoveryPort)),
      // );
      // print("📢 [CLIENT] Sent $sentBytes bytes to $broadcastIp:$discoveryPort");
      await Future.delayed(Duration(seconds: 5)); // Wait before retrying
    }

    // sender.close();

    // ✅ Return the list of discovered hosts
    if (discoveredHosts.isNotEmpty) {
      print("✅ [CLIENT] Returning List of hosts: $discoveredHosts");
      return discoveredHosts.toList();
    }

    print("❌ No lobby found within timeout.");
    return [];
  }


  Future<String?> getBroadcastAddress() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            addr.address.startsWith("192.168.")) {
          // Ensure it's a WiFi IP
          print(
              "🔍 Found WiFi IP: ${addr.address} on interface: ${interface.name}");
          List<String> parts = addr.address.split('.');
          if (parts.length == 4) {
            String broadcastIp = "${parts[0]}.${parts[1]}.${parts[2]}.255";
            print("📢 Using Correct Broadcast IP: $broadcastIp");
            return broadcastIp;
          }
        }
      }
    }
    print("❌ Could not determine correct broadcast address.");
    return null;
  }

  Future<String?> getLocalIp() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            addr.address.startsWith("192.168.")) {
          // Ensure it's a WiFi IP
          return addr.address;
        }
      }
    }
    return null;
  }

  void dispose() {
    _udpSender?.close();
    _udpReceiver?.close();
    _udpSubscription?.cancel();
  }
}
