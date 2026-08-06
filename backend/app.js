require("dotenv").config();
const express = require("express");
const os = require('os');
const app = express()
const process = require('process')
const path = require('path');

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

// Start server
const PORT = process.env.PORT || 8000;
app.listen(PORT, () => {
    console.log(`Server running at http://localhost:${PORT}`);
    console.log(`(Server Address on network: http://${server_addr}:${PORT})`);
});