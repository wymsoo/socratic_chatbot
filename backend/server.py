import json
import requests
import uuid
from pathlib import Path
from string import Template
from typing import List, Optional, Dict, Any
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
import datetime
import os
from dotenv import load_dotenv
from memory_ui import MemoryUI

# Additional built-in imports for data processing
import csv
from collections import Counter
from itertools import combinations

# Initialize single memory clients
mem_chat_hist = MemoryUI(user_id="default_user", agent_id="chat_history_agent")
mem_chat_hist.run()
user_pref = MemoryUI(user_id="default_user", agent_id="user_pref_agent")
user_pref.run()
mem_transcript = MemoryUI(user_id="default_user", agent_id="transcript_agent")
mem_transcript.run()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Pydantic Models for Output Validation (UNCHANGED FOR FRONTEND SAFETY) ---
class TimeSeriesPoint(BaseModel):
    time: int
    count: int

class Edge(BaseModel):
    source: str
    target: str
    weight: int

class StudentCount(BaseModel):
    student: str
    count: int

class ConfusionDataResponse(BaseModel):
    timeSeries: List[TimeSeriesPoint]
    nodes: List[str]
    edges: List[Edge]
    students: List[StudentCount]

@app.get("/api/confusion-data", response_model=ConfusionDataResponse)
def get_confusion_data():
    time_buckets = Counter()
    student_counts = Counter()
    edge_weights = Counter()
    nodes = set()

    try:
        with open('data.csv', mode='r', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            for row in reader:
                if row.get('timestamp'):
                    ts = int(row['timestamp'])
                    bucket = (ts // 600000) * 600000
                    time_buckets[bucket] += 1

                student = row.get('student_id')
                if student:
                    student_counts[student] += 1

                words = [row.get('keyword1'), row.get('keyword2'), row.get('keyword3')]
                words = [w.strip() for w in words if w and w.strip()]
                
                for w in words:
                    nodes.add(w)

                for pair in combinations(words, 2):
                    sorted_pair = tuple(sorted(pair))
                    edge_weights[sorted_pair] += 1

    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="data.csv not found")

    time_series_data = [{"time": t, "count": c} for t, c in sorted(time_buckets.items())]
    network_edges = [{"source": p[0], "target": p[1], "weight": w} for p, w in edge_weights.most_common()]
    student_data = [{"student": s, "count": c} for s, c in student_counts.most_common()]

    return {
        "timeSeries": time_series_data,
        "nodes": list(nodes),
        "edges": network_edges,
        "students": student_data
    }

# API_KEY = os.environ.get("DEEPSEEK_API_KEY") 
API_KEY = "sk-d0007ec01ed74cd18a4eddbf8aed7e69"
URL = "https://api.deepseek.com/chat/completions"
LEVEL = "secondary school"

PROMPT_TEMPLATES_DIR = Path(__file__).resolve().parent / "prompt_templates"
PROMPT_FILES = {
    "extract_confusion": "extract_confusion.txt",
    "generate_question": "generate_question.txt",
    "chat": "chat.txt",
    "generate_3_questions": "generate_3_questions.txt",
    "grade_answer": "grade_answer.txt",
    "final_summary": "final_summary.txt",
    "default_rules":"default_rules.txt",
    "summarize_and_plan": "summarize_and_plan.txt"
}
_prompt_cache: Dict[str, str] = {}

def load_prompt_template(prompt_name: str) -> str:
    if prompt_name not in PROMPT_FILES:
        raise ValueError(f"Unknown prompt: {prompt_name}")
    if prompt_name not in _prompt_cache:
        path = PROMPT_TEMPLATES_DIR / PROMPT_FILES[prompt_name]
        _prompt_cache[prompt_name] = path.read_text(encoding="utf-8")
    return _prompt_cache[prompt_name]

def get_prompt(
    prompt_name: str,
    lecture_snippet: str = "",
    confused_topic: str = "",
    current_question: str = "",
    history: str = "",
    learning_outcomes: str = "",
    give_ans: str = ""
) -> str:
    template = load_prompt_template(prompt_name)
    return Template(template).safe_substitute(
        level=LEVEL,
        lecture_snippet=lecture_snippet,
        confused_topic=confused_topic,
        current_question=current_question,
        history=history,
        learning_outcomes=learning_outcomes,
        give_ans=give_ans
    )

class InitializePayload(BaseModel):
    lecture_snippet: str

class SelectConceptPayload(BaseModel):
    session_id: str
    selected_concepts: List[str]

class ChatTurnPayload(BaseModel):
    session_id: str
    message: str

class StartTestPayload(BaseModel):
    session_id: str

class SubmitAnswerPayload(BaseModel):
    session_id: str
    answer: str

def ask_deepseek(system_prompt: str, user_input: str, default_rules: str = "") -> Dict[str, Any]:
    payload = {
        "messages": [
            {"content": system_prompt + "\n" + default_rules, "role": "system"},
            {"content": user_input, "role": "user"}
        ],
        "model": "deepseek-v4-flash",
        "thinking": {"type": "disabled"},
        "response_format": {"type": "json_object"},
        "reasoning_effort": "high",
        "max_tokens": 4096,
        "temperature": 0.3,
        "top_p": 1,
        "stream": False
    }
    headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': f'Bearer {API_KEY}'
    }
    try:
        response = requests.post(URL, headers=headers, json=payload)
        response.raise_for_status()
        return json.loads(response.json()["choices"][0]["message"]["content"])
    except Exception as e:
        print(f"[System Error Calling AI: {e}]")
        return {}

