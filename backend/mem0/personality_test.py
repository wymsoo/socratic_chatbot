import json
import requests
import os

# API_KEY = 

QUIZ_QUESTIONS = [
    {
        "id": "q1_hobbies",
        "question": "1. What are your favorite hobbies, sports, or creative outlets outside of school?",
        "type": "open",
    },
    {
        "id": "q2_interests",
        "question": "2. When you have free time to work on a personal project, what do you naturally gravitate toward?",
        "type": "choice",
        "options": {
            "A": "Building, tinkering, or repairing physical/digital things (Hands-on)",
            "B": "Researching a deep, curious question or analyzing data (Investigative)",
            "C": "Designing, writing, drawing, or creating art/music (Artistic)",
            "D": "Helping others, teaching a friend, or organizing group activities (Social)",
        },
    },
    {
        "id": "q3_thinking_style",
        "question": "3. Which of the following do you enjoy most in learning?",
        "type": "choice",
        "options": {
            "A": "I love problem-solving, especially with clear logic, math, or step-by-step proofs.",
            "B": "I love thinking about complex theoretical problems, especially abstract ideas.",
            "C": "I enjoy practical work—I build, test, fail, and learn directly from mistakes.",
            "D": "I love reading and taking in new background knowledge before implementing it.",
        },
    },
    {
        "id": "q4_comprehension",
        "question": "4. How do you best make sense of a difficult new topic?",
        "type": "choice",
        "options": {
            "A": "Show me the big picture/final application first, so I know WHY it matters.",
            "B": "Walk me through step-by-step from fundamentals without skipping ahead.",
            "C": "Give me a real-world example or case study first, then explain theory.",
            "D": "Let me explore open-ended questions first to test my intuition.",
        },
    },
    {
        "id": "q5_explanation_style",
        "question": "5. When an AI or teacher explains a concept to you, which style clicks fastest?",
        "type": "choice",
        "options": {
            "A": "Concrete, real-life analogies and everyday metaphors.",
            "B": "Formal definitions, rigorous formulas, and exact terminology.",
            "C": "Visual diagrams, charts, and mental maps.",
            "D": "Interactive Socratic questions that force me to deduce the answer.",
        },
    },
    {
        "id": "q6_structure",
        "question": "6. How do you like your study materials or tutoring sessions structured?",
        "type": "choice",
        "options": {
            "A": "Highly structured: clear bullet points, defined checklists, and concise takeaways.",
            "B": "Conversational and exploratory: flexible tangents, deep dives, and 'what-if' scenarios.",
            "C": "Quick and direct: give me short summaries and let me ask follow-ups when stuck.",
            "D": "Practice-heavy: give me immediate exercises or practice problems right away.",
        },
    },
    {
        "id": "q7_error_handling",
        "question": "7. When you hit a dead end or get an answer wrong, what helps you recover best?",
        "type": "choice",
        "options": {
            "A": "Break down my mistake step-by-step so I see where my logic failed.",
            "B": "Explain the underlying core concept again in a completely different way.",
            "C": "Give me a smaller, simpler practice problem to rebuild my confidence.",
            "D": "Give me a subtle hint and let me try to fix it on my own first.",
        },
    },
    {
        "id": "q8_tone",
        "question": "8. What tone would you prefer your AI tutor to adopt?",
        "type": "choice",
        "options": {
            "A": "Encouraging, empathetic, and patient (like a friendly peer mentor).",
            "B": "Direct, precise, and highly academic (like a rigorous university professor).",
            "C": "Playful, enthusiastic, and highly energetic.",
            "D": "Socratic and challenging: pushing me to think harder rather than giving answers away.",
        },
    },
    {
        "id": "q9_pace",
        "question": "9. How do you prefer to interact during a study session?",
        "type": "choice",
        "options": {
            "A": "Fast-paced back-and-forth dialogue with frequent check-ins.",
            "B": "Slow and thorough: full explanations that I can read and reflect on deeply.",
        },
    },
    {
        "id": "q10_frustrations",
        "question": "10. Is there anything specific that frustrates you when learning something new? (e.g., 'Too much jargon')",
        "type": "open",
    },
]


