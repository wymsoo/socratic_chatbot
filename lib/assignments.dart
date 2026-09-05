import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Simple models
class Question {
  final String id;
  final String lectureId;
  final String lectureTitle;
  final List<String> tags;
  final String prompt;
  final int published;

  Question.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        lectureId = j['lectureId'],
        lectureTitle = j['lectureTitle'],
        tags = List<String>.from(j['tags'] ?? []),
        prompt = j['prompt'] ?? '',
        published = j['published'] ?? 0;
}

class AssignmentModel {
  final String id;
  final String title;
  final String date;
  final int submitted;
  final int total;

  AssignmentModel.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        title = j['title'],
        date = j['date'],
        submitted = j['submitted'] ?? 0,
        total = j['total'] ?? 0;
}

class ApiService {
  final String baseUrl;
  ApiService({this.baseUrl = 'http://localhost:8000'});

  Future<List<Question>> fetchQuestions({String? lectureId, String? subtopics}) async {
    final uri = Uri.parse('$baseUrl/api/questions').replace(queryParameters: {
      if (lectureId != null) 'lectureId': lectureId,
      if (subtopics != null) 'subtopics': subtopics,
    });
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final data = json.decode(resp.body);
      final items = List.from(data['questions'] ?? []);
      return items.map((e) => Question.fromJson(e)).toList();
    }
    throw Exception('Failed to load questions');
  }

  Future<List<AssignmentModel>> fetchAssignments() async {
    final uri = Uri.parse('$baseUrl/api/assignments');
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final data = json.decode(resp.body);
      final items = List.from(data['assignments'] ?? []);
      return items.map((e) => AssignmentModel.fromJson(e)).toList();
    }
    throw Exception('Failed to load assignments');
  }

  Future<AssignmentModel> createAssignment(String title, List<String> questionIds) async {
    final uri = Uri.parse('$baseUrl/api/assignments');
    final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: json.encode({'title': title, 'questionIds': questionIds}));
    if (resp.statusCode == 200) {
      final data = json.decode(resp.body);
      return AssignmentModel.fromJson(data['assignment']);
    }
    throw Exception('Failed to create assignment');
  }
}