sessions_db: Dict[str, Dict[str, Any]] = {}

@app.post("/initialize")
def initialize_session(payload: InitializePayload):
    confusion_data = ask_deepseek(get_prompt("extract_confusion"), payload.lecture_snippet, "")
    statements = confusion_data.get("confusing_statements", [])
    summary = confusion_data.get("summary", "No Summary was extracted")
    
    session_id = str(uuid.uuid4())
    sessions_db[session_id] = {
        "original_concept": "",
        "lecture_snippet": payload.lecture_snippet,
        "learning_outcomes": {},
        "session_history": [],
        "node_queue": [], 
        "status": "awaiting_concept_selection",
        "test_history": [],
        "current_question": ""
    }

    # mem_transcript.add_memory([{"role": "system", "content": f"Transcript to reference: {payload.lecture_snippet}"}])
    
    return {
        "session_id": session_id,
        "confusing_statements": statements,
        "summary": summary
    }

@app.post("/select_concept")
def select_concept(payload: SelectConceptPayload):
    if payload.session_id not in sessions_db:
        raise HTTPException(status_code=404, detail="Session expired or not found")

    session = sessions_db[payload.session_id]
    session["original_concept"] = ", ".join(payload.selected_concepts)
    session["status"] = "tutoring"

    plan_resp = summarize_and_plan(session, payload.selected_concepts)
    lo = plan_resp.get("learning_outcomes", [])
    
    for i, l in enumerate(lo):
        session["learning_outcomes"][f"learning_outcome_{i}"] = {
            "topic": l.get("topic", ""),
            "summary": l.get("summary", ""),
            "outcome": l.get("outcome", ""),
            # "strategy": l.get("strategy", ""),
            # "first_question": l.get("first_question", ""),
            "resolved": bool(l.get("resolved", False)),
        }

    tutor_intro = plan_resp.get("overview", "")
    first_q = plan_resp.get("first_question", "")
    session["node_queue"].append(first_q)
    session["current_question"] = first_q  # Store active current question

    return {
        "tutor_response": first_q,
        "overview": tutor_intro,
        "status": session["status"]
    }

def summarize_and_plan(session: Dict[str, Any], selected_concepts: List[str]) -> Dict[str, Any]:
    # Pull student preferences to tailor the roadmap and first question
    raw_pref_memories = user_pref.get_all_memories()
    user_prefs_str = ""
    if raw_pref_memories:
        user_prefs_str = "STUDENT PERSONALITY & PREFERENCES:\n" + json.dumps(raw_pref_memories)

    system_prompt = get_prompt('summarize_and_plan')
    user_input = (
        f"STUDENT'S CONFUSED CANDIDATE CONCEPTS:\n{selected_concepts}\n\n"
        f"{user_prefs_str}\n\n"
        f"EXECUTION TASK:\nAnalyze the inputs above, identify the missing link, and populate the requested JSON schema."
    )

    resp = ask_deepseek(system_prompt, user_input, "")
    if not isinstance(resp, dict):
        return {}
    return resp

def unresolved_learning_outcomes(session: Dict[str, Any]) -> List[Dict[str, Any]]:
    return [
        {"key": key, **details}
        for key, details in session.get("learning_outcomes", {}).items()
        if not details.get("resolved", False)
    ]

def all_outcomes_resolved(session: Dict[str, Any]) -> bool:
    return bool(session.get("learning_outcomes")) and all(
        details.get("resolved", False)
        for details in session.get("learning_outcomes", {}).values()
    )
