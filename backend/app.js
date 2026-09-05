const express = require("express");
const os = require('os');
const app = express()
const process = require('process')
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

// Function to get the server's IP address
function getServerIp() {
    const networkInterfaces = os.networkInterfaces();
    for (const interfaceName in networkInterfaces) {
        for (const iface of networkInterfaces[interfaceName]) {
            if (iface.family === 'IPv4' && !iface.internal) return iface.address;
        }
    }
    return '127.0.0.1';
}

const server_addr = getServerIp();

const gemini_mem_controller = require('./controllers/gemini_mem');
const chat_controller = require('./controllers/chat');

app.use(express.json());

const memory_ui = new gemini_mem_controller.MemoryUI('chat_history_agent', 'default_user');

// Memory handling routes
app.post('/memory', async (req, res) => {
    try {
        const payload = typeof req.body === 'string' ? req.body : req.body?.message || req.body?.memory || req.body?.messages || req.body;
        const result = await memory_ui.addMemory(payload);
        res.json({ success: true, result });
    } catch (e) {
        res.status(400).json({ error: e.message });
    }
});


app.get('/memory/search', async (req, res) => {
    try {
        const query = req.query.q || req.query.query || req.body?.message || req.body?.query;
        const results = await memory_ui.searchMemories(query);
        res.json({ success: true, results });
    } catch (e) {
        res.status(400).json({ error: e.message });
    }
});


// Chat-related routes mapped to chat controller
app.get('/api/quiz', chat_controller.getQuiz);
app.post('/api/quiz/submit', chat_controller.submitQuiz);
app.get('/api/confusion-data', chat_controller.getConfusionData);
app.post('/initialize', chat_controller.initialize);
app.post('/select_concept', chat_controller.selectConcept);
app.post('/chat', chat_controller.handleChat);
app.post('/start_test', chat_controller.startTest);
app.post('/submit_answer', chat_controller.submitAnswer);

// --- In-memory sample data for questions and assignments (simple mock) ---
const fs = require('fs');
let sampleQuestions = [];
try {
    const seedPath = path.join(__dirname, 'questions_seed.json');
    const raw = fs.readFileSync(seedPath, 'utf8');
    const seed = JSON.parse(raw);
    if (Array.isArray(seed)) {
        sampleQuestions = seed.map((item, idx) => ({
            id: item._id || item.id || `q${idx+1}`,
            lectureId: item.lecture || `lec${idx+1}`,
            lectureTitle: item.lectureTitle || (item.topics && item.topics.length ? `Lecture: ${item.topics[0]}` : `Lecture ${idx+1}`),
            tags: item.topics || [],
            prompt: item.question || '',
            published: (typeof item.published === 'boolean') ? (item.published ? 1 : 0) : (typeof item.published === 'number' ? item.published : 0),
            raw: item
        }));
    }
} catch (e) {
    console.warn('Could not load questions_seed.json, falling back to empty questions:', e.message);
    sampleQuestions = [];
}

let sampleAssignments = [
    {
        id: 'a1',
        title: 'Assignment 1',
        date: '02-22-26',
        submitted: 28,
        total: 32,
        questionIds: ['q1','q2']
    }
];

// GET /api/questions
app.get('/api/questions', (req, res) => {
    try {
        const lectureId = req.query.lectureId;
        const subtopics = req.query.subtopics; // comma-separated or single

        let results = sampleQuestions.slice();
        if (lectureId) results = results.filter(q => q.lectureId === lectureId);
        if (subtopics) {
            const subs = Array.isArray(subtopics) ? subtopics : String(subtopics).split(',').map(s=>s.trim()).filter(Boolean);
            results = results.filter(q => q.tags.some(t => subs.includes(t)));
        }

        res.json({ success: true, questions: results });
    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});

// GET /api/assignments
app.get('/api/assignments', (req, res) => {
    try {
        res.json({ success: true, assignments: sampleAssignments });
    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});

// POST /api/assignments
app.post('/api/assignments', (req, res) => {
    try {
        const { title, questionIds } = req.body;
        if (!title || !Array.isArray(questionIds) || questionIds.length === 0) {
            return res.status(400).json({ success: false, error: 'Missing title or questionIds' });
        }
        const id = `a${Date.now()}`;
        const date = new Date().toLocaleDateString('en-CA').replace(/-/g,'-');
        const newAssignment = {
            id,
            title,
            date,
            submitted: 0,
            total: questionIds.length,
            questionIds,
        };
        sampleAssignments.unshift(newAssignment);
        res.json({ success: true, assignment: newAssignment });
    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});

// Start server
const PORT = process.env.PORT || 8000;
app.listen(PORT, () => {
    console.log(`Server running at http://localhost:${PORT}`);
    console.log(`(Server Address on network: http://${server_addr}:${PORT})`);
});