def run_quiz():
    """Runs the terminal quiz and collects responses."""
    print("=" * 60)
    print("         WELCOME TO THE LEARNER PERSONALITY QUIZ")
    print("=" * 60 + "\n")

    user_responses = {}

    for item in QUIZ_QUESTIONS:
        print(f"\n{item['question']}")

        if item["type"] == "open":
            answer = input("> Answer: ").strip()
            user_responses[item["id"]] = answer

        elif item["type"] == "choice":
            for key, val in item["options"].items():
                print(f"   [{key}] {val}")

            while True:
                choice = input("> Select (A, B, C, D): ").strip().upper()
                if choice in item["options"]:
                    # Store both the key and the full string response for LLM context
                    user_responses[item["id"]] = {
                        "option": choice,
                        "text": item["options"][choice],
                    }
                    break
                print("Invalid selection. Please choose a valid option letter.")

    return user_responses



PROMPT = """
### SYSTEM PROMPT: LEARNER PROFILE GENERATOR

You are an expert educational psychologist. Your task is to analyze a student's responses to a 10-question learning style quiz and synthesize them into a concise, high-density "Learner System Persona" (max 150 words).

This profile will be injected into the System Prompt of an AI Tutor chatbot to personalize instruction.

---
### INPUT DATA:
[Paste Student Quiz JSON / Raw Text Responses Here]

---
### OUTPUT FORMAT:
Generate the summary in the exact format below:

**[STUDENT PROFILE SUMMARY]**
- **Learner Type:** [e.g., Abstract-Sequential / Practical-Experiential]
- **Primary Domain Hobbies:** [List key hobbies for analogy generation]
- **Explanatory Preference:** [e.g., Analogies, Step-by-Step, Visuals, Rigorous Theory]
- **Pedagogical Strategy:** [e.g., Socratic scaffolding, Direct feedback, Big-picture first]
- **Tone & Persona:** [e.g., Supportive peer, Rigorous academic, Energetic mentor]
- **Negative Constraints:** [e.g., Avoid long walls of text, avoid jargon without defining it]

Also generate a tainted summary that makes the student feel closer and special:
- Apart from the above traits, also add in 1 or 2 famous people so that whom the student can relate with, according to their hobbies.
- e.g. if the student likes art, you can introduce an artist. If the sutdent likes basketball, you can introduce an athlete.

- Example:
{
    summary: <your generated personality summary>
    display: "You are a... <tainted personality summary>.
}

"""

URL = "https://api.deepseek.com/chat/completions"

def ask_deepseek(system_prompt: str, user_input: str):
    payload = {
        "messages": [
            {"content": system_prompt, "role": "system"},
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


# --- EXECUTION ---
if __name__ == "__main__":

    dummy = """
    {
    "q1_hobbies": "shopping",
    "q2_interests": {
        "option": "B",
        "text": "Researching a deep, curious question or analyzing data (Investigative)"
    },
    "q3_thinking_style": {
        "option": "B",
        "text": "I love thinking about complex theoretical problems, especially abstract ideas."
    },
    "q4_comprehension": {
        "option": "A",
        "text": "Show me the big picture/final application first, so I know WHY it matters."
    },
    "q5_explanation_style": {
        "option": "A",
        "text": "Concrete, real-life analogies and everyday metaphors."
    },
    "q6_structure": {
        "option": "B",
        "text": "Conversational and exploratory: flexible tangents, deep dives, and 'what-if' scenarios."
    },
    "q7_error_handling": {
        "option": "A",
        "text": "Break down my mistake step-by-step so I see where my logic failed."
    },
    "q8_tone": {
        "option": "A",
        "text": "Encouraging, empathetic, and patient (like a friendly peer mentor)."
    },
    "q9_pace": {
        "option": "A",
        "text": "Fast-paced back-and-forth dialogue with frequent check-ins."
    },
    "q10_frustrations": "Things that I have never encountered before, and when i don't know why I need to learn it, make me very difficult to understand"
    } """
    summary = ask_deepseek(PROMPT, dummy)
    print(summary)