# make sure the outputs that are resolved will remain resolved 
def merge_learning_outcome_updates(session: Dict[str, Any], updates: Any) -> None:
    if not isinstance(updates, dict):
        return
    for key, payload in updates.items():
        if key not in session.get("learning_outcomes", {}):
            continue
        if isinstance(payload, dict):
            resolved_value = payload.get("resolved")
            if isinstance(resolved_value, bool):
                session["learning_outcomes"][key]["resolved"] = (
                    session["learning_outcomes"][key].get("resolved", False)
                    or resolved_value
                )
            elif isinstance(resolved_value, str):
                session["learning_outcomes"][key]["resolved"] = (
                    session["learning_outcomes"][key].get("resolved", False)
                    or resolved_value.lower() == "resolved"
                )

def convert_to_mcq(question_text: str) -> Dict[str, Any]:
    system_prompt = (
        "Convert the provided question into a multiple-choice question with 4 options.\n"
        "Output a JSON object with keys: 'question', 'choices' (array of 4 strings), 'answer_index' (0-based int), 'explanation' (brief)."
    )
    user_input = f"Question: {question_text}\n\nProvide MCQ JSON output."
    resp = ask_deepseek(system_prompt, user_input, "")
    if not isinstance(resp, dict):
        return {
            "question": question_text,
            "choices": ["A", "B", "C", "D"],
            "answer_index": 0,
            "explanation": "No explanation available."
        }
    return resp

