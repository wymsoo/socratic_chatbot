const fs = require('fs/promises');
const path = require('path');
const gemini_mem_controller = require('./gemini_mem');
const { RagStore } = require('./rag_store');
const mongoose = require('mongoose');
const json_path = `../ragdata/syllabus_rag/dse_questions_sample.json`
const dotenv = require("dotenv");

const memory_ui = new gemini_mem_controller.MemoryUI('chat_history_agent', 'default_user');
const ragStore = new RagStore('dse_questions');

const SEC_QUESTION_PROMPT = 
`
You are an expert Hong Kong secondary school instructor. Analyze the provided lecture transcript and complete the following tasks:

Tasks:
1. Identify the core, high-leverage concept or framework from the transcript that students often struggle to apply.
2. Use the given example question as reference and ask a question of similar level and style.

Question & Option Rules:
- Generate exactly 4 options (1 correct answer, 3 highly plausible distractors targeting common student misconceptions).
- Distractors must be theoretically grounded—not obviously wrong or superficial.
- Provide a clear, pedagogical explanation for why the correct option is right and why the distractors fail.

JSON Schema:
{
  "question": "The scenario question text",
  "answers": [
    { "text": "Option A text", "isCorrect": true },
    { "text": "Option B text", "isCorrect": false },
    { "text": "Option C text", "isCorrect": false },
    { "text": "Option D text", "isCorrect": false }
  ],
  "correct_explanation": "Detailed explanation of why the correct framework applies to Company A",
  "topics": ["Name of primary topic or framework"]
}

`


const QUESTION_PROMPT =
`You are an expert university instructor. Analyze the provided lecture transcript and complete the following tasks:

Tasks:
1. Identify the core, high-leverage concept or framework from the transcript that students often struggle to apply.
2. Select the most fitting scenario style for this specific topic:
   - Diagnostic Dilemma (Isolating root causes/mechanisms)
   - Strategic Trade-Off (Evaluating competing constraints)
   - Counterfactual Challenge (Testing theoretical boundaries under changed conditions)
   - Data Interpretation (Resolving conflicting evidence or anomalies)
   - Comparative Strategy (Applying models across distinct contexts/entities)
3. Draft a realistic, context-rich scenario testing this concept.

Question & Option Rules:
- The question MUST present a realistic problem scenario rather than testing simple definition recall.
- Generate exactly 4 options (1 correct answer, 3 highly plausible distractors targeting common student misconceptions).
- Distractors must be theoretically grounded—not obviously wrong or superficial.
- Provide a clear, pedagogical explanation for why the correct option is right and why the distractors fail.

JSON Schema:
{
  "question": "The scenario question text",
  "answers": [
    { "text": "Option A text", "isCorrect": true },
    { "text": "Option B text", "isCorrect": false },
    { "text": "Option C text", "isCorrect": false },
    { "text": "Option D text", "isCorrect": false }
  ],
  "correct_explanation": "Detailed explanation of why the correct framework applies to Company A",
  "topics": ["Name of primary topic or framework"]
}
`


async function askGeminiFlashSummary(prompt, content, model) {
    try {
        console.log(process.env.AIML_API_KEY)
        const response = await fetch('https://api.aimlapi.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${process.env.AIML_API_KEY}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                model: model,
                messages: [
                    {
                        content: prompt,
                        role: "system"
                    },
                    {
                        role: 'user',
                        content: content
                    },
                ],
                temperature: 0.3,
                response_format: {
                    "type": "json_object"
                }
            }),
        });

        const data = await response.json();
        let obj;
        try {
            obj = JSON.parse(data.choices[0].message.content);
        } catch (err) {
            console.error(data)
            obj = {
                message: data.choices[0].message.content,
            };
        }
        return obj;
    } catch (error) {
        console.error("Error:", error);
        throw error;
    }
}

// async function addQuestionsToMemoryFromJson(jsonRelativePath, clearExisting = false) {
//     // Delegate to RagStore which handles embeddings + Chroma collection writes
//     if (!ragStore.collection) {
//         await ragStore.init();
//     }
//     const res = await ragStore.addDocumentsFromJson(jsonRelativePath, clearExisting);
//     return res;
// }

function formatMemoryResultsForPrompt(results, topK = 1) {
    if (!Array.isArray(results) || results.length === 0) {
        return '';
    }

    const sorted = [...results].sort((a, b) => (b.score ?? 0) - (a.score ?? 0));
    const selected = sorted.slice(0, topK);

    return selected
        .map((item, idx) => {
            const memoryText = item.memory || item.content || item.message || JSON.stringify(item, null, 2);
            const scoreText = item.score != null ? `score=${item.score}` : 'score=n/a';
            return `=== Relevant chunk ${idx + 1} (${scoreText}) ===\n${memoryText}`;
        })
        .join('\n\n');
}

