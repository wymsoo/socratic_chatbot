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

from pathlib import Path


# 2. INITIALIZE A SINGLE MEMORY CLIENT (Scoping is handled by agent_id later)
mem_chat_hist = MemoryUI(user_id="default_user",agent_id="chat_history_agent")
mem_chat_hist.run()
user_pref = MemoryUI(user_id="default_user",agent_id="user_pref_agent")
user_pref.run()
mem_transcript = MemoryUI(user_id="default_user",agent_id="transcript_agent")
mem_transcript.run()

app = FastAPI()

# Enable Cross-Origin Resource Sharing (CORS)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

API_KEY = os.environ.get("DEEPSEEK_API_KEY")  # Replace with your actual key
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
    # Using safe_substitute ensures prompts without the ${history} token don't throw KeyErrors
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
    """Step 1: Extract the 3 core confusing items from a raw text file snippet."""
    confusion_data = ask_deepseek(get_prompt("extract_confusion"), payload.lecture_snippet, "")
    statements = confusion_data.get("confusing_statements", [])
    summary = confusion_data.get("summary","No Summary was extracted")
    
    # Generate an explicit session identification handle
    session_id = str(uuid.uuid4())
    sessions_db[session_id] = {
        "original_concept": "",
        "lecture_snippet": payload.lecture_snippet,
        "learning_outcomes": {},
        "session_history": [],
        "node_queue": [], 
        "status": "awaiting_concept_selection",
        "test_history": []
    }

    # 3. STORE THE TRANSCRIPT INTO MEM0
    mem_transcript.add_memory([{"role": "system", "content": f"Transcript to reference: {payload.lecture_snippet}"}])
    mem_transcript.get_all_memories()
    
    return {
        "session_id": session_id,
        "confusing_statements": statements,
        "summary": summary
    }

@app.post("/select_concept")
def select_concept(payload: SelectConceptPayload):
    """Step 2: Receives the user selection and seeds the root execution engine node."""
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
            "strategy": l.get("strategy", ""),
            "first_question": l.get("first_question", ""),
            "resolved": bool(l.get("resolved", False)),
        }

    tutor_intro = plan_resp.get("overview", "")
    session["node_queue"].append(plan_resp.get("first_question", ""))

    first_question = None
    if session["node_queue"]:
        first_question = session["node_queue"][0] or prepare_next_node(session)

    return {
        "tutor_response": f"{tutor_intro}\n\n{first_question}",
        "status": session["status"]
    }


def summarize_and_plan(session: Dict[str, Any], selected_concepts: List[str]) -> Dict[str, Any]:
    lecture = session.get("lecture_snippet", "")
    system_prompt = get_prompt('summarize_and_plan')
    user_input = (
        f"STUDENT'S CONFUSED CANDIDATE CONCEPTS:\n{selected_concepts}\n\n"
        f"EXECUTION TASK:\nAnalyze the inputs above, identify the missing link, and populate the requested JSON schema."
    )

    resp = ask_deepseek(system_prompt, user_input, "")
    if not isinstance(resp, dict):
        return {}
    return resp

def normalize_learning_outcome(item: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "topic": item.get("topic", ""),
        "summary": item.get("summary", ""),
        "outcome": item.get("outcome", ""),
        "first_question": item.get("first_question", ""),
        "resolved": bool(item.get("resolved", False)),
    }


def normalize_learning_outcomes(lo: Any) -> Dict[str, Dict[str, Any]]:
    normalized: Dict[str, Dict[str, Any]] = {}
    if isinstance(lo, dict):
        return lo
    if isinstance(lo, list):
        for index, item in enumerate(lo):
            if not isinstance(item, dict):
                continue
            normalized[f"learning_outcome_{index}"] = normalize_learning_outcome(item)
            
    return normalized


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
        elif isinstance(payload, str):
            session["learning_outcomes"][key]["resolved"] = (
                session["learning_outcomes"][key].get("resolved", False)
                or payload.lower() == "resolved"
            )


