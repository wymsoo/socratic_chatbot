# StashTag 2.0: Frontend UI/UX Handoff Document

This document outlines the detailed user interface specifications, interactive elements, and navigation flows for the StashTag 2.0 application. It is segmented by user type (Class Student, Individual Tertiary Student, and Professor) and categorized by the corresponding UI mockups to facilitate frontend development.

---

## Slide 1: Authentication & Onboarding

![Slide 1](1.png)

**Target User:** All Users

*   **Screen 1.1: Splash & Login**
    *   **Visual Element:** Central graphic featuring the "Ghosty" mascot wearing a graduation cap.
    *   **"Register Now" Button:** A prominent yellow button that navigates the user to the registration workflow (Screen 1.2).
    *   **"Login" Button:** A secondary light-blue button that navigates existing users to the login screen.
*   **Screen 1.2: User Path Selection**
    *   **Text Prompt:** Asks, "Are you using StashTag as a part of a class, hosted by your teacher?".
    *   **"Yes, I am registering as part of a class" Button:** Yellow button mapping the user to the "Class version" account tier.
    *   **"No, I am registering as an individual student" Button:** Light blue button mapping the user to the "Tertiary individual student" account tier.
    *   **Back Arrow (Top Left):** Navigates back to the Splash Screen.
*   **Screen 1.3: Registration Form**
    *   **Institution Code Field:** Text input for school identification (placeholder: "HKUST").
    *   **Username Field:** Text input for the desired account name (placeholder: "mini123so").
    *   **Password & Confirm Password Fields:** Masked text inputs for account security.
    *   **"Register" Button:** Validates the form data, creates the account, and navigates the user to their respective dashboard.

---

## Slide 2: Course Library (Individual Student Version)

![Slide 2](2.png)

**Target User:** Tertiary Individual Students

*   **Screen 2.1: Library Overview (Empty/Initial State)**
    *   **Course Card:** Displays active courses, such as a yellow card for "PHYS1114 General Physics".
    *   **"Add Course +" Button:** A dashed-border interactive area. Tapping this opens the "Add Course" modal (Screen 2.2).
    *   **Bottom Navigation Bar:** Features icons for the Library (active/highlighted) and User Profile.
*   **Screen 2.2: Add Course Modal**
    *   **Input Fields:** Contains text fields for "Course Code" (e.g., PHYS1101), "Section Code" (e.g., L2), "Course Name" (e.g., Introductory Physics), and "Lecture Time" (e.g., 01:20).
    *   **"Add to Library" Button:** Saves the course data and updates the Library Overview (Screen 2.3).
*   **Screen 2.3: Library Overview (Populated State)**
    *   **Multiple Course Cards:** Shows newly added courses side-by-side (e.g., PHYS1114 and COMP2011).
    *   **"Upgrade for Unlimited Courses" Button:** A dashed-border call-to-action. Clicking this navigates the user to the Subscription/Upgrade page (Slide 3).

---

## Slide 3: Subscription Upgrades

![Slide 3](3.png)

**Target User:** Tertiary Individual Students

*   **Screen 3.1: "Upgrade your Plan!" Modal**
    *   **Student Premium Tier:** Displays limits (5 courses, 5000 min) and price ($38/mo). The "Unlock" button processes the monthly subscription.
    *   **Student Pro Tier:** Displays limits (Unlimited courses, 10000 min) and price ($358/yr). The "Unlock" button processes the annual subscription.
    *   **+ Breakout Room Tier:** An add-on featuring unlimited Socratic Tutor access for $128/yr. The "Unlock" button adds this feature to the user's account.

---

## Slide 4: In-Class Stashing Interface

![Slide 4](4.png)

**Target User:** Class Students

*   **Screen 4.1: Active Stashing View**
    *   **Top Statistics Bar:** Tracks live session metrics, including a lightbulb icon (5), a notes icon (3), and a question mark icon (6).
    *   **"Got it!" Button (Left):** Circular button featuring Ghosty with a lightbulb. Logs a point of understanding in real-time.
    *   **"I'm Confused!" Button (Right):** Circular button featuring Ghosty taking notes with a question mark. Logs a timestamped point of confusion.
    *   **Bottom Navigation Bar:** Contains icons for Stashing (active), Notes/Assignments, Community, and a "..." (More) menu. Includes a "Chatroom Disabled" indicator badge.
*   **Screen 4.2: Navigation Menu Expansion**
    *   **"..." Menu:** Tapping the far-right icon opens a vertical pop-up menu.
    *   **Menu Items:** Navigates the user to "Home", "Assignments", or "Ghosty the Stashbot".