@app.post("/chat")
def handle_chat_turn(payload: ChatTurnPayload):
    time_of_post = datetime.datetime.now()
    if payload.session_id not in sessions_db:
        raise HTTPException(status_code=404, detail="Session context timeline missing")

    session = sessions_db[payload.session_id]
    student_input = payload.message.strip()

    # FIX 1: Properly resolve current_question from session state instead of freezing on node_queue
    current_question = session.get("current_question")
    if not current_question and session.get("node_queue"):
        current_question = session["node_queue"][-1]

    # FIX 2: Tag history with Speaker roles (Tutor: / Student:) to eliminate loop ambiguities
    history_lines = []
    for msg in session.get("session_history", [])[-8:]:
        if isinstance(msg, dict) and "text" in msg:
            speaker = "Tutor" if msg.get("user") == "tutor" else "Student"
            history_lines.append(f"{speaker}: {msg['text']}")
    history_str = "\n".join(history_lines) if history_lines else "No previous history yet. This is the first turn."

    # FIX 3: Fetch full Student Preferences / Personality profiles from user_pref memory
    raw_transcript_memories = mem_transcript.search_memories(student_input)
    raw_pref_memories = user_pref.get_all_memories()
    search_pref_memories = user_pref.search_memories(student_input)
    
    transcript_info = [mem["memory"] for mem in raw_transcript_memories] if raw_transcript_memories else []
    
    user_prefs = []
    if isinstance(raw_pref_memories, list):
        for m in raw_pref_memories:
            if isinstance(m, dict) and "memory" in m:
                user_prefs.append(m["memory"])
            elif isinstance(m, str):
                user_prefs.append(m)
    if search_pref_memories:
        for m in search_pref_memories:
            if isinstance(m, dict) and "memory" in m and m["memory"] not in user_prefs:
                user_prefs.append(m["memory"])

    # Format context for system prompt
    memory_context = ""
    if transcript_info or user_prefs:
        memory_context = "--- STUDENT PERSONALITY & RELEVANT MEMORIES ---\n"
        if user_prefs:
            memory_context += "Student Preferences/Personality Profile:\n- " + "\n- ".join(user_prefs) + "\n"
        if transcript_info:
            memory_context += "Lecture Transcript Details:\n- " + "\n- ".join(transcript_info) + "\n"
        memory_context += "---------------------------------------------\n\n"

    handler_payload = f"{memory_context}Question Asked Previously: {current_question}\nStudent Said: {student_input}"

    unresolved_outcomes = unresolved_learning_outcomes(session)
    num_of_uro = len(unresolved_outcomes)
    num_of_hist = len(session.get('session_history', []))
    give_ans = False
    
    # if num_of_uro == 3 and num_of_hist >= 6:
    #     give_ans = True
    # elif num_of_uro == 2 and num_of_hist >= 12:
    #     give_ans = True
    # elif num_of_uro == 1 and num_of_hist >= 16:
    #     give_ans = True
    
    if not unresolved_outcomes:
        session["status"] = "testing_prompt"
        session["pending_test"] = True
        test_instruction = (
            "The tutor recommends a short 3-question assessment to check understanding. "
            "When you confirm, the quiz will start: you'll receive 3 questions of increasing difficulty. "
            "Each correct answer awards +1 StashStar. Click Confirm to begin."
        )
        return {
            "tutor_response": "Great work! You have resolved all current learning outcomes. Would you like to start the 3-question quiz to earn StashStars?",
            "status": session["status"],
            "test_prompt": True,
            "test_instructions": test_instruction,
            "transcript_info": [],
            "user_preferences": user_prefs
        }
        
    ai_output = ask_deepseek(
        get_prompt(
            "chat",
            lecture_snippet=session.get("lecture_snippet", ""),
            confused_topic=session.get("original_concept", ""),
            current_question=current_question,
            history=history_str,
            learning_outcomes=json.dumps(unresolved_outcomes, indent=2),
            give_ans=str(give_ans)
        ),
        handler_payload,
        ""
    )

    tutor_reply = ai_output.get("response", "")
    # mcq_data = ai_output.get("response")
    # print("MCQDATA:",mcq_data)
    # mcq = None
    # if isinstance(mcq_data, dict):
    #     raw_choices = mcq_data.get("choices")
    #     if isinstance(raw_choices, list):
    #         mcq = {
    #             "question": str(mcq_data.get("question", "") or ""),
    #             "choices": [str(choice) for choice in raw_choices],
    #             "allow_custom_answer": bool(mcq_data.get("allow_custom_answer", True)),
    #         }

    next_question = tutor_reply["question"]

    # Record history
    session["session_history"].append({
        "timestamp": time_of_post,
        "user": "tutor",
        "text": current_question,
    })
    session["session_history"].append({
        "timestamp": datetime.datetime.now(),
        "user": "student",
        "text": student_input,
    })

    # FIX 4: Update session current question so the next turn moves forward
    session["current_question"] = next_question

    updated_outcomes = ai_output.get("learning_outcomes")
    merge_learning_outcome_updates(session, updated_outcomes)
    print("Learning Outcomes:", session.get("learning_outcomes"))

    # Store turn into memory
    chat_interaction = [
        {"role": "user", "content": f"[Student stated]: {student_input}"},
        {"role": "assistant", "content": f"[AI Tutor explained]: {tutor_reply}"}
    ]
    # mem_chat_hist.add_memory(chat_interaction)

    if all_outcomes_resolved(session) or ai_output.get("session_complete"):
        session["status"] = "testing_prompt"
        session["pending_test"] = True
        test_instruction = (
            "The tutor recommends a short 3-question assessment to check understanding. "
            "When you confirm, the quiz will start: you'll receive 3 questions of increasing difficulty. "
            "Each correct answer awards +1 StashStar. Click Confirm to begin."
        )
        base_response = {
            "tutor_response": tutor_reply,
            "status": session["status"],
            "test_prompt": True,
            "test_instructions": test_instruction,
            "transcript_info": transcript_info,
            "user_preferences": user_prefs
        }
        # if mcq:
        #     base_response["mcq"] = mcq_data
        return base_response

    response_payload = {
        "tutor_response": tutor_reply,
        "status": "tutoring",
    }
    print("RES",response_payload)
    return response_payload    

@app.post("/start_test")
def start_test(payload: StartTestPayload):
    if payload.session_id not in sessions_db:
        raise HTTPException(status_code=404, detail="Session expired or not found")

    session = sessions_db[payload.session_id]
    history = session.get("session_history", [])
    history_str = ' '.join(json.dumps(h["text"]) for h in history)
    gen_input = f"Original Concept: {session.get('original_concept', '')}\nSession History: {history_str}"

    questions_resp = ask_deepseek(get_prompt("generate_3_questions"), gen_input)
    questions = questions_resp.get("questions", []) if isinstance(questions_resp, dict) else []

    if not questions:
        raise HTTPException(status_code=500, detail="Failed to generate test questions")

    # Initialize the test queue and the session storage reference for answers
    session["test_queue"] = questions
    session["test_history"] = []  # Clear/initialize session storage for the new test
    session["test_index"] = 0
    session["status"] = "in_test"
    session["pending_test"] = False

    first_q = questions[0]
    question_text = first_q.get('question', '') if isinstance(first_q, dict) else str(first_q)

    return {
        "tutor_response": first_q,
        "raw_question": question_text,
        "status": session["status"],
        "question_index": 1,
        "total_questions": len(questions),
    }


