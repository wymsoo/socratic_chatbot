# StashTag Demo

StashTag Demo is a Flutter learning application backed by a Node.js API. It includes lecture chat, quizzes, assignments, question generation, learner profiles, and Mem0-backed memory services.

## Repository Layout

This workspace contains one Git repository with several project areas:

- `lib/`: Flutter application screens and learning flows.
- `assets/`: app images, data, and other bundled resources.
- `backend/`: Express API, prompt templates, question data, RAG code, and Mem0 integration.
- `backend/mem0-deploy/`: Docker Compose stack for Mem0, PostgreSQL/pgvector, and Neo4j.
- `backend/mem0/`: Python utilities for memory and RAG experiments.
- `cli/`: separate Dart command-line package.
- `test/`: Flutter widget tests.
- `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/`: Flutter platform projects.

`cli/` is a nested Dart package, not a separate Git repository.

## Requirements

- Flutter and Dart SDK compatible with Dart `3.12.2`.
- Node.js with npm.
- Docker Desktop for the Mem0 services.
- A MongoDB Atlas connection for RAG question retrieval.
- API credentials for the providers used by the selected backend features.

## Secrets and Environment

Backend secrets belong in `backend/.env`, which is ignored by Git. Start from [`backend/.env.example`](backend/.env.example):

```sh
cp backend/.env.example backend/.env
```

Fill only the variables needed for the feature you are running. The backend loads this file by path, so commands work whether they are launched from the repository root or from `backend/controllers/`.

## Run the Flutter App

From the repository root:

```sh
flutter pub get
flutter run
```

For a physical device, update the backend address used by the relevant Flutter screen from `localhost` to the host machine's LAN address.

Run Flutter checks with:

```sh
flutter analyze
flutter test
```

## Run the Node Backend

Install the Node dependencies defined by the root `package.json`, then start the API:

```sh
npm install
node backend/app.js
```

The API listens on port `8000` by default. Set `PORT` in `backend/.env` to change it. Main routes include `/chat`, `/memory`, `/memory/search`, `/api/quiz`, `/api/questions`, and `/api/assignments`.

Question generation can be run directly after configuring `AIML_API_KEY` and `MONGODB_URI`:

```sh
node backend/controllers/generate_questions.js
```

## Run Mem0 Services

Start the self-hosted memory dependencies from the deployment directory:

```sh
cd backend/mem0-deploy
docker compose up -d
```

The stack exposes Mem0 on `localhost:8888`, PostgreSQL/pgvector on port `8432`, Neo4j Browser on port `8474`, and Neo4j Bolt on port `8687`. Inspect service output with `docker compose logs -f` and stop it with `docker compose down`.

## Run the Dart CLI

```sh
cd cli
dart pub get
dart run
dart test
```

## Development Notes

- `lib/breakout.dart` contains the lecture transcript and backend URL used by the breakout-room flow.
- `backend/prompt_templates/` contains the prompts used by chat, grading, summaries, and question generation.
- `backend/ragdata/` contains quiz and teaching RAG data.
- The generated `build/`, `.dart_tool/`, `node_modules/`, and platform build artifacts should remain uncommitted.