*   **Screen 4.3: Post-Lecture Summary Modal**
    *   **"Lesson Completed!" Modal:** Appears automatically when the professor ends the session.
    *   **Status Text:** Congratulates the user and summarizes flagged items (e.g., "You have successfully identified 7 confusions").
    *   **Interactive Flow Graphic:** Displays an "Identify -> Resolve -> Master" roadmap. Tapping "Resolve" likely navigates the user to the Resolve Confusions list (Slide 5).

---

## Slide 5: Learning Roadmap & Resolution Hub

![Slide 5](5.png)

**Target User:** Class Students

*   **Screen 5.1: Learning Roadmap**
    *   **Visual Interface:** A gamified, node-based map representing different lectures (e.g., Lecture 1, Lecture 2, etc.).
    *   **Nodes:** Lectures with completed resolutions show a gold star. The Ghosty mascot hovers over the currently active/pending lecture node.
*   **Screen 5.2: Resolve Confusions (Confusions Tab)**
    *   **Top Toggle:** Allows switching between "Confusions" and "Notes" views.
    *   **"Unresolved" List:** Displays a vertically scrolling list of flagged confusions.
    *   **Confusion Cards:** Each entry features a specific timestamp (e.g., "Timestamp 6 min 31 sec") and auto-generated contextual tags (e.g., "Initial velocity", "projectile", "EOM"). Tapping a card opens the detailed view (Slide 6).
*   **Screen 5.3: Resolve Confusions (Notes Tab)**
    *   **Notes List:** Displays notes taken during the lecture, organized by timestamp.
    *   **Content Display:** Shows detailed text captured at that moment (e.g., a note about a "Battery-less RFID Camera System" at Timestamp 12 min 13 sec).

---

## Slide 6: Breakout Room Entry point

![Slide 6](6.png)

**Target User:** Individual Students

*   **Screen 6.1 & 6.2: Confusion Detail Expansion**
    *   **Expanded Card:** When a confusion timestamp card is selected, it expands to reveal AI-generated explanations.
    *   **Text Sections:** Contains "1. Your Confusion" (diagnosing the root cause) and "2. Additional Explanations" (providing analogies).
    *   **"Mark as Done" Button:** A green button that moves the item from the "Unresolved" to the "Resolved" list.
    *   **"Discuss More" Button:** A blue button that launches the 1-on-1 AI Breakout Room (Slide 7) for Socratic learning.

---

## Slide 7: AI Breakout Room (Socratic Tutor)

![Slide 7](7.png)

**Target User:** Class Students

*   **Screen 7.1: Chat Interface**
    *   **"Exit" Button:** A red button in the top right to leave the breakout room and return to the resolution hub.
    *   **Chat Bubbles:** The AI provides interactive, conversational tutoring. It pushes multiple-choice prompts to diagnose understanding (e.g., "Which of the following topics is most confusing to you?").
    *   **Option Buttons:** Interactive chips for the student to select an answer directly in the chat.
    *   **Text Input:** A standard chat input field at the bottom ("Type whats on your mind...") with a send arrow.
*   **Screen 7.2: Diagnostic Report Modal**
    *   **Report Card:** Appears upon finishing a chat segment. Details "What you covered" and "What to Improve".
    *   **Star Rating:** Displays a 3-star visual metric for the session.
    *   **"Complete" Button:** Closes the report.
    *   **"Still unsure? Post a questions here ->" Link:** Navigates the user to the Community Post feature (Screen 7.3).
*   **Screen 7.3: Post to Community Modal**
    *   **"Post a question" Box:** A free-text area for the user's specific query.
    *   **"Suggested Questions" Buttons:** Auto-generated question prompts that the user can tap to auto-fill the text box.
    *   **"Post anonymously" Checkbox:** Toggles user privacy on the public forum.
    *   **"Post" Button:** Publishes the question to the StashTag Community (Slide 8).

---

## Slide 8: Community & Student Dashboard

![Slide 8](8.png)

**Target User:** Class Students

*   **Screen 8.1: StashTag Community**
    *   **Top Toggles:** Switch between "FOR YOU" (personalized feed) and "UNRESOLVED" (open questions).
    *   **Question Cards:** Displays community posts, complete with the question text, relevant tags (e.g., "Initial velocity"), the author's name/pseudonym ("Anonymous Tiger"), and timestamp.
    *   **Arrow Icon (Right):** Navigates the user into the specific discussion thread for that question.
