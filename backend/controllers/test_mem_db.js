let Memory;
const mem0 = require("mem0ai/oss");
const readline = require("readline");
Memory = mem0.Memory;

const dotenv = require("dotenv");
// Load environment variables from .env file
dotenv.config();

class MemoryUI {
    constructor(agentId, userId = "default_user") {
        this.userId = userId;
        this.agentId = agentId;
        this.connected = false;
        this.rl = readline.createInterface({
            input: process.stdin,
            output: process.stdout,
        });

        // Mem0 Configuration targeting Gemini
        this.config = {
            llm: {
                // You can also use "google" as provider ( for backward compatibility )
                provider: "gemini",
                config: {
                    model: "gemini-3.6-flash",
                    apiKey: process.env.GOOGLE_API_KEY || '',
                    temperature: 0.1
                }
            },
            embedder: {
                provider: "google",
                config: {
                    apiKey: process.env.GOOGLE_API_KEY || '',
                    model: "gemini-embedding-001",
                    embeddingDims: 1536,
                },
            },
            vectorStore: {
                provider: "pgvector",
                config: {
                    host: "localhost",
                    port: parseInt("8432", 10),
                    user: "postgres",
                    password: "postgres",
                    dbname: "postgres",
                    embeddingModelDims: 768,
                },
            },
            graphStore: {
                provider: "neo4j",
                config: {
                    url: process.env.NEO4J_URL || "bolt://localhost:8687",
                    username: process.env.NEO4J_USER || "neo4j",
                    password: process.env.NEO4J_PASSWORD || "mem0graph",
                },
            },
        };


        try {
            if (!Memory) throw new Error("Memory class not found from mem0ai/oss");
            this.memory = new Memory(this.config);
            this.connected = true;
        } catch (e) {
            console.error(`Error initializing Memory: ${e.message}`);
            this.memory = null;
            this.connected = false;
        }

    }

    prompt(question) {
        return new Promise((resolve) => {
            this.rl.question(question, (answer) => resolve(answer));
        });
    }

    normalizeMemoryInput(content) {
        if (content == null) return '';

        if (Array.isArray(content)) {
            return content
                .map((item) => {
                    if (typeof item === 'string') return item;
                    const text = item.content || item.message || item.memory || JSON.stringify(item);
                    const prefix = item.role ? `[${item.role}] ` : '';
                    return prefix + text;
                })
                .join('\n');
        }

        if (typeof content === 'object') {
            return content.content || content.message || content.memory || JSON.stringify(content);
        }

        return String(content);
    }

    async addMemory(newMem) {
        const content = this.normalizeMemoryInput(newMem).trim();
        if (!content) {
            throw new Error('Memory text cannot be empty.');
        }

        return await this.memory.add(content, {
            userId: this.userId,
            agentId: this.agentId,
        });
    }

    async getAllMemories() {
        console.log("\n--- Get All Memories ---");
        try {
            const result = await this.memory.getAll({
                filters: {
                    user_id: this.userId,
                    agent_id: this.agentId,
                },
            });

            const memories = Array.isArray(result)
                ? result
                : result?.results || [];

            if (memories.length > 0) {
                console.log(`Found ${memories.length} memories for Agent '${this.agentId}':`);
                memories.forEach((mem, i) => {
                    console.log(`\n${i + 1}. ID: ${mem.id}`);
                    console.log(`   Memory: ${mem.memory}`);
                    console.log(`   Created: ${mem.created_at || "N/A"}`);
                });
            } else {
                console.log(`No memories found for Agent '${this.agentId}'.`);
            }
        } catch (e) {
            console.error(`Error: ${e.message}`);
        }
    }

    async getMemory(memoryId) {
        if (!memoryId || !String(memoryId).trim()) {
            throw new Error('Memory ID cannot be empty.');
        }
        return await this.memory.get(memoryId);
    }

    async updateMemory(memoryId, newContent) {
        if (!memoryId || !String(memoryId).trim()) {
            throw new Error('Memory ID cannot be empty.');
        }
        const content = this.normalizeMemoryInput(newContent).trim();
        if (!content) {
            throw new Error('Memory content cannot be empty.');
        }
        return await this.memory.update(memoryId, content);
    }

    async deleteMemory(memoryId) {
        if (!memoryId || !String(memoryId).trim()) {
            throw new Error('Memory ID cannot be empty.');
        }
        return await this.memory.delete(memoryId);
    }

    async deleteAllMemories() {
        return await this.memory.deleteAll({
            filters: {
                user_id: this.userId,
                agent_id: this.agentId,
            },
        });
    }

