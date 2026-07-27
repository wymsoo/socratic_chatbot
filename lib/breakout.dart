import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const String sampleLectureSnippet = """
The primary goal of statistical thermodynamics (also known as equilibrium statistical mechanics) is to derive the classical thermodynamics of materials in terms of the properties of their constituent particles and the interactions between them. In other words, statistical thermodynamics provides a connection between the macroscopic properties of materials in thermodynamic equilibrium, and the microscopic behaviours and motions occurring inside the material.

Whereas statistical mechanics proper involves dynamics, here the attention is focused on statistical equilibrium (steady state). Statistical equilibrium does not mean that the particles have stopped moving (mechanical equilibrium), rather, only that the ensemble is not evolving.

Fundamental postulate
A sufficient (but not necessary) condition for statistical equilibrium with an isolated system is that the probability distribution is a function only of conserved properties (total energy, total particle numbers, etc.). There are many different equilibrium ensembles that can be considered, and only some of them correspond to thermodynamics. Additional postulates are necessary to motivate why the ensemble for a given system should have one form or another.

A common approach found in many textbooks is to take the equal a priori probability postulate. This postulate states that

For an isolated system with an exactly known energy and exactly known composition, the system can be found with equal probability in any microstate consistent with that knowledge.
The equal a priori probability postulate therefore provides a motivation for the microcanonical ensemble described below. There are various arguments in favour of the equal a priori probability postulate:

Ergodic hypothesis: An ergodic system is one that evolves over time to explore "all accessible" states: all those with the same energy and composition. In an ergodic system, the microcanonical ensemble is the only possible equilibrium ensemble with fixed energy. This approach has limited applicability, since most systems are not ergodic.
Principle of indifference: In the absence of any further information, we can only assign equal probabilities to each compatible situation.
Maximum information entropy: A more elaborate version of the principle of indifference states that the correct ensemble is the ensemble that is compatible with the known information and that has the largest Gibbs entropy (information entropy).
Other fundamental postulates for statistical mechanics have also been proposed.
""";

void main() {
  runApp(const SocraticTutorApp());
}