*   **Screen 8.2: Student Profile**
    *   **User Info:** Displays name (e.g., "Chan Tai Ming, Ken") and an AI-generated personalized learning persona description.
    *   **"Reset Profile" Button:** Allows the user to refresh their persona or data.
    *   **Course Dropdown:** Filters the dashboard metrics by specific classes (e.g., PHYS1101).
    *   **Resolutions Metric:** Displays the total number of earned stars (e.g., 26).
    *   **Achievements Section:** Visual badges earned by the student (e.g., "First Stash", "Perfect Sunday", "Untangled").
    *   **Assignment Average:** A list view displaying the overall average (88.3%) and a breakdown of individual assignment scores.
    *   **"Review Assignments" Link:** Navigates the user to a detailed view of past graded work.

---

## Slide 9: Professor Course Management & Live Recording

![Slide 9](9.png)

**Target User:** Professors

*   **Screen 9.1: Professor Course Library**
    *   **Course Card:** Identical styling to the student view, showing active courses (PHYS1114).
    *   **Lectures List:** Displays created lectures underneath the selected course.
    *   **"+ Add Lecture" Button:** Opens a modal to schedule or create a new lecture module.
    *   **Bottom Navigation Bar:** Features icons for Record/Microphone (active), Dashboard/Analytics, Assignments, and More.
*   **Screen 9.2: Pre-Recording Interface**
    *   **"Start Recording" Button:** A large, prominent button to begin tracking a live lecture session.
    *   **"QR code" Button:** Generates a code for students to scan and join the live session.
    *   **Questions Toggle:** An "Enabled/Disabled" switch to allow or block live question submissions from the class.
*   **Screen 9.3: Active Recording Interface**
    *   **"Stop Recording" Button:** Replaces the start button, styled in solid red, to terminate the session.
    *   **Live Question Feed:** A real-time, scrolling list of student queries submitted during the lecture (e.g., "What would happen if k > 1?") with timestamps. Note: Bottom navigation is intended to be disabled during active recording.

---

## Slide 10: Professor Analytics Dashboard

![Slide 10](10.png)

**Target User:** Professors

*   **Screen 10.1: Overview Dashboard**
    *   **"Stashing Distribution" Chart:** A stacked bar chart visualizing where the class pressed "Got it" vs. "Confused" across the lecture timeline.
    *   **"Lecture Review" List:** An AI-generated breakdown of the lecture into Major Topics and Subtopics alongside duration timestamps (e.g., "03 min Major Topic 1").
*   **Screen 10.2: Confusion & Breakout Analytics**
    *   **"Most Confusing Topics" Pie Chart:** Visually breaks down which subjects received the most "Confused" tags (e.g., Lenz Law 50%, Gauss Law 30%).
    *   **"Breakout Room Data" Bar Chart:** A horizontal bar chart tracking the "Percentage Score" of how well students resolved their confusion on specific topics (e.g., Faraday's Law, Vector) within their Socratic AI sessions.
*   **Screen 10.3: Advanced Visualizations (Tablet/Web)**
    *   **Topics Network Graph:** A node-based scatter web showing how different curriculum concepts interlink based on student data.
    *   **Assignment Score Distribution:** A traditional histogram/bar chart illustrating the grade curve across the classroom.

---

## Slide 11: AI Assignment Generation

![Slide 11](11.png)

**Target User:** Professors

*   **Screen 11.1: Assignments Hub**
    *   **Assignment Card:** Displays published tasks, due dates, and submission rates (e.g., "Submitted: 28/32").
    *   **"Create Assignment" Button:** A dashed-border button that initiates the AI generation flow (Screen 11.2).
*   **Screen 11.2: Generate Assignments Menu**
    *   **Topic List:** Displays the auto-segmented lecture topics.
    *   **Magic Wand Icons:** Small buttons next to each major topic. Tapping one opens the generation settings for that specific topic (Screen 11.3).
    *   **Generated Questions Area:** Displays blocks of AI-created questions. Includes "Select" and "Delete" buttons to curate the final assignment.
    *   **"Review and Publish" Button:** Finalizes the curated list and posts it to the students.
*   **Screen 11.3: Assignment Generation Settings**
    *   **"No. Questions to Gen" Inputs:** Number fields corresponding to specific Sub Topics to tell the AI exactly how many questions to create per granular concept.
    *   **"Additional Requirements" Box:** A free-text field for the professor to provide custom prompting to the AI (e.g., "For Topic 1, focus more on the mathematical derivation...").
    *   **"Generate" Button:** Executes the AI prompt and populates the list on the previous screen.