    async searchMemories(query) {
        const searchText = this.normalizeMemoryInput(query).trim();
        if (!searchText) {
            throw new Error('Search query cannot be empty.');
        }

        const results = await this.memory.search(searchText, {
            filters: {
                user_id: this.userId,
                agent_id: this.agentId,
            },
        });

        return Array.isArray(results) ? results : results?.results || [];
    }

    async getMemoryHistory(memoryId) {
        //     if (!memoryId || !String(memoryId).trim()) {
        //         throw new Error('Memory ID cannot be empty.');
        //     }

        //     const result = await this.memory.history(memoryId);
        //     if (Array.isArray(result)) {
        //         return result;
        //     }
        //     if (result?.results) {
        //         return result.results;
        //     }
        // //     return result ? [result] : [];
        // // }
        //     console.log("\n--- Get Memory History ---");
        //     const memoryId = (await this.prompt("Enter memory ID: ")).trim();
        //     if (!memoryId) {
        //         console.log("Memory ID cannot be empty!");
        //         return;
        //     }

        //     try {
        //         const result = await this.memory.history(memoryId);
        //         let history = [];

        //         if (Array.isArray(result)) {
        //             history = result;
        //         } else if (result?.results) {
        //             history = result.results;
        //         } else if (result) {
        //             history = [result];
        //         }

        //         if (history.length === 0) {
        //             console.log("No history found for this memory.");
        //             return;
        //         }

        //         console.log(`\nHistory for memory ${memoryId}:`);
        //         history.forEach((entry, i) => {
        //             const action = entry.event || entry.action || entry.type || "N/A";
        //             const content = entry.new_memory || entry.memory || entry.old_memory || entry.content || "N/A";
        //             const timestamp = entry.created_at || entry.updated_at || "N/A";

        //             console.log(`\n${i + 1}. Action: ${action}`);
        //             console.log(`   Content: ${content}`);
        //             console.log(`   Timestamp: ${timestamp}`);
        //         });
        //     } catch (e) {
        //         console.error(`Error: ${e.message}`);
        //     }
    }

    async resetAllMemories() {
        return await this.memory.reset();
    }

    async setUserAndAgentId({ agentId, userId } = {}) {
        if (agentId) {
            this.agentId = agentId;
        }
        if (userId) {
            this.userId = userId;
        }
        return { agentId: this.agentId, userId: this.userId };
    }

    displayMenu() {
        const connectionStatus = this.connected ? "✓ Connected" : "✗ Disconnected";
        console.log("\n" + "=".repeat(50));
        console.log("      MEMORY MANAGEMENT SYSTEM");
        console.log("=".repeat(50));
        console.log(`Current User ID : ${this.userId}`);
        console.log(`Current Agent ID: ${this.agentId}`);
        console.log(`Status          : ${connectionStatus}`);
        console.log("-".repeat(50));
        console.log("1.  Add Memory");
        console.log("2.  Get All Memories");
        console.log("3.  Get Specific Memory");
        console.log("4.  Update Memory");
        console.log("5.  Delete Memory");
        console.log("6.  Delete All Memories");
        console.log("7.  Search Memories");
        console.log("8.  Get Memory History");
        console.log("9.  Reset All Memories");
        console.log("10. Change User & Agent ID");
        console.log("0.  Exit");
        console.log("-".repeat(50));
    }

    async run() {
        if (!this.connected) {
            console.log("\n✗ Cannot start - Memory not initialized.");
            console.log("Please ensure all services are running:");
            console.log("  - Gemini API key set in .env");
            console.log("  - PostgreSQL: localhost:8432");
            console.log("  - Neo4j: localhost:8687");
            return { connected: false };
        }

        // console.log("Memory connected.");
        // return { connected: true };
    


        while (true) {
            this.displayMenu();
            const choice = (await this.prompt("Select an option (0-10): ")).trim();

            if (choice === "0") {
                console.log("\n👋 Goodbye!");
                this.rl.close();
                break;
            }

            switch (choice) {
                case "1":
                    await this.addMemory();
                    break;
                case "2":
                    await this.getAllMemories();
                    break;
                case "3":
                    await this.getMemory();
                    break;
                case "4":
                    await this.updateMemory();
                    break;
                case "5":
                    await this.deleteMemory();
                    break;
                case "6":
                    await this.deleteAllMemories();
                    break;
                case "7":
                    await this.searchMemories();
                    break;
                case "8":
                    await this.getMemoryHistory();
                    break;
                case "9":
                    await this.resetAllMemories();
                    break;
                case "10":
                    await this.setUserAndAgentId();
                    break;
                default:
                    console.log("Invalid option. Please try again.");
            }
        }
    }
}


const ui = new MemoryUI("chat_history_agent", "default_user");
ui.run();

module.exports = { MemoryUI }