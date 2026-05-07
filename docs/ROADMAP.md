# Role & Objective
Act as a Senior Tooling Engineer specializing in Roblox (Luau) and Node.js. 
Your objective is to build a "Real-Time AI Bridge" that allows an AI/Local Environment to read, write, and modify Roblox map data (Instances, Properties, Workspace layout) and scripts in real-time.

# Architecture Overview
We will build a bidirectional communication system consisting of two main components:
1. **Local Bridge Server (Node.js):** A local HTTP server that watches local files and communicates with Roblox Studio.
2. **Roblox Studio Plugin (Luau):** A plugin running inside Roblox Studio that serializes/deserializes Instances to JSON, polls the local server, and applies changes to the map in real-time.

# Development Steps
Please execute this project step-by-step. Wait for my confirmation after completing each step before moving to the next.

## Step 1: Initialize the Local Node.js Server
- Create a new Node.js project.
- Set up an Express.js server (or fastify) running on `localhost:3000`.
- Create the following API endpoints:
  - `GET /sync`: For the Roblox plugin to fetch the latest changes made by the AI in the local file system.
  - `POST /sync`: For the Roblox plugin to send the current state of the map (Workspace) as a JSON payload.
- Ensure the server writes the incoming JSON map data to a file named `map_context.json` so the AI can read it.

## Step 2: Create the Roblox Serialization Module (Luau)
- Write a Luau ModuleScript that can convert Roblox Instances (Parts, Models, Scripts) into a readable JSON format.
- It must capture: `ClassName`, `Name`, `Parent`, and key properties (e.g., `Position`, `Size`, `Color`, `Source` for scripts).
- Write a deserialization function that takes a JSON object and creates or updates the corresponding Instances in the Roblox Workspace.

## Step 3: Develop the Roblox Studio Plugin (Luau)
- Create a Roblox Studio Plugin script using standard plugin architecture.
- Use `HttpService` to continuously poll the `GET /sync` endpoint (e.g., every 1-2 seconds) to listen for any commands or map updates written by the AI.
- Add a plugin toolbar button to "Push Map State", which will serialize the current Workspace using the module from Step 2 and send it via `POST /sync`.

## Step 4: Establish the AI Action Format (JSON Protocol)
- Define a strict JSON schema for how I (the AI) should write commands to modify the map. 
- Example format: 
  `{"action": "update", "target": "Workspace.Part1", "properties": {"Size": [10, 10, 10]}}`
- Implement the logic in the Node.js server to read these "action" files and queue them up for the Roblox plugin's next `GET` request.

# Rules for Code Generation
- Write clean, modular, and well-documented code.
- Optimize the Node.js server to handle frequent polling efficiently.
- In Luau, always use `task.wait()` instead of `wait()`.
- Ensure the Node.js setup is standard and compatible with Linux environments.

Start by executing Step 1.