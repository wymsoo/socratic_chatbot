# Steps
- start docker
- test memory containers by running memory_ui.py (note there are two, run the one in folder mem0)
- run node app.js
- run flutter app
- Click breakout room block to try out chatbot

# Details
## testing the memory containers before running the app
- go to folder 'controllers'
- Start the memory UI (inspect and edit memories) to test whether memory is running properly
  `node test_mem_db.py`
- Check for connection status. If connected, select 2: see all memories. You will see the memories currently stored. 
- You can select number 1 and try to add your own memories.
- if its working, it should also work in the flutter application

## to try out the chatbot
- run node app.js (ignore server1.py)
- run app by `flutter run` on a separate terminal
- go to lib 'breakout.dart' to change a testing 'lecture transcript/snippet' as an input
- one you click the home page's 'Breakout rooms' it will directly start processing the lecture transcript and the session starts

**Notes for Memory**
- a `mem0` memory backend is expected and may raise connection errors if services are not running. To run services, start docker by `docker compose up -d`.
- Make sure status shows "connected".
- change the 'backend_url' in lib/breakout.dart according to your own device address
- **Reference for memories** https://mem0.ai/blog/self-host-mem0-docker 

# RAG for question generation
- StashTag-Demo now has a new schema called 'dse_questions'
- this is added as a vector database (refer to MongoDB Atlas)
- Run generate_questions.js (tied to rag_store.js) to test out the function


