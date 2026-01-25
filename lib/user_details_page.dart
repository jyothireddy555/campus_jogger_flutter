import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // contains HomePage


class UserDetailsPage extends StatefulWidget {
  final String userEmail;
  final int userId;
  final bool isEdit;
  final String userName;
  final String? profileImageUrl;


  const UserDetailsPage({
    super.key,
    required this.userEmail,
    required this.userId,
    required this.userName,
    this.profileImageUrl,
    this.isEdit = false,
  });


  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}


class _UserDetailsPageState extends State<UserDetailsPage> {
  final ageCtrl = TextEditingController();
  final weightCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  Future<void> _loadExistingData() async {
    final prefs = await SharedPreferences.getInstance();
    final age = prefs.getInt("age_${widget.userEmail}");
    final weight = prefs.getDouble("weight_${widget.userEmail}");

    if (age != null) ageCtrl.text = age.toString();
    if (weight != null) weightCtrl.text = weight.toString();
  }

  Future<void> _save() async {
    final age = int.tryParse(ageCtrl.text);
    final weight = double.tryParse(weightCtrl.text);

    if (age == null || weight == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Enter valid data")));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("age_${widget.userEmail}", age);
    await prefs.setDouble("weight_${widget.userEmail}", weight);
    await prefs.setBool("profile_done_${widget.userEmail}", true);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(
          userId: widget.userId,
          email: widget.userEmail,
          name: widget.userName,
          profileImageUrl: widget.profileImageUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? "Edit Profile" : "Your Details"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: ageCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Age"),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: weightCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Weight (kg)"),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _save,
              child: Text(widget.isEdit ? "Update" : "Continue"),
            )
          ],
        ),
      ),
    );
  }
}
