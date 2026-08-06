require('dotenv').config();
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const { v4: uuidv4 } = require('uuid');
const MemoryUI = require('./gemini_mem').MemoryUI;

const PROMPT_TEMPLATES_DIR = path.join(__dirname, '..', 'prompt_templates');
const PROMPT_FILES = {
    extract_confusion: 'extract_confusion.txt',
    generate_question: 'generate_question.txt',
    chat: 'chat.txt',
    generate_3_questions: 'generate_3_questions.txt',
    grade_answer: 'grade_answer.txt',
    final_summary: 'final_summary.txt',
    default_rules: 'default_rules.txt',
    summarize_and_plan: 'summarize_and_plan.txt',
};

const promptCache = {};
function loadPrompt(name) {
    if (!PROMPT_FILES[name]) throw new Error('Unknown prompt: ' + name);
    if (!promptCache[name]) {
        const p = path.join(PROMPT_TEMPLATES_DIR, PROMPT_FILES[name]);
        promptCache[name] = fs.readFileSync(p, { encoding: 'utf8' });
    }
    return promptCache[name];
}

function formatPrompt(template, vars) {
    return template.replace(/\$\{?(\w+)\}?/g, (_, k) => vars[k] || '');
}

const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY || '';
const DEEPSEEK_URL = 'https://api.deepseek.com/chat/completions';

async function askDeepseek(systemPrompt, userInput, defaultRules = '') {
    try {
        const payload = {
            messages: [
                { content: systemPrompt + '\n' + defaultRules, role: 'system' },
                { content: userInput, role: 'user' },
            ],
            model: 'deepseek-v4-flash',
            thinking: { type: 'disabled' },
            response_format: { type: 'json_object' },
            reasoning_effort: 'high',
            max_tokens: 4096,
            temperature: 0.3,
            top_p: 1,
            stream: false,
        };

        const headers = {
            'Content-Type': 'application/json',
            Accept: 'application/json',
            Authorization: `Bearer ${DEEPSEEK_API_KEY}`,
        };

        const r = await axios.post(DEEPSEEK_URL, payload, { headers });
        const content = r.data?.choices?.[0]?.message?.content;
        if (!content) return {};
        return JSON.parse(content);
    } catch (e) {
        console.error('askDeepseek error', e?.message || e);
        return {};
    }
}

// Initialize memories similar to server.py
const mem_chat_hist = new MemoryUI('chat_history_agent', 'default_user');
mem_chat_hist.run && mem_chat_hist.run();
const user_pref = new MemoryUI('user_pref_agent', 'default_user');
user_pref.run && user_pref.run();
const mem_transcript = new MemoryUI('transcript_agent', 'default_user');
mem_transcript.run && mem_transcript.run();

// In-memory sessions store
const sessions = {};

