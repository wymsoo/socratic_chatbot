let Memory;
const mem0 = require("mem0ai/oss");
Memory = mem0.Memory;

const dotenv = require("dotenv");
// Load environment variables from .env file
dotenv.config();

class MemoryUI {
    constructor(agentId, userId = "default_user") {
        this.userId = userId;
        this.agentId = agentId;
        this.connected = false;

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
                    apiKey:process.env.GOOGLE_API_KEY || '',
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
                    password:"postgres",
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


    async setUserAndAgentId({ agentId, userId } = {}) {
        if (agentId) {
            this.agentId = agentId;
        }
        if (userId) {
            this.userId = userId;
        }
        return { agentId: this.agentId, userId: this.userId };
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

        console.log("Memory connected.");
        return { connected: true };
    }
}


module.exports = { MemoryUI }