import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jabbery/Model/User.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../Services/network_service.dart';
import '../Model/Host.dart';

import 'lobby_screen.dart';
import 'ChooseLobbyScreen.dart';

class HomeScreen extends StatelessWidget {
  final NetworkService networkService = NetworkService();

  HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF11E0DC), // Jabbery theme color
              Color(0xFFFF6767), // Complementary gradient color
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Jabbery Logo or Icon
              Icon(
                LucideIcons.radio, // Use a walkie-talkie style icon
                size: 100,
                color: Colors.white,
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'Jabbery',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                'Walkie-Talkie for Groups',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                ),
              ),

              const SizedBox(height: 40),

              // Create Lobby Button (with Name Input)
              _buildButton(
                context,
                icon: LucideIcons.plusCircle,
                label: 'Create Lobby',
                onTap: () => _showHostNameDialog(context),
              ),

              const SizedBox(height: 20),

              // Join Lobby Button
              _buildButton(
                context,
                icon: LucideIcons.radioTower,
                label: 'Join Lobby',
                onTap: () async {
                  _showLoadingDialog(context); // Show loading dialog

                  List<Host?> hostAddresses = await networkService.findHosts();

                  // Dismiss loading dialog
                  Navigator.pop(context);

                  if (hostAddresses.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChooseLobbyScreen(
                          availableHosts: hostAddresses,
                        ),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("No lobbies found."),
                      ),
                    );
                  }
                },
              ),

              const Spacer(),

              // Bottom Tagline
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  'Stay in sync with your crew 😎',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Custom Button Widget
  Widget _buildButton(
      BuildContext context, {
        required IconData icon,
        required String label,
        required VoidCallback onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              offset: const Offset(0, 4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show Host Name Dialog
  void _showHostNameDialog(BuildContext context) {
    TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Enter Host Name"),
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
            onPressed: () async {
              String hostName = nameController.text.trim();
              if (hostName.isNotEmpty) {
                Navigator.pop(context); // Close dialog

                String hostIp = await networkService.startHosting();

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LobbyScreen(
                      isHost: true,
                      host: Host(ipAddress: hostIp, hostName: hostName), // Pass host to LobbyScreen
                      user: User(ipAddress: hostIp, userName: hostName),
                    ),
                  ),
                );
              }
            },
            child: Text("Start Lobby"),
          ),
        ],
      ),
    );
  }

  // Show Loading Dialog
  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing by tapping outside
      builder: (BuildContext context) {
        return Stack(
          children: [
            // Blurred background
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Container(
                color: Colors.black.withOpacity(0.2),
              ),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Color(0xFF11E0DC),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