@app.post("/submit_answer")
def submit_answer(payload: SubmitAnswerPayload):
    if payload.session_id not in sessions_db:
        raise HTTPException(status_code=404, detail="Session expired or not found")

    session = sessions_db[payload.session_id]
    queue = session.get("test_queue", [])
    idx = session.get("test_index", 0)

    if not isinstance(queue, list) or idx >= len(queue):
        raise HTTPException(status_code=400, detail="No active test question")

    current = queue[idx]
    correct = False
    explanation = ""
    canonical_answer_text = ""

    # 1. Evaluate Multiple Choice
    if isinstance(current, dict) and current.get("choices"):
        raw_choices = current.get("choices", [])
        
        choice_texts = [
            c["text"] if isinstance(c, dict) and "text" in c else str(c)
            for c in raw_choices
        ]

        correct_index = current.get("answer_index")
        if correct_index is None:
            for i, c in enumerate(raw_choices):
                if isinstance(c, dict) and c.get("correct") is True:
                    correct_index = i
                    break

        if correct_index is not None and 0 <= correct_index < len(choice_texts):
            canonical_answer_text = choice_texts[int(correct_index)]

        student_choice_index = None
        sval = str(payload.answer).strip()

        if sval.isdigit():
            iv = int(sval)
            if 1 <= iv <= len(choice_texts):
                student_choice_index = iv - 1
            elif 0 <= iv < len(choice_texts):
                student_choice_index = iv
        else:
            try:
                student_choice_index = choice_texts.index(sval)
            except ValueError:
                student_choice_index = None

        if student_choice_index is not None and correct_index is not None:
            correct = (student_choice_index == int(correct_index))

        explanation = current.get("explanation", "")

    # 2. Evaluate Free-Text Answer (Fallback)
    else:
        canonical_answer_text = current.get('answer', '')
        grade_input = (
            f"Question: {current.get('question', '')}\n"
            f"Canonical Answer: {canonical_answer_text}\n"
            f"Student Answer: {payload.answer}"
        )
        grade_resp = ask_deepseek(get_prompt("grade_answer"), grade_input)
        correct = bool(grade_resp.get("correct", False)) if isinstance(grade_resp, dict) else False
        explanation = grade_resp.get("explanation", "") if isinstance(grade_resp, dict) else ""

    # 3. Store response and correct boolean in Session Storage reference
    session.setdefault("test_history", []).append({
        "question": current.get("question", ""),
        "student_response": payload.answer,
        "correct_answer": canonical_answer_text,
        "correct": correct,
        "explanation": explanation
    })

    # Increment index
    session["test_index"] = idx + 1

    # 4. Return next question if available
    if session["test_index"] < len(queue):
        raw_next = queue[session["test_index"]]
        next_q_text = raw_next.get("question", "") if isinstance(raw_next, dict) else str(raw_next)

        return {
            "tutor_response": explanation,
            "next_question": raw_next,
            "raw_question": next_q_text,
            "question_index": session["test_index"] + 1,
            "total_questions": len(queue),
            "status": "in_test",
        }

    # 5. Test Complete: Derive stars strictly from session reference and generate report
    stash_stars = sum(1 for item in session["test_history"] if item.get("correct") is True)
    
    # Prompt the AI to generate the report content
    summary_input = (
        f"Original Concept: {session.get('original_concept', '')}\n"
        f"Test History (Session Data): {json.dumps(session.get('test_history', []))}\n"
        "Generate a JSON object with 'summary', 'competency_notes', and 'report_content'. "
        "'report_content' must be a detailed markdown string outlining the questions, the student's answers, "
        "why they were wrong or right, and the key concepts learned."
    )
    
    final_summary = ask_deepseek(get_prompt("final_summary"), summary_input)
    summary_text = final_summary.get("summary", "Great job today!") if isinstance(final_summary, dict) else "Great job today!"
    competency = final_summary.get("competency_notes", "") if isinstance(final_summary, dict) else ""
    report_content = final_summary.get("report_content", "Detailed performance report is unavailable.") if isinstance(final_summary, dict) else "No report generated."

    session["status"] = "awaiting_continuation"

    return {
        "tutor_response": explanation,
        "final_summary": summary_text,
        "competency_notes": competency,
        "report_content": report_content,
        "stash_stars": stash_stars,
        "status": session["status"],
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="172.20.10.4", port=8000)