exports.getQuiz = async (req, res) => {
    try {
        const jsonPath = path.join(__dirname, '..', 'ragdata', 'quiz_questions.json');
        const data = JSON.parse(fs.readFileSync(jsonPath, { encoding: 'utf8' }));
        res.json(data);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};

exports.submitQuiz = async (req, res) => {
    console.log('Received quiz responses:', req.body);
    res.json({ status: 'success', message: 'Quiz submitted successfully!' });
};

exports.getConfusionData = async (req, res) => {
    const csvPath = path.join(__dirname, '..', 'data.csv');
    try {
        const csv = fs.readFileSync(csvPath, { encoding: 'utf8' });
        const lines = csv.split(/\r?\n/).filter(Boolean);
        const headers = lines[0].split(',').map(h => h.trim());
        const rows = lines.slice(1).map(l => {
            const vals = l.split(',');
            const obj = {};
            headers.forEach((h, i) => (obj[h] = vals[i]));
            return obj;
        });

        const timeBuckets = {};
        const studentCounts = {};
        const edgeWeights = {};
        const nodes = new Set();

        rows.forEach(row => {
            if (row.timestamp) {
                const ts = parseInt(row.timestamp, 10);
                const bucket = Math.floor(ts / 600000) * 600000;
                timeBuckets[bucket] = (timeBuckets[bucket] || 0) + 1;
            }
            const student = row.student_id;
            if (student) studentCounts[student] = (studentCounts[student] || 0) + 1;
            const words = [row.keyword1, row.keyword2, row.keyword3].filter(Boolean).map(w => w.trim()).filter(Boolean);
            words.forEach(w => nodes.add(w));
            for (let i = 0; i < words.length; i++) {
                for (let j = i + 1; j < words.length; j++) {
                    const pair = [words[i], words[j]].sort().join('||');
                    edgeWeights[pair] = (edgeWeights[pair] || 0) + 1;
                }
            }
        });

        const timeSeries = Object.keys(timeBuckets).sort().map(k => ({ time: parseInt(k, 10), count: timeBuckets[k] }));
        const edges = Object.entries(edgeWeights).map(([k, w]) => {
            const [a, b] = k.split('||');
            return { source: a, target: b, weight: w };
        });
        const students = Object.entries(studentCounts).map(([s, c]) => ({ student: s, count: c }));

        res.json({ timeSeries, nodes: Array.from(nodes), edges, students });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};

function getPrompt(promptName, vars = {}) {
    const template = loadPrompt(promptName);
    return formatPrompt(template, vars);
}

exports.initialize = async (req, res) => {
    try {
        const lecture_snippet = req.body.lecture_snippet || '';
        const confusion_data = await askDeepseek(loadPrompt('extract_confusion'), lecture_snippet, '');
        const statements = confusion_data.confusing_statements || [];
        const summary = confusion_data.summary || 'No Summary was extracted';
        const session_id = uuidv4();
        sessions[session_id] = {
            original_concept: '',
            lecture_snippet,
            learning_outcomes: {},
            session_history: [],
            node_queue: [],
            status: 'awaiting_concept_selection',
            test_history: [],
            current_question: '',
        };
        res.json({ session_id, confusing_statements: statements, summary });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};

exports.selectConcept = async (req, res) => {
    try {
        const { session_id, selected_concepts } = req.body;
        if (!sessions[session_id]) return res.status(404).json({ error: 'Session not found' });
        const session = sessions[session_id];
        session.original_concept = (selected_concepts || []).join(', ');
        session.status = 'tutoring';
        const plan_resp = await (async () => {
            const sys = loadPrompt('summarize_and_plan');
            const user_input = `STUDENT'S CONFUSED CANDIDATE CONCEPTS:\n${selected_concepts}\n`;
            return await askDeepseek(sys, user_input, '');
        })();
        const lo = plan_resp.learning_outcomes || [];
        lo.forEach((l, i) => {
            session.learning_outcomes[`learning_outcome_${i}`] = { topic: l.topic || '', summary: l.summary || '', outcome: l.outcome || '', resolved: !!l.resolved };
        });
        const tutor_intro = plan_resp.overview || '';
        const first_q = plan_resp.first_question || '';
        session.node_queue.push(first_q);
        session.current_question = first_q;
        res.json({ tutor_response: first_q, overview: tutor_intro, status: session.status });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};

function unresolvedLearningOutcomes(session) {
    return Object.entries(session.learning_outcomes || {}).filter(([k, v]) => !v.resolved).map(([k, v]) => ({ key: k, ...v }));
}

function allOutcomesResolved(session) {
    const lo = session.learning_outcomes || {};
    const keys = Object.keys(lo);
    return keys.length > 0 && keys.every(k => !!lo[k].resolved);
}

exports.handleChat = async (req, res) => {
    try {
        const { session_id, message } = req.body;
        if (!sessions[session_id]) return res.status(404).json({ error: 'Session missing' });
        const session = sessions[session_id];
        const student_input = (message || '').trim();

        let current_question = session.current_question || (session.node_queue && session.node_queue.slice(-1)[0]) || '';

        const history_lines = (session.session_history || []).slice(-8).map(m => `${m.user === 'tutor' ? 'Tutor' : 'Student'}: ${m.text}`);
        const history_str = history_lines.length ? history_lines.join('\n') : 'No previous history yet. This is the first turn.';

        // Fetch memories
        const raw_transcript = await (mem_transcript.searchMemories ? mem_transcript.searchMemories(student_input) : []);
        const raw_pref = "User is a secondary school student who enjoy gaming and rock climbing."
        const transcript_info = Array.isArray(raw_transcript) ? raw_transcript.map(m => m.memory || m) : [];
        const user_prefs = [];
        if (Array.isArray(raw_pref)) raw_pref.forEach(m => { if (m && m.memory) user_prefs.push(m.memory); else if (typeof m === 'string') user_prefs.push(m); });

        let memory_context = '';
        if (transcript_info.length || user_prefs.length) {
            memory_context = '--- STUDENT PERSONALITY & RELEVANT MEMORIES ---\n';
            if (user_prefs.length) memory_context += 'Student Preferences/Personality Profile:\n- ' + user_prefs.join('\n- ') + '\n';
            if (transcript_info.length) memory_context += 'Lecture Transcript Details:\n- ' + transcript_info.join('\n- ') + '\n';
            memory_context += '---------------------------------------------\n\n';
        }
        console.log("SESSION", session.learning_outcomes)
        const handler_payload = `${memory_context}Question Asked Previously: ${current_question}\nStudent Said: ${student_input}`;
        console.log("Handler payload", handler_payload)
        const unresolved = unresolvedLearningOutcomes(session);
        if (unresolved.length === 0) {
            session.status = 'testing_prompt';
            session.pending_test = true;
            return res.json({ tutor_response: 'Great work! You have resolved all current learning outcomes. Would you like to start the 3-question quiz to earn StashStars?', status: session.status, test_prompt: true, test_instructions: 'The tutor recommends a short 3-question assessment to check understanding.', transcript_info, user_preferences: user_prefs });
        }

        const ai_output = await askDeepseek(loadPrompt('chat'), handler_payload, '');
        console.log("AI OUTPUT", ai_output)

        const tutor_reply = ai_output.response || ai_output;
        const next_question = (tutor_reply && tutor_reply.question) || '';

        session.session_history.push({ timestamp: Date.now(), user: 'tutor', text: current_question });
        session.session_history.push({ timestamp: Date.now(), user: 'student', text: student_input });
        session.current_question = next_question;

        const updated_outcomes = ai_output.learning_outcomes || {};
        Object.keys(updated_outcomes).forEach(k => {
            if (session.learning_outcomes[k]) {
                session.learning_outcomes[k].resolved = session.learning_outcomes[k].resolved || !!updated_outcomes[k].resolved;
            }
        });
        console.log("LEARNING OUTCOMES", session.learning_outcomes)

        // store turn in memory
        try { await mem_chat_hist.addMemory && mem_chat_hist.addMemory([{ role: 'user', content: `[Student stated]: ${student_input}` }, { role: 'assistant', content: `[AI Tutor explained]: ${JSON.stringify(tutor_reply)}` }]); } catch (e) { /* ignore */ }

        if (allOutcomesResolved(session) || ai_output.session_complete) {
            session.status = 'testing_prompt';
            session.pending_test = true;
            return res.json({ tutor_response: tutor_reply, status: session.status, test_prompt: true, test_instructions: 'The tutor recommends a short 3-question assessment to check understanding.', transcript_info, user_preferences: user_prefs });
        }

        res.json({ tutor_response: tutor_reply, status: 'tutoring' });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};

exports.startTest = async (req, res) => {
    try {
        const { session_id } = req.body;
        if (!sessions[session_id]) return res.status(404).json({ error: 'Session not found' });
        const session = sessions[session_id];
        const history_str = (session.session_history || []).map(h => JSON.stringify(h.text)).join(' ');
        const gen_input = `Original Concept: ${session.original_concept}\nSession History: ${history_str}`;
        const questions_resp = await askDeepseek(loadPrompt('generate_3_questions'), gen_input, '');
        const questions = questions_resp.questions || [];
        if (!questions.length) return res.status(500).json({ error: 'Failed to generate test questions' });
        session.test_queue = questions;
        session.test_history = [];
        session.test_index = 0;
        session.status = 'in_test';
        session.pending_test = false;
        const first_q = questions[0];
        const question_text = typeof first_q === 'object' ? first_q.question : String(first_q);
        res.json({ tutor_response: first_q, raw_question: question_text, status: session.status, question_index: 1, total_questions: questions.length });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};

exports.submitAnswer = async (req, res) => {
    try {
        const { session_id, answer } = req.body;
        if (!sessions[session_id]) return res.status(404).json({ error: 'Session not found' });
        const session = sessions[session_id];
        const queue = session.test_queue || [];
        const idx = session.test_index || 0;
        if (!Array.isArray(queue) || idx >= queue.length) return res.status(400).json({ error: 'No active test question' });
        const current = queue[idx];
        let correct = false;
        let explanation = '';
        let canonical_answer_text = '';

        if (current && current.choices) {
            const raw_choices = current.choices.map(c => (typeof c === 'object' && c.text) ? c.text : String(c));
            let correct_index = current.answer_index;
            if (correct_index == null) {
                for (let i = 0; i < current.choices.length; i++) {
                    const c = current.choices[i];
                    if (typeof c === 'object' && c.correct) { correct_index = i; break; }
                }
            }
            if (correct_index != null && correct_index >= 0 && correct_index < raw_choices.length) canonical_answer_text = raw_choices[correct_index];
            let student_choice_index = null;
            const sval = String(answer).trim();
            if (/^\d+$/.test(sval)) {
                const iv = parseInt(sval, 10);
                if (1 <= iv && iv <= raw_choices.length) student_choice_index = iv - 1;
                else if (0 <= iv && iv < raw_choices.length) student_choice_index = iv;
            } else {
                const idxOf = raw_choices.indexOf(sval);
                if (idxOf >= 0) student_choice_index = idxOf;
            }
            if (student_choice_index != null && correct_index != null) correct = (student_choice_index === correct_index);
            explanation = current.explanation || '';
        } else {
            canonical_answer_text = current.answer || '';
            const grade_input = `Question: ${current.question || ''}\nCanonical Answer: ${canonical_answer_text}\nStudent Answer: ${answer}`;
            const grade_resp = await askDeepseek(loadPrompt('grade_answer'), grade_input, '');
            correct = !!(grade_resp.correct);
            explanation = grade_resp.explanation || '';
        }

        session.test_history = session.test_history || [];
        session.test_history.push({ question: current.question || '', student_response: answer, correct_answer: canonical_answer_text, correct, explanation });
        session.test_index = idx + 1;

        if (session.test_index < (queue || []).length) {
            const raw_next = queue[session.test_index];
            const next_q_text = typeof raw_next === 'object' ? raw_next.question : String(raw_next);
            return res.json({ tutor_response: explanation, next_question: raw_next, raw_question: next_q_text, question_index: session.test_index + 1, total_questions: queue.length, status: 'in_test' });
        }

        // Test complete
        const stash_stars = (session.test_history || []).filter(i => i.correct).length;
        const summary_input = `Original Concept: ${session.original_concept}\nTest History (Session Data): ${JSON.stringify(session.test_history)}`;
        const final_summary = await askDeepseek(loadPrompt('final_summary'), summary_input, '');
        const summary_text = final_summary.summary || 'Great job today!';
        const competency = final_summary.competency_notes || '';
        const report_content = final_summary.report_content || 'Detailed performance report is unavailable.';
        session.status = 'awaiting_continuation';
        res.json({ tutor_response: explanation, final_summary: summary_text, competency_notes: competency, report_content, stash_stars, status: session.status });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
