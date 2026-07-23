# Steps
- start docker
- test memory containers by running memory_ui.py (note there are two, run the one in folder mem0)
- run python backend server.py
- run flutter app (can hot-restart by typing R)


## to try out the chatbot
- run backend server.py (ignore server1.py)
- run app by `flutter run` on a separate terminal
- go to lib 'breakout.dart' to change a testing 'lecture transcript/snippet' as an input
- one you click the home page's 'Breakout rooms' it will directly start processing the lecture transcript and the session starts

## testing the memory containers before running the app
- go to folder 'mem0'
- Start the memory UI (inspect and edit memories) to test whether memory is running properly
  `python memory_ui.py`
- Check for connection status. If connected, select 2: see all memories. You will see the memories currently stored. 
- You can select number 1 and try to add your own memories.
- if its working, it should also work in the flutter application

**Notes for Memory**
- `mem0/memory_ui.py` expects a `mem0` memory backend and may raise connection errors if services are not running. To run services, start docker by `docker compose up -d`.
- Make sure status shows "connected" before running chatbot.py.
- **Reference for memories** https://mem0.ai/blog/self-host-mem0-docker 