async function getRelevantQuestionContext(query, topK = 2) {
    if (!ragStore.collection) {
        await ragStore.init();
    }
    const resp = await ragStore.query(query, topK);
    console.log("QUERY RESP", resp);

    const normalized = [];
    const docs = resp.documents || [];
    const distances = resp.distances || [];

    try {
        for (let i = 0; i < docs.length; i++) {
            const doc = docs[i];

            // Safely format options whether it's an Object, Array, or String
            let optionsStr = '';
            if (doc.options) {
                if (Array.isArray(doc.options)) {
                    optionsStr = doc.options.join(', ');
                } else if (typeof doc.options === 'object') {
                    optionsStr = Object.entries(doc.options)
                        .map(([k, v]) => `${k}: ${v}`)
                        .join(' | ');
                } else {
                    optionsStr = String(doc.options);
                }
            }

            // Safely format keywords
            const keywordsStr = Array.isArray(doc.keywords) 
                ? doc.keywords.join(', ') 
                : (doc.keywords || '');

            normalized.push({
                question: doc.question_text || doc.text || '',
                options: optionsStr,
                keywords: keywordsStr,
                score: distances[i] ?? 'N/A'
            });
        }

        const rel_q = normalized.map((obj) => {
            return `Question: ${obj.question}\nOptions: ${obj.options}\nKeywords: ${obj.keywords}\nScore: ${obj.score}`;
        });

        return rel_q;

    } catch (e) {
        console.warn('Unexpected RAG query response format, falling back to raw response:', e);
        return formatMemoryResultsForPrompt(resp, topK);
    }
}

async function generateQuestions(transcript, relevantContext = ''){
    let model = 'google/gemini-2.5-flash';
    const prompt = `${SEC_QUESTION_PROMPT}\n\nReference the questioning style provided:\n${relevantContext}`;
    console.log("PROMPT",prompt)
    const questions = await askGeminiFlashSummary(prompt, transcript, model );
    console.log(questions);
    return questions;
}

async function generateAssignment() {
    // replace with 5 minute snippets in product
    const batch = `
    Wow. Goldman Sachs originally, but not today. Yeah, they went into retail banking. They failed miserably at it, but a large part of the revenue of Goldman Sachs nowadays is asset management. All of them. They're both. You're correct. Did I give you the thing? I think I did. Read it. So
    If you were to take a look at the annual report of any of these, put them side by side and black out the names, you couldn't tell the difference. Morgan Stanley, the DNA is investment banking, but they make most of their money in asset management. Citibank, HSBC, JP Morgan, UBS, RGBS
    BNP, the DNA is commercial banking but they now do investment banking very successfully. In fact, BNP Paribas, BNP was a commercial bank, Paribas was the investment bank, and they merged together. Okay? So that's why you need to understand the difference between what a business is and what the institution does. Okay? So-
    All of these institutions, I mean, UBS, mo-most of the money they make is private banking, and yet they are known as an investment bank. Okay? So it's kind of challenging because they may have started with a particular type of DNA, but now they are huge institutions. Now, the legal framework
    For organizing banking and securities firms is three basic models. One model is legal separation. So we separate banking from the securities business. So that was the regime under Glass-Steagall Act, that was the regime in Japan, legal separation. The second model is the financial supermarket, which is-
    Regime in the US right now after Gramleach-Bliley Act nineteen ninety-nine. So you have a holding company, which can be a bank holding company regulated by the Fed or a financial holding company regulated by the SEC. And under that, you have different legal entities with different business lines. So you have a commercial bank, an invest-- uh, an investment bank, a
    Broker-dealer, an asset management firm, et cetera, et cetera. The third model is universal banking. This is what you find in continental Europe. All the different financial services under one umbrella. Typical example, Deutsche Bank. Deutsche Bank have many different financial services all under the same legal entity
    Okay, so three different models. All right. So we've talked about the difference between investment banks and securities firms, security broker-dealers. We understand now that the core of investment banking is corporate finance. We've compared and contrast commercial and investment banking. We've talked about, again-

    `
    const relevantQuestions = await getRelevantQuestionContext(batch, 2);
    const questions = await generateQuestions(batch, relevantQuestions);
    return questions;
}


async function main() {
    dburi = process.env.MONGODB_URI
    dotenv.config();

    try {
        await mongoose.connect(dburi);
        const lectureSummaries = await generateAssignment();

        await mongoose.disconnect()

    } catch (error) {
        console.error('Database connection error:', error);
        await mongoose.disconnect();
        process.exit(1);
    }
}

main().catch(err => console.log(err));