class SocraticTutorApp extends StatelessWidget {
  const SocraticTutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Socratic AI Tutor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B365D)),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final String senderName;
  final List<String>? choices;
  final bool allowCustomResponse;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.senderName,
    this.choices,
    this.allowCustomResponse = false,
  });
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  final List<ChatMessage> _messages = [];

  bool _isLoading = false;
  String? _sessionId;
  List<String> _confusingStatements = [];
  String _sessionStatus = "initializing";
  final String _backendUrl = 'http://172.20.10.4:8000';
  final Set<int> _selectedIndexes = <int>{};

  @override
  void initState() {
    super.initState();
    _initializeSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeSession() async {
    setState(() {
      _isLoading = true;
      _messages.add(
        ChatMessage(
          text: "Analyzing your lecture content...",
          isUser: false,
          senderName: "🤖 System",
        ),
      );
    });

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/initialize'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'lecture_snippet': sampleLectureSnippet}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _sessionId = data['session_id'];
        final dynamic statements = data['confusing_statements'];
        final dynamic summary = data['summary'];

        setState(() {
          _confusingStatements = List<String>.from(statements);
          _sessionStatus = "selection";
          _messages.add(
            ChatMessage(
              text:
                  "$summary\n\nWhich of the following topics is most confusing to you?",
              isUser: false,
              senderName: "🤖 Tutor",
            ),
          );
        });
      } else {
        _showErrorBubble("Initialization failed: ${response.statusCode}");
      }
    } catch (e) {
      _showErrorBubble("Unable to connect to tutor service.");
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _toggleSelect(int index) {
    setState(() {
      if (_selectedIndexes.contains(index)) {
        _selectedIndexes.remove(index);
      } else {
        _selectedIndexes.add(index);
      }
    });
  }

  Future<void> _confirmSelection() async {
    if (_sessionId == null || _selectedIndexes.isEmpty) return;
    final selectedConcepts = _selectedIndexes
        .map((i) => _confusingStatements[i])
        .toList();

    setState(() {
      _isLoading = true;
      _sessionStatus = "tutoring";
      _messages.add(
        ChatMessage(
          text: selectedConcepts.join(', '),
          isUser: true,
          senderName: "You",
        ),
      );
    });

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/select_concept'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': _sessionId,
          'selected_concepts': selectedConcepts,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Parse tutor_response and choices
        final responseObj = data['tutor_response'];
        final overviewText = data['overview'];
        final String tutorText = (responseObj is Map)
            ? (responseObj['question'] ?? responseObj['text'] ?? '')
            : responseObj.toString();

        final dynamic mcqData = (responseObj is Map) ? responseObj['choices'] : null;
        List<String>? parsedChoices;
        if (mcqData is List) {
          parsedChoices = mcqData.map((choice) => choice.toString()).toList();
        } else if (mcqData is Map && mcqData['choices'] is List) {
          parsedChoices = (mcqData['choices'] as List)
              .map((choice) => choice.toString())
              .toList();
        }

        setState(() {
          _messages.add(
          ChatMessage(
            text: overviewText,
            isUser: false,
            senderName: "🤖 Tutor",
          ),
          );
          _messages.add(
            ChatMessage(
              text: tutorText.isNotEmpty ? tutorText : responseObj.toString(),
              isUser: false,
              senderName: "🤖 Tutor",
              choices: parsedChoices, // Pass parsed choices here
              allowCustomResponse: false,
            ),
          );
          _sessionStatus = data['status'] ?? "tutoring";
          _selectedIndexes.clear();
        });
      } else {
        _showErrorBubble('Failed to register concept selection.');
      }
    } catch (e) {
      _showErrorBubble('Connection lost while confirming selection.');
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }
  Future<void> _sendChatMessage(String text) async {
    if (text.trim().isEmpty || _sessionId == null) return;
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, senderName: "You"));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': _sessionId, 'message': text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final responseObj = data['tutor_response'];
        final String tutorText = (responseObj is Map) 
            ? (responseObj['question'] ?? responseObj['text'] ?? '')
            : responseObj.toString();

        final dynamic mcqData = (responseObj is Map) ? responseObj['choices'] : null;
        List<String>? parsedChoices;
        if (mcqData is List) {
          parsedChoices = mcqData.map((choice) => choice.toString()).toList();
        } else if (mcqData is Map && mcqData['choices'] is List) {
          parsedChoices = (mcqData['choices'] as List)
              .map((choice) => choice.toString())
              .toList();
        }

        setState(() {
          _messages.add(
            ChatMessage(
              text: tutorText.isNotEmpty ? tutorText : "Here is the next step:",
              isUser: false,
              senderName: "🤖 Tutor",
              choices: parsedChoices,
              allowCustomResponse: false,
            ),
          );
          _sessionStatus = data['status'] ?? "tutoring";
        });

        // 1. FIXED: Show dialog, and let the dialog handling call start test directly
        if (data['test_prompt'] == true) {
          _showTestConfirmation(
            data['test_instructions'] ?? "Ready to start the 3-question test?",
          );
        }
      } else {
        _showErrorBubble("Server returned error: ${response.statusCode}");
      }
    } catch (e) {
      _showErrorBubble("Failed to reach server.");
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  Future<void> _handleSubmitted(String text) async {
    await _sendChatMessage(text);
  }

  Future<void> _submitChatChoice(String answer) async {
    await _sendChatMessage(answer);
  }

  Future<void> _showTestConfirmation(String instructions) async {
    final userChoice = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24.0),
          ),
          backgroundColor: const Color(0xFFFFF2C2),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Test Understanding',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B365D),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ghosty will ask 3 questions to test your understanding on the discussed concepts. Each correct answer earns you 1 star.\n\nCompleting the questions will automatically end the session and mark Stash as resolved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF333333)),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFCC33),
                      foregroundColor: const Color(0xFF1B365D),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(
                      "I'm Ready!",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC7DCF9),
                      foregroundColor: const Color(0xFF1B365D),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      'Back to Discussion',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (userChoice == true) {
      await _handleStartTest();
    }
  }

  Future<void> _handleStartTest() async {
    if (_sessionId == null || _isLoading) return;
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/start_test'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': _sessionId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        final rawQuestion = data['tutor_response'];
        String firstQuestionText = data['raw_question'] ?? '';
        List<String>? choices;

        if (rawQuestion is Map) {
          firstQuestionText = rawQuestion['question']?.toString() ?? firstQuestionText;
          final rawChoices = rawQuestion['choices'];
          
          if (rawChoices is List) {
            choices = rawChoices.map((choice) {
              if (choice is Map && choice.containsKey('text')) {
                return choice['text'].toString();
              }
              return choice.toString();
            }).toList();
          }
        }

        final index = data['question_index'] ?? 1;
        final total = data['total_questions'] ?? 3;

        await _showTestQuestionDialog(
          firstQuestionText,
          index,
          total,
          options: choices,
        );
      } else {
        _showErrorBubble('Failed to start test.');
      }
    } catch (e) {
      _showErrorBubble('Unable to start test.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitTestAnswer(String answer) async {
    if (_sessionId == null) return;
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/submit_answer'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': _sessionId, 'answer': answer}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final feedback = data['tutor_response'] ?? 'Feedback';
        setState(() {
          _messages.add(
            ChatMessage(
              text: feedback,
              isUser: false,
              senderName: '🤖 Tutor',
            ),
          );
        });

        if (data.containsKey('next_question')) {
          final nextQObj = data['next_question'];
          String nextQText = "";
          List<String>? options;

          if (nextQObj is Map) {
            nextQText = nextQObj['question']?.toString() ?? '';
            final rawChoices = nextQObj['choices'];
            if (rawChoices is List) {
              options = rawChoices.map((choice) {
                if (choice is Map && choice.containsKey('text')) {
                  return choice['text'].toString();
                }
                return choice.toString();
              }).toList();
            }
          } else {
            nextQText = nextQObj.toString();
          }

          final idx = data['question_index'] ?? 1;
          final tot = data['total_questions'] ?? 3;

          await _showTestQuestionDialog(nextQText, idx, tot, options: options);
        } else {
          
          // Test complete modal logic
          final summary = data['final_summary'] ?? 'Good job!';
          final competency = data['competency_notes'] ?? '';
          final reportContent = data['report_content'] ?? 'No report details found.';
          final stash = data['stash_stars'] ?? 0;

          if (!mounted) return;
          final dialogContext = context;
          await showDialog<void>(
            context: dialogContext,
            builder: (context) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24.0),
                ),
                backgroundColor: const Color(0xFFFFF2C2),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Session Complete',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Color(0xFF1B365D),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) {
                          return Icon(
                            Icons.star,
                            size: 40,
                            color: i < stash
                                ? const Color(0xFFFFCC33)
                                : Colors.grey.shade400,
                          );
                        }),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'What you covered:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF1B365D),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(summary, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 16),
                      
                      // View Report Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B365D),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24.0),
                            ),
                          ),
                          onPressed: () => _downloadReportPdf(reportContent),
                          label: const Text(
                            'View Report',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Complete / Dismiss Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF1B365D),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24.0),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }
      } else {
        _showErrorBubble('Failed to submit answer.');
      }
    } catch (e) {
      _showErrorBubble('Error while submitting answer.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Helper function to generate and download the PDF report
  Future<void> _downloadReportPdf(String reportContent) async {
    final pdf = pw.Document();

    // Split the massive text string into smaller chunks (paragraphs/lines)
    final List<String> textBlocks = reportContent.split('\n');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32), // Add some nice margins
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Session Study Report',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            
            // Map each paragraph to its own Text widget so it paginates perfectly
            ...textBlocks.map(
              (block) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6.0),
                child: pw.Text(
                  block,
                  style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.5),
                ),
              ),
            ),
          ];
        },
      ),
    );

    // Layout the PDF (handles preview and download on both mobile and web)
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Socratic_Tutor_Report.pdf',
    );
  }
  // 3. FIXED: Strictly Multiple Choice Only
  Future<void> _showTestQuestionDialog(
    String question,
    int index,
    int total, {
    List<String>? options,
  }) async {
    String? selectedChoice;
    final List<String> effectiveOptions = (options != null && options.isNotEmpty)
        ? options
        : ["Option A", "Option B", "Option C", "Option D"];

    final dialogContext = context;
    await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final bool canSubmit = selectedChoice != null;

            return AlertDialog(
              backgroundColor: const Color(0xFFFFF2C2),
              title: Text(
                'Question $index of $total',
                style: const TextStyle(
                  color: Color(0xFF1B365D),
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question,
                      style: const TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    ...effectiveOptions.map((option) {
                      final isSelected = selectedChoice == option;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: InkWell(
                          onTap: () => setState(() {
                            selectedChoice = option;
                          }),
                          borderRadius: BorderRadius.circular(12.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF1B365D)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 12.0,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 10.0),
                                Expanded(
                                  child: Text(
                                    option,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFCC33),
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  onPressed: canSubmit
                      ? () {
                          Navigator.of(context).pop(true);
                          _submitTestAnswer(selectedChoice!);
                        }
                      : null,
                  child: const Text(
                    'Submit Answer',
                    style: TextStyle(color: Color(0xFF1B365D)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showErrorBubble(String message) {
    setState(() {
      _messages.add(
        ChatMessage(
          text: "System Alert: $message",
          isUser: false,
          senderName: "⚠️ System",
        ),
      );
    });
    _scrollToBottom();
  }

  Future<void> _showEndSessionConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Exit Session'),
          content: const Text('Are you sure you want to exit?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildAvatar(bool isUser) {
    if (isUser) {
      return const CircleAvatar(
        radius: 18,
        backgroundImage: AssetImage('assets/user.png'),
        backgroundColor: Colors.transparent,
      );
    }
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFC7DCF9),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/tutor.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.school, color: Color(0xFF1B365D), size: 20),
        ),
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    final bool hasChoices =
        !message.isUser && message.choices != null && message.choices!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: message.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: message.isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!message.isUser) ...[
                _buildAvatar(false),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(14.0),
                  decoration: BoxDecoration(
                    color: message.isUser
                        ? const Color(0xFF4A6FA5)
                        : const Color(0xFFC7DCF9),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(message.isUser ? 18 : 4),
                      bottomRight: Radius.circular(message.isUser ? 4 : 18),
                    ),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      color: message.isUser
                          ? Colors.white
                          : const Color(0xFF1B365D),
                    ),
                  ),
                ),
              ),
              if (message.isUser) ...[
                const SizedBox(width: 8),
                _buildAvatar(true)
              ],
            ],
          ),

          if (hasChoices)
            Padding(
              padding: const EdgeInsets.only(left: 46.0, top: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...message.choices!.map((choice) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(129, 29, 70, 142),
                            foregroundColor: const Color.fromARGB(255, 195, 220, 255),
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isLoading
                              ? null
                              : () => _submitChatChoice(choice),
                          child: Text(
                            choice,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1B365D),
          image: DecorationImage(
            image: AssetImage('assets/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      'Statistical Mechanics',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: _showEndSessionConfirmation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Exit',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Chat Messages List
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    return _buildChatBubble(_messages[index]);
                  },
                ),
              ),

              // Concept Selection Buttons
              if (_sessionStatus == "selection" &&
                  _confusingStatements.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 6.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ..._confusingStatements.asMap().entries.map((entry) {
                        final index = entry.key;
                        final statement = entry.value;
                        final selected = _selectedIndexes.contains(index);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: InkWell(
                            onTap: _isLoading
                                ? null
                                : () => _toggleSelect(index),
                            borderRadius: BorderRadius.circular(14.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 12.0,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFC7DCF9)
                                    : const Color(0xFF2C4A7C),
                                borderRadius: BorderRadius.circular(14.0),
                                border: Border.all(
                                  color: selected
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                statement,
                                style: TextStyle(
                                  color: selected
                                      ? const Color(0xFF1B365D)
                                      : Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      if (_selectedIndexes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFCC33),
                                    foregroundColor: const Color(0xFF1B365D),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _isLoading
                                      ? null
                                      : _confirmSelection,
                                  child: const Text(
                                    'Confirm Selection',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => setState(
                                        () => _selectedIndexes.clear(),
                                      ),
                                child: const Text(
                                  'Clear',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.0),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                  ),
                ),

              // 2. REMOVED: The "Test Understanding" button bar was here and has been removed.

              // Text Input Dock Bar
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C4A7C),
                  borderRadius: BorderRadius.circular(28.0),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _inputFocusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        onSubmitted: _sessionStatus == "terminated"
                            ? null
                            : _handleSubmitted,
                        enabled:
                            _sessionStatus != "selection" &&
                            _sessionStatus != "terminated",
                        decoration: const InputDecoration(
                          hintText: "Type whats on your mind...",
                          hintStyle: TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap:
                          (_sessionStatus == "selection" ||
                              _sessionStatus == "terminated" ||
                              _isLoading)
                          ? null
                          : () => _handleSubmitted(_controller.text),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF4A80F0),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}