// Main page that toggles between Questions and Assignments
class AssignmentsPage extends StatefulWidget {
  const AssignmentsPage({super.key});

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  int activeTab = 0; // 0 questions, 1 assignments
  final ApiService api = ApiService();
  List<Question> questions = [];
  List<AssignmentModel> assignments = [];
  final Set<String> selected = {};
  bool loadingQuestions = false;
  bool loadingAssignments = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
    _loadAssignments();
  }

  Future<void> _loadQuestions({String? lectureId}) async {
    setState(() => loadingQuestions = true);
    try {
      final q = await api.fetchQuestions(lectureId: lectureId);
      setState(() => questions = q);
    } catch (e) {
      // ignore
    } finally {
      setState(() => loadingQuestions = false);
    }
  }

  Future<void> _loadAssignments() async {
    setState(() => loadingAssignments = true);
    try {
      final a = await api.fetchAssignments();
      setState(() => assignments = a);
    } catch (e) {
      // ignore
    } finally {
      setState(() => loadingAssignments = false);
    }
  }

  void _onCreateAssignment() async {
    final titleController = TextEditingController();
    final result = await showDialog<String?>(context: context, builder: (ctx) {
      return AlertDialog(
        title: const Text('Create Assignment'),
        content: TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(titleController.text), child: const Text('Create')),
        ],
      );
    });
    if (result != null && result.trim().isNotEmpty) {
      try {
        final a = await api.createAssignment(result.trim(), selected.toList());
        setState(() {
          assignments.insert(0, a);
          selected.clear();
          activeTab = 1; // switch to assignments view
        });
      } catch (e) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignments'),
        centerTitle: true,
        backgroundColor: const Color(0xFF2F4D8F),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          ToggleButtons(
            isSelected: [activeTab == 0, activeTab == 1],
            onPressed: (i) => setState(() => activeTab = i),
            borderRadius: BorderRadius.circular(24),
            children: const [Padding(padding: EdgeInsets.symmetric(horizontal:18, vertical:8), child: Text('Questions')), Padding(padding: EdgeInsets.symmetric(horizontal:18, vertical:8), child: Text('Assignments'))],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: activeTab == 0 ? _questionsView() : _assignmentsView(),
          ),
        ],
      ),
      floatingActionButton: selected.isNotEmpty ? FloatingActionButton.extended(onPressed: _onCreateAssignment, label: Text('Create Assignment (${selected.length})')) : null,
    );
  }

  Widget _questionsView() {
    if (loadingQuestions) return const Center(child: CircularProgressIndicator());

    // Group by lectureTitle
    final Map<String, List<Question>> groups = {};
    for (var q in questions) groups.putIfAbsent(q.lectureTitle, () => []).add(q);

    return RefreshIndicator(
      onRefresh: _loadQuestions,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(items: const [DropdownMenuItem(value: null, child: Text('Filter by lecture...'))], onChanged: (v) {}, hint: const Text('Filter by lecture...'))),
            const SizedBox(width:8),
            ElevatedButton(onPressed: () => setState(() => selected.clear()), child: const Text('Cancel Select'))
          ]),
          const SizedBox(height:12),
          for (var entry in groups.entries) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)), TextButton(onPressed: () async { // navigate to bank
              await Navigator.push(context, MaterialPageRoute(builder: (_) => QuestionBankScreen(lectureTitle: entry.key, lectureId: entry.value.first.lectureId, selected: selected)));
              setState(() {});
            }, child: const Text('View More'))]),
            const SizedBox(height:8),
            for (var q in entry.value) _questionCard(q),
            const SizedBox(height:18),
          ]
        ],
      ),
    );
  }

  Widget _questionCard(Question q) {
    final selectedFlag = selected.contains(q.id);
    return Card(
      margin: const EdgeInsets.symmetric(vertical:8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        title: Wrap(spacing:8, children: q.tags.map((t) => Chip(label: Text(t))).toList()),
        subtitle: Padding(padding: const EdgeInsets.only(top:8.0), child: Text(q.prompt, maxLines: 3, overflow: TextOverflow.ellipsis)),
        trailing: IconButton(icon: Icon(selectedFlag ? Icons.check_circle : Icons.radio_button_unchecked, color: selectedFlag ? Colors.green : Colors.grey), onPressed: () => setState(() => selectedFlag ? selected.remove(q.id) : selected.add(q.id))),
        onTap: () => showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Question'), content: Text(q.prompt), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))])),
      ),
    );
  }

  Widget _assignmentsView() {
    if (loadingAssignments) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadAssignments,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        for (var a in assignments) Card(margin: const EdgeInsets.symmetric(vertical:8), child: ListTile(title: Text(a.title), subtitle: Text('${a.date}\nSubmitted: ${a.submitted}/${a.total}'))),
        const SizedBox(height:12),
        GestureDetector(
          onTap: () => setState(() => activeTab = 0),
          child: DottedBorderPlaceholder(),
        )
      ]),
    );
  }
}

class DottedBorderPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(style: BorderStyle.solid, color: Colors.grey.shade400)),
      child: Center(child: Text('Select Questions to create new Assignment', style: TextStyle(color: Colors.grey.shade700))),
    );
  }
}

// Question Bank Screen
class QuestionBankScreen extends StatefulWidget {
  final String lectureId;
  final String lectureTitle;
  final Set<String> selected;
  const QuestionBankScreen({required this.lectureId, required this.lectureTitle, required this.selected, super.key});

  @override
  State<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends State<QuestionBankScreen> {
  final ApiService api = ApiService();
  List<Question> questions = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final q = await api.fetchQuestions(lectureId: widget.lectureId);
      setState(() => questions = q);
    } catch (e) {}
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Bank'),
        leading: BackButton(onPressed: () => Navigator.pop(context)),
      ),
      body: loading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: questions.length,
        itemBuilder: (ctx, i) {
          final q = questions[i];
          final sel = widget.selected.contains(q.id);
          return Card(
            margin: const EdgeInsets.symmetric(vertical:8),
            child: ListTile(
              title: Wrap(spacing:8, children: q.tags.map((t) => Chip(label: Text(t))).toList()),
              subtitle: Text(q.prompt, maxLines: 3, overflow: TextOverflow.ellipsis),
              trailing: IconButton(icon: Icon(sel ? Icons.check_circle : Icons.radio_button_unchecked, color: sel ? Colors.green : Colors.grey), onPressed: () => setState(() { if (sel) widget.selected.remove(q.id); else widget.selected.add(q.id); })),
              onTap: () => showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Question'), content: Text(q.prompt), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))])),
            ),
          );
        },
      ),
      bottomNavigationBar: widget.selected.isNotEmpty ? BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(children: [
            Expanded(child: ElevatedButton(onPressed: () async { Navigator.pop(context); }, child: const Text('Add to Assignment'))),
            const SizedBox(width:12),
            ElevatedButton(onPressed: () async { Navigator.pop(context); }, child: const Text('Create Assignment'))
          ]),
        ),
      ) : null,
    );
  }
}
