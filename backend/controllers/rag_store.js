const { MongoClient } = require('mongodb');
const fs = require('fs/promises');
const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

class RagStore {
    constructor(collectionName = 'dse_questions', options = {}) {
        this.collectionName = collectionName;
        this.mongoUri = process.env.MONGODB_URI;
        this.dbName = 'StashTag-Demo';
        this.searchIndex = 'autoembed_index';
        
        // When using autoEmbed, the textField and vectorField are usually the same indexed field
        this.textField = 'question_text';
        this.client = null;
        this.db = null;
        this.collection = null;
    }

    async init() {
        if (!this.mongoUri) {
            throw new Error('MONGODB_URI must be defined in environment variables.');
        }

        try {
            this.client = new MongoClient(this.mongoUri);
            await this.client.connect();
            this.db = this.client.db(this.dbName);
            this.collection = this.db.collection(this.collectionName);
            console.log(`MongoDB collection "${this.collectionName}" initialized on database "${this.dbName}".`);
        } catch (e) {
            console.error('Error initializing MongoDB collection:', e.message || e);
            throw e;
        }
    }

    async addDocumentsFromJson(jsonRelativePath, clearExisting = false) {
        if (!this.collection) {
            throw new Error('RagStore is not initialized. Call await ragStore.init() first.');
        }

        const jsonPath = path.resolve(__dirname, jsonRelativePath);
        const raw = await fs.readFile(jsonPath, 'utf8');
        const items = JSON.parse(raw);

        if (!Array.isArray(items)) {
            throw new Error('Expected JSON file to contain an array of objects.');
        }

        if (clearExisting) {
            try {
                await this.collection.deleteMany({});
                console.log(`Collection "${this.collectionName}" cleared.`);
            } catch (e) {
                console.warn('Could not clear existing collection:', e.message || e);
            }
        }

        const documents = items.map((item) => {
            const contentParts = [];
            if (item.question_text) contentParts.push(`Question: ${item.question_text}`);
            if (item.options) {
                const optionsStr = typeof item.options === 'object'
                    ? Object.entries(item.options).map(([k, v]) => `${k}: ${v}`).join(' | ')
                    : String(item.options);
                contentParts.push(`Options: ${optionsStr}`);
            }
            if (Array.isArray(item.keywords) && item.keywords.length > 0) {
                contentParts.push(`Keywords: ${item.keywords.join(', ')}`);
            }

            const text = contentParts.join('\n');

            const document = {
                source: jsonRelativePath,
                insertedAt: new Date(),
                text, // This is the field Atlas autoEmbeds based on your index definition
                question_text: item.question_text || '',
                options: item.options || null,
                keywords: Array.isArray(item.keywords) ? item.keywords : [],
                exam: item.exam || null,
                question_number: item.question_number ?? null,
            };

            if (item.id) {
                document._id = String(item.id);
            }

            return document;
        }).filter((doc) => doc.text);

        if (documents.length === 0) {
            return { added: 0 };
        }

        const bulkOps = documents.map((doc) => {
            if (doc._id) {
                return {
                    updateOne: {
                        filter: { _id: doc._id },
                        update: { $set: doc },
                        upsert: true,
                    },
                };
            }

            return {
                insertOne: {
                    document: doc,
                },
            };
        });

        await this.collection.bulkWrite(bulkOps, { ordered: false });
        console.log(`Successfully upserted ${documents.length} documents into MongoDB collection "${this.collectionName}".`);
        return { added: documents.length };
    }

    async query(queryText, nResults = 2) {
        if (!this.collection) {
            throw new Error('RagStore is not initialized. Call await ragStore.init() first.');
        }
        console.log("Querying...", queryText)
        // 1. Vector Search Pipeline with AutoEmbed
        const vectorSearchStage = {
            $vectorSearch: {
                index: this.searchIndex,
                path: this.textField,
                query: {
                    text: queryText
                },
                numCandidates: Math.max(nResults * 10, 20),
                limit: nResults
            }
        };

        try {
            const pipeline = [
                vectorSearchStage,
                {
                    $project: {
                        _id: 0,
                        score: { $meta: 'vectorSearchScore' },
                        document: '$$ROOT',
                    },
                },
            ];

            const results = await this.collection.aggregate(pipeline).toArray();

            if (results.length > 0) {

                return {
                    documents: results.map((item) => item.document),
                    metadatas: results.map((item) => ({ source: item.document.source })),
                    distances: results.map((item) => item.score),
                };
            }
        } catch (err) {
            console.warn('MongoDB autoEmbed vector search failed, falling back to text search:', err.message || err);
        }

        // 2. Fallback $search Pipeline (standard full-text search)
        const fallbackPipeline = [
            {
                $search: {
                    index: this.searchIndex,
                    text: {
                        query: queryText,
                        path: this.textField,
                    },
                },
            },
            { $limit: nResults },
            {
                $project: {
                    _id: 0,
                    score: { $meta: 'searchScore' },
                    document: '$$ROOT',
                },
            },
        ];

        const fallbackResults = await this.collection.aggregate(fallbackPipeline).toArray();
        return {
            documents: fallbackResults.map((item) => item.document),
            metadatas: fallbackResults.map((item) => ({ source: item.document.source })),
            distances: fallbackResults.map((item) => item.score),
        };
    }

    async deleteById(id) {
        if (!this.collection) return false;
        try {
            const result = await this.collection.deleteOne({ _id: id });
            return result.deletedCount === 1;
        } catch (e) {
            console.error('Error deleting ID from collection:', e.message || e);
            return false;
        }
    }

    async close() {
        if (this.client) {
            await this.client.close();
            this.client = null;
            this.db = null;
            this.collection = null;
        }
    }
}

module.exports = { RagStore };