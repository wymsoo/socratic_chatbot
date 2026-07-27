import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class LearningStyleQuizPage extends StatefulWidget {
  const LearningStyleQuizPage({Key? key}) : super(key: key);

  @override
  State<LearningStyleQuizPage> createState() => _LearningStyleQuizPageState();
}

class _LearningStyleQuizPageState extends State<LearningStyleQuizPage> {
  // Update host according to your environment (10.0.2.2 for Android emulator)
  final String _apiUrl = 'http://172.20.10.4:8000/api/quiz';

  List<dynamic> _questions = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Stores responses: { question_id: answer_string }
  final Map<String, String> _answers = {};

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  Future<void> _fetchQuestions() async {
    try {
      final response = await http.get(Uri.parse(_apiUrl));
      if (response.statusCode == 200) {
        setState(() {
          _questions = json.decode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load quiz questions';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _submitQuiz() async {
    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/submit'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(_answers),
      );
      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quiz submitted successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryTextColor = Color(0xFF2C3E50);

    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: primaryTextColor),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background graphic pattern (if asset exists)
          Positioned.fill(
            child: Image.asset(
              'assets/background_pattern.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: const Color(0xFFEDF2F7),
              ),
            ),
          ),
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Title Header
                            const Text(
                              'Personality Quiz',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Intro Card
                            const Text(
                              'Backed by educational research, this quick 10-question quiz identifies your unique thinking style, interests, and study preferences. In minutes, you’ll unlock an adaptive AI tutor configured to explain complex concepts using tailored analogies, your favorite hobbies, and your ideal pace.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Render Dynamic Questions
                            ..._questions.map((q) => _buildQuestionCard(q)),
                            const SizedBox(height: 24),
                            // Submit Button
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3182CE),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _submitQuiz,
                              child: const Text(
                                'Submit Quiz',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(Map<String, dynamic> q) {
    final String qId = q['id'];
    final String questionText = q['question'];
    final String type = q['type'];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            questionText,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C3E50),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          if (type == 'open')
            TextField(
              maxLines: 4,
              onChanged: (val) => _answers[qId] = val,
              decoration: InputDecoration(
                hintText: 'Type your response here...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF3182CE)),
                ),
              ),
            )
          else if (type == 'choice' && q.containsKey('options'))
            ...((q['options'] as Map<String, dynamic>).entries.map((entry) {
              final optionKey = entry.key;
              final optionValue = entry.value as String;
              final bool isSelected = _answers[qId] == optionKey;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _answers[qId] = optionKey;
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFEBF8FF)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF3182CE)
                            : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        optionValue,
                        style: TextStyle(
                          fontSize: 14,
                          color: isSelected
                              ? const Color(0xFF2B6CB0)
                              : const Color(0xFF4A5568),
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList()),
        ],
      ),
    );
  }
}