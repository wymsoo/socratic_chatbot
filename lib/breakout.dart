import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

const String sampleLectureSnippet = """
Most production agents build on the context window with one or more storage patterns.

1. Raw transcript storage
The simplest pattern is storing complete conversation logs in a database or logging system. To reuse them:

Retrieve a user’s past messages by ID

Optionally summarise them

Add them to the context for the next query

This approach is:

Easy to implement

Good for compliance and debugging

Weak for retrieval and personalization

Limitations:

Retrieval is usually basic (time-based, not semantic)

Summarisation is lossy and non-incremental

No structure for user profile vs transient context

2. Vector store-based semantic memory
Another common pattern uses embeddings and a vector database:

Generate embeddings for user or message chunks

Store embeddings with metadata

At query time, embed the new message and run KNN similarity search

Inject top results back into the prompt

This improves relevance for long-tail queries and cross-session recall. Yet it still behaves largely as a retrieval layer, not a true memory system:

It rarely distinguishes between stable facts and transient chatter

Facts are not updated, only added

Memory management (deduplication, decay, merging) is manual

3. Application database as "memory."
Many teams store user state in first-class tables:

users: profile fields and preferences

settings: notification, language, access control

tasks or projects: ongoing workflows and status

This gives durability and structure, but requires:

Custom schema design for every new agent feature

Glue code to keep the chatbot and database in sync

Manual reasoning about what belongs in SQL vs in prompts

The core trade-off appears:

While structured data is reliable and cheap, it is expensive to maintain and evolve.

While prompt-based context is flexible, it is ephemeral and costly.

Most systems end up combining all three patterns, but with ad hoc logic scattered across services.

The core memory problems in production agents
Illustrates the lifecycle of a memory from extraction to retrieval and update, clarifying how Mem0 differs from simple append only vector storage.
For AI engineers, the hard part is not storing data. The problems are around meaning and usage of memory.

1. What should be remembered
Not every user utterance deserves long-term storage. A good memory system must decide:

Is this a stable preference?

Is this a one-off constraint?

Is this only relevant to the current turn?

If everything is stored, retrieval becomes noisy and expensive. If too little is stored, personalization vanishes.

2. How memory evolves
Facts change over time. A user might say:

“I am a frontend engineer at Acme Corp.”

Then six months later:

“I just moved to backend engineering at Acme Corp.”

A naive vector store will keep both lines. At retrieval time, the model sees conflicting information. Real memory must handle:

Updates and overrides

Time-aware relevance

Merging and deduplication

3. How agents use memory consistently
When multiple agents or tools interact with the same user, they must see a coherent view of memory:

Chatbot agent

Scheduling agent

Knowledge search agent

Without a shared memory layer, each component builds its own partial "memory," leading to fragmentation and inconsistent behavior.

4. Operational constraints
Production systems also need:

Low latency and predictable cost

Observability into what was stored and retrieved

Access control and per-tenant separation

Migration paths when models and embeddings change

A memory solution must fit into the engineering stack, not just into the prompt.

Mem0 as a dedicated memory layer
Mem0 provides a memory layer designed specifically for LLMs and agents, with a few key design principles:

Memory as a first-class object: Mem0 treats memories as typed, queryable objects linked to identities and scopes, not just raw text chunks.

Automatic extraction from conversations: It uses LLMs and heuristics to extract meaningful facts, preferences, and events from chat logs, instead of storing every token.

Semantic and structured retrieval: Memories can be retrieved by semantic similarity, metadata filters, or both. The system can return concise, relevant snippets, not entire logs.

Cross-session and cross-agent sharing: Multiple agents can read and write to the same memory space, so a user’s preferences or history are visible across workflows.

Pluggable persistence: Mem0 can run as a managed API or self-hosted service. It integrates with common databases and vector stores while providing a stable API surface.

In production terms, Mem0 sits between the agent orchestration layer and storage, handling memory extraction, storage, and retrieval so application code stays focused on business logic.
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
} // <--- Fixed missing closing brace for SocraticTutorApp

class ChatMessage {
  final String text;
  final bool isUser;
  final String senderName;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.senderName,
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
        setState(() {
          _messages.add(
            ChatMessage(
              text: data['tutor_response'],
              isUser: false,
              senderName: "🤖 Tutor",
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

  Future<void> _handleSubmitted(String text) async {
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
        setState(() {
          _messages.add(
            ChatMessage(
              text: data['tutor_response'],
              isUser: false,
              senderName: "🤖 Tutor",
            ),
          );
          _sessionStatus = data['status'] ?? "tutoring";
        });

        if (data['test_prompt'] == true) {
          await _showTestConfirmation(
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
        final rawQuestion = data['raw_question'];
        String firstQuestionText = data['tutor_response'] ?? 'Question';
        List<String>? choices;

        if (rawQuestion is Map) {
          firstQuestionText =
              rawQuestion['question']?.toString() ?? firstQuestionText;
          final rawChoices = rawQuestion['choices'];
          if (rawChoices is List) {
            choices = rawChoices.map((choice) => choice.toString()).toList();
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

        if (data.containsKey('next_question')) {
          final nextQ = data['next_question'];
          final idx = data['question_index'] ?? 1;
          final tot = data['total_questions'] ?? 3;
          setState(() {
            _messages.add(
              ChatMessage(
                text: data['tutor_response'] ?? 'Feedback',
                isUser: false,
                senderName: '🤖 Tutor',
              ),
            );
          });
          await _showTestQuestionDialog(nextQ, idx, tot);
        } else {
          final summary = data['final_summary'] ?? 'Good job!';
          final competency = data['competency_notes'] ?? '';
          final stash = data['stash_stars'] ?? 2;

          await showDialog<void>(
            context: context,
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
                        'What you covered:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF1B365D),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(summary, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 12),
                      const Text(
                        'What to Improve:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF1B365D),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(competency, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) {
                          return Icon(
                            Icons.star,
                            size: 36,
                            color: i < stash
                                ? const Color(0xFFFFCC33)
                                : Colors.grey.shade400,
                          );
                        }),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFCC33),
                            foregroundColor: const Color(0xFF1B365D),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24.0),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'Complete',
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

  Future<void> _showTestQuestionDialog(
    String question,
    int index,
    int total, {
    List<String>? options,
  }) async {
    String? selectedChoice;
    final TextEditingController answerController = TextEditingController();

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFFFF2C2),
              title: Text(
                'Question $index of $total',
                style: const TextStyle(color: Color(0xFF1B365D)),
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
                    if (options != null && options.isNotEmpty)
                      ...options.map((option) {
                        final isSelected = selectedChoice == option;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: InkWell(
                            onTap: () =>
                                setState(() => selectedChoice = option),
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
                      })
                    else
                      TextField(
                        controller: answerController,
                        decoration: const InputDecoration(
                          hintText: 'Type your answer here',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFCC33),
                  ),
                  onPressed: () {
                    if (options != null && options.isNotEmpty) {
                      if (selectedChoice != null) {
                        Navigator.of(context).pop(true);
                        _submitTestAnswer(selectedChoice!);
                      }
                    } else {
                      Navigator.of(context).pop(true);
                      _submitTestAnswer(answerController.text.trim());
                    }
                  },
                  child: const Text(
                    'Submit',
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
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
          if (message.isUser) ...[const SizedBox(width: 8), _buildAvatar(true)],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1B365D), // Dark blue themed background
          image: DecorationImage(
            image: AssetImage('assets/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar Header with Title and Exit Button
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      'Change in Atomic States',
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

              // Test Understanding Yellow Action Bar
              if (_sessionStatus == 'tutoring')
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 6.0,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFCC33),
                        foregroundColor: const Color(0xFF1B365D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22.0),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isLoading ? null : _handleStartTest,
                      child: const Text(
                        'Test Understanding',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),

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