def prepare_next_node(session: Dict[str, Any]) -> Optional[str]:
    while session["node_queue"]:
        current_node = session["node_queue"][0]
        concept_text = current_node["concept_text"]
        user_input_str = f"Target Concept: {concept_text}"
        default_rules = get_prompt(
            "default_rules",
            learning_outcomes=json.dumps(session.get("learning_outcomes", {})),
        )
        prompt = get_prompt("generate_question")
        node_data = ask_deepseek(prompt, user_input_str, default_rules)

        current_node["current_question"] = node_data.get("question", "Could you explain how this concept works?")
        current_node["topics"] = node_data.get("topics", [])
        return current_node["current_question"]
    return None


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

    if not session.get("node_queue"):
        raise HTTPException(status_code=400, detail="No active tutoring concepts in queue")

    current_question = session["node_queue"][-1]

    history_lines = []
    for msg in session.get("session_history", [])[-6:]:
        if isinstance(msg, dict) and "text" in msg:
            history_lines.append(msg["text"])
    history_str = "\n\n".join(history_lines) if history_lines else "No previous history yet. This is the first turn."

    # 1. RETRIEVE RELEVANT MEMORIES FIRST
    raw_transcript_memories = mem_transcript.search_memories(student_input)
    raw_pref_memories = user_pref.search_memories(student_input)
    
    transcript_info = [mem["memory"] for mem in raw_transcript_memories] if raw_transcript_memories else []
    user_prefs = [mem["memory"] for mem in raw_pref_memories] if raw_pref_memories else []

    # 2. FORMAT MEMORIES FOR THE AI CONTEXT
    memory_context = ""
    if transcript_info or user_prefs:
        memory_context = "--- RELEVANT PAST CONTEXT ---\n"
        if transcript_info:
            memory_context += "Transcript Details:\n- " + "\n- ".join(transcript_info) + "\n"
        if user_prefs:
            memory_context += "Student Preferences/History:\n- " + "\n- ".join(user_prefs) + "\n"
        memory_context += "-----------------------------\n\n"

    # 3. INJECT THE MEMORY CONTEXT INTO THE PAYLOAD SENT TO DEEPSEEK
    handler_payload = f"{memory_context}Question: {current_question}\nStudent: {student_input}"
    default_rules = ""

    unresolved_outcomes = unresolved_learning_outcomes(session)
    num_of_uro = len(unresolved_outcomes)
    num_of_hist = len(session.get('session_history',[]))
    give_ans = False
    
    if num_of_uro==3 and num_of_hist==6:
        give_ans = True
    elif num_of_uro==2 and num_of_hist==12:
        give_ans = True
    elif num_of_uro==3 and num_of_hist==16:
        give_ans = True
    
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
            "user_preferences": []
        }
        
    ai_output = ask_deepseek(
        get_prompt(
            "chat",
            lecture_snippet=session.get("lecture_snippet", ""),
            current_question=current_question,
            history=history_str,
            learning_outcomes=json.dumps(unresolved_outcomes, indent=2),
            give_ans=str(give_ans)
        ),
        handler_payload,
        default_rules
    )

    tutor_reply = ai_output.get("response", "")

    # 4. STORE THE NEW CHAT TURN IN MEM0 FOR FUTURE RETRIEVAL
    chat_interaction = [
        {"role": "user", "content": f"[Student stated]: {student_input}"},
        {"role": "assistant", "content": f"[AI Tutor explained]: {tutor_reply}"}
    ]
    
    mem_chat_hist.add_memory(chat_interaction)
    user_pref.add_memory(chat_interaction)

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

    updated_outcomes = ai_output.get("learning_outcomes")
    merge_learning_outcome_updates(session, updated_outcomes)

    if all_outcomes_resolved(session):
        session["status"] = "testing_prompt"
        session["pending_test"] = True
        test_instruction = (
            "The tutor recommends a short 3-question assessment to check understanding. "
            "When you confirm, the quiz will start: you'll receive 3 questions of increasing difficulty. "
            "Each correct answer awards +1 StashStar. Click Confirm to begin."
        )
        return {
            "tutor_response": ai_output.get("response", test_instruction),
            "status": session["status"],
            "test_prompt": True,
            "test_instructions": test_instruction,
            "transcript_info": transcript_info,
            "user_preferences": user_prefs
        }

    session["current_question"] = ai_output.get("question", current_question)
    
    return {
        "tutor_response": tutor_reply,
        "status": "tutoring",
        "transcript_info": transcript_info,
        "user_preferences": user_prefs
    }    
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

    mcq_questions: List[Dict[str, Any]] = []
    for q in questions:
        if isinstance(q, dict) and q.get("choices"):
            if "answer_index" not in q and "answer" in q:
                try:
                    q["answer_index"] = int(q.get("answer"))
                except Exception:
                    try:
                        q["answer_index"] = q.get("choices",[]).index(str(q.get("answer")))
                    except Exception:
                        q["answer_index"] = 0
            mcq_questions.append(q)
        else:
            q_text = q.get("question") if isinstance(q, dict) else str(q)
            mcq_questions.append(convert_to_mcq(q_text))

    session["test_queue"] = mcq_questions
    session["test_index"] = 0
    session["total_score"] = 0
    session["status"] = "in_test"
    session["pending_test"] = False

    first_q = questions[0]
    choices_text = "\n".join([f"{i+1}. {c}" for i, c in enumerate(first_q.get("choices", []))])
    question_text = f"{first_q.get('question', '')}\n\n{choices_text}"
    return {
        "tutor_response": question_text,
        "raw_question": first_q,
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

    if idx >= len(queue):
        raise HTTPException(status_code=400, detail="No active test question")

    current = queue[idx]
    correct = False
    explanation = ""
    if isinstance(current, dict) and current.get("choices"):
        choices = current.get("choices", [])
        correct_index = current.get("answer_index") if current.get("answer_index") is not None else None

        student_choice_index = None
        try:
            sval = str(payload.answer).strip()
            if sval.isdigit():
                iv = int(sval)
                if 1 <= iv <= len(choices):
                    student_choice_index = iv - 1
                elif 0 <= iv < len(choices):
                    student_choice_index = iv
            else:
                try:
                    student_choice_index = choices.index(sval)
                except ValueError:
                    student_choice_index = None
        except Exception:
            student_choice_index = None

        if student_choice_index is not None and correct_index is not None:
            correct = (student_choice_index == int(correct_index))
        else:
            correct = False

        explanation = current.get("explanation", "")

        if correct:
            session["total_score"] = session.get("total_score", 0) + 1

        session.setdefault("test_history", []).append({
            "phase": "test",
            "question": current.get("question", ""),
            "student_answer": payload.answer,
            "selected_index": student_choice_index,
            "correct": correct,
            "explanation": explanation,
        })

    if not (isinstance(current, dict) and current.get("choices")):
        grade_input = (
            f"Question: {current.get('question', '')}\n"
            f"Canonical Answer: {current.get('answer', '')}\n"
            f"Student Answer: {payload.answer}"
        )
        grade_resp = ask_deepseek(get_prompt("grade_answer"), grade_input)
        correct = bool(grade_resp.get("correct", False)) if isinstance(grade_resp, dict) else False
        explanation = grade_resp.get("explanation", "") if isinstance(grade_resp, dict) else ""
        if correct:
            session["total_score"] = session.get("total_score", 0) + 1
        session.setdefault("test_history", []).append({
            "phase": "test",
            "question": current.get("question", ""),
            "student_answer": payload.answer,
            "correct": correct,
            "explanation": explanation,
        })

    session["test_index"] = idx + 1

    if session["test_index"] < len(queue):
        raw_next = queue[session["test_index"]]
        if isinstance(raw_next, dict) and raw_next.get("choices"):
            choices_text = "\n".join([f"{i+1}. {c}" for i, c in enumerate(raw_next.get("choices", []))])
            next_q_text = f"{raw_next.get('question', '')}\n\n{choices_text}"
        else:
            next_q_text = raw_next.get("question", "") if isinstance(raw_next, dict) else str(raw_next)

        return {
            "tutor_response": explanation,
            "next_question": next_q_text,
            "raw_question": raw_next,
            "question_index": session["test_index"] + 1,
            "total_questions": len(queue),
            "score": session.get("total_score", 0),
            "status": "in_test",
        }

    summary_input = (
        f"Original Concept: {session.get('original_concept', '')}\n"
        f"Test History: {json.dumps(session.get('test_history', []))}\n"
        f"Test Score: {session.get('total_score', 0)}"
    )
    final_summary = ask_deepseek(get_prompt("final_summary"), summary_input)
    summary_text = final_summary.get("summary", "Great job today! Keep up the good work.") if isinstance(final_summary, dict) else "Great job today!"
    competency = final_summary.get("competency_notes", "") if isinstance(final_summary, dict) else ""

    stash = int(session.get("total_score", 0))
    session["status"] = "awaiting_continuation"

    return {
        "tutor_response": "Test complete.",
        "final_summary": summary_text,
        "competency_notes": competency,
        "stash_stars": stash,
        "status": session["status"],
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="172.20.10.4", port=8000)