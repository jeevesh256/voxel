import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
      ),
      body: ListView(
        children: [
          _buildSection(
            'Playback',
            [
              _buildSwitchTile('Gapless Playback', true),
              _buildSwitchTile('Normalize Volume', false),
              _buildSwitchTile('Equalizer', false),
            ],
          ),
          _buildSection(
            'Downloads',
            [
              _buildSwitchTile('Download over Cellular', false),
              _buildSwitchTile('Auto Download', true),
            ],
          ),
          _buildSection(
            'Other',
            [
              ListTile(
                title: const Text('About'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {},
              ),
              ListTile(
                title: const Text('Help'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }

  Widget _buildSwitchTile(String title, bool initialValue) {
    return SwitchListTile(
      title: Text(title),
      value: initialValue,
      onChanged: (value) {},
    );
  }
}
