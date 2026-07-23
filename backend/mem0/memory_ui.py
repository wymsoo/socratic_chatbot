"""
Simple User Interface for Memory Management
Provides interactive menu-driven access to memory operations
"""

from mem0 import Memory
import json
from typing import Optional, Dict, Any
from datetime import datetime

class MemoryUI:
    """Interactive UI for managing memories scoped by agent_id and user_id"""
    
    def __init__(self, agent_id: str, user_id: str = "default_user"):
        self.user_id = user_id
        self.agent_id = agent_id

        # Initialize Memory with ollama configuration
        self.config = {
            "llm": {
                "provider": "ollama",
                "config": {
                    "model": "llama3.1",
                    "temperature": 0,
                    "max_tokens": 2000,
                    "ollama_base_url": "http://localhost:11434",
                },
            },
            "embedder": {
                "provider": "ollama",
                "config": {
                    "model": "nomic-embed-text:latest",
                    "ollama_base_url": "http://localhost:11434",
                },
            },
            "vector_store": {
                "provider": "pgvector",
                "config": {
                    "host": "localhost",
                    "port": 8432,
                    "user": "postgres",
                    "password": "postgres",
                    "dbname": "postgres",
                    "embedding_model_dims": 768,
                },
            },
            "graph_store": {
                "provider": "neo4j",
                "config": {
                    "url": "bolt://localhost:8687",
                    "username": "neo4j",
                    "password": "mem0graph",
                },
            },
        }
        
        try:
            self.memory = Memory.from_config(self.config)
            self.connected = True
        except Exception as e:
            print(f"Error: Could not initialize Memory: {str(e)}")
            self.memory = None
            self.connected = False
    
    def add_memory(self, new_mem="manual"):
        """Add a new memory scoped to the current user and agent"""
        if new_mem == "manual":
            new_mem = input("Enter memory text: ").strip()
        if not new_mem:
            print("Memory text cannot be empty!")
            return
        
        try:
            result = self.memory.add(new_mem, user_id=self.user_id, agent_id=self.agent_id)
            print("✓ Memory added successfully!")
            if isinstance(result, dict) and "results" in result:
                for r in result["results"]:
                    print(f"  [{r.get('event')}] {r.get('memory')}")
        except Exception as e:
            print(f"Error: {str(e)}")
    
    def get_all_memories(self):
        """Retrieve all memories for the active user and agent"""
        print("\n--- Get All Memories ---")
        try:
            result = self.memory.get_all(filters={"user_id": self.user_id, "agent_id": self.agent_id})
            if result:
                memories = result.get("results", []) if isinstance(result, dict) else result
                if memories:
                    print(f"Found {len(memories)} memories for Agent '{self.agent_id}':")
                    for i, mem in enumerate(memories, 1):
                        print(f"\n{i}. ID: {mem.get('id')}")
                        print(f"   Memory: {mem.get('memory')}")
                        print(f"   Created: {mem.get('created_at', 'N/A')}")
                else:
                    print(f"No memories found for Agent '{self.agent_id}'.")
        except Exception as e:
            print(f"Error: {str(e)}")
    
    def get_memory(self):
        """Retrieve a specific memory"""
        print("\n--- Get Specific Memory ---")
        memory_id = input("Enter memory ID: ").strip()
        if not memory_id:
            print("Memory ID cannot be empty!")
            return
        
        try:
            result = self.memory.get(memory_id)
            if result:
                print(f"\nMemory ID: {result.get('id')}")
                print(f"Content: {result.get('memory')}")
                print(f"Created: {result.get('created_at', 'N/A')}")
        except Exception as e:
            print(f"Error: {str(e)}")
    
    def update_memory(self):
        """Update an existing memory"""
        print("\n--- Update Memory ---")
        memory_id = input("Enter memory ID: ").strip()
        if not memory_id:
            print("Memory ID cannot be empty!")
            return
        
        new_content = input("Enter new memory content: ").strip()
        if not new_content:
            print("Memory content cannot be empty!")
            return
        
        try:
            result = self.memory.update(memory_id, new_content)
            if result:
                print("✓ Memory updated successfully!")
        except Exception as e:
            print(f"Error: {str(e)}")
    
    def delete_memory(self):
        """Delete a specific memory"""
        print("\n--- Delete Memory ---")
        memory_id = input("Enter memory ID: ").strip()
        if not memory_id:
            print("Memory ID cannot be empty!")
            return
        
        confirm = input(f"Delete memory {memory_id}? (yes/no): ").strip().lower()
        if confirm != "yes":
            print("Cancelled.")
            return
        
        try:
            result = self.memory.delete(memory_id)
            if result:
                print("✓ Memory deleted successfully!")
        except Exception as e:
            print(f"Error: {str(e)}")
    
    def delete_all_memories(self):
        """Delete all memories ONLY for this agent and user"""
        print(f"\n--- Delete All Memories for Agent '{self.agent_id}' ---")
        confirm = input(f"This will delete ALL memories for agent '{self.agent_id}'. Continue? (yes/no): ").strip().lower()
        if confirm != "yes":
            print("Cancelled.")
            return
        
        try:
            # Scoped to user_id AND agent_id so other agents' memories are safe
            result = self.memory.delete_all(user_id=self.user_id, agent_id=self.agent_id)
            if result:
                print(f"✓ All memories for agent '{self.agent_id}' deleted successfully!")
        except Exception as e:
            print(f"Error: {str(e)}")
    
    def search_memories(self, query="manual"):
        """Search memories scoped to this specific agent"""
        if query == "manual":
            query = input("Enter search query: ").strip()
        if not query:
            print("Query cannot be empty!")
            return
        
        try:
            # Filter search strictly by user_id and agent_id
            results = self.memory.search(
                query, 
                filters={"user_id": self.user_id, "agent_id": self.agent_id}
            )
            if results:
                result_list = results.get("results", []) if isinstance(results, dict) else results
                if result_list:
                    if query != "manual":
                        return result_list[:3].get('memory')
                    
                    print(f"\nFound {len(result_list)} results:")
                    for i, res in enumerate(result_list, 1):
                        score = res.get('score', 0)
                        print(f"\n{i}. Memory: {res.get('memory')}")
                        print(f"   Score: {score:.2f}")
                else:
                    print("No memories found matching your search.")
        except Exception as e:
            print(f"Error: {str(e)}")
    
    def get_memory_history(self):
        """Get memory history"""
        print("\n--- Get Memory History ---")
        memory_id = input("Enter memory ID: ").strip()
        if not memory_id:
            print("Memory ID cannot be empty!")
            return
        
        try:
            result = self.memory.history(memory_id)

            history = []
            if result is None:
                history = []
            elif isinstance(result, dict):
                history = result.get("results") if "results" in result else [result]
            elif isinstance(result, list):
                history = result
            else:
                try:
                    history = json.loads(result)
                    if not isinstance(history, list):
                        history = [history]
                except Exception:
                    history = [result]

            if not history:
                print("No history found for this memory.")
                return

            print(f"\nHistory for memory {memory_id}:")
            for i, entry in enumerate(history, 1):
                action = entry.get("event") or entry.get("action") or entry.get("type") or "N/A"
                content = (
                    entry.get("new_memory")
                    or entry.get("memory")
                    or entry.get("old_memory")
                    or entry.get("content")
                    or "N/A"
                )
                timestamp = entry.get("created_at") or entry.get("updated_at") or "N/A"

                print(f"\n{i}. Action: {action}")
                print(f"   Content: {content}")
                print(f"   Timestamp: {timestamp}")
        except Exception as e:
            print(f"Error: {str(e)}")
    
    def reset_all_memories(self):
        """Reset all memories in the system"""
        print("\n--- Reset Entire System Memories ---")
        confirm = input("WARNING: This will reset ALL database memories across ALL agents. Continue? (yes/no): ").strip().lower()
        if confirm != "yes":
            print("Cancelled.")
            return
        
        try:
            result = self.memory.reset()
            if result:
                print("✓ All system memories reset successfully!")
        except Exception as e:
            print(f"Error: {str(e)}")
    
    def set_user_and_agent_id(self):
        """Set the active User ID and Agent ID"""
        print("\n--- Update Scope ---")
        new_agent_id = input(f"Enter Agent ID (current: {self.agent_id}): ").strip()
        if new_agent_id:
            self.agent_id = new_agent_id
            print(f"✓ Agent ID updated to: {self.agent_id}")
            
        new_user_id = input(f"Enter User ID (current: {self.user_id}): ").strip()
        if new_user_id:
            self.user_id = new_user_id
            print(f"✓ User ID updated to: {self.user_id}")

    def run(self):
        """Run the interactive menu"""
        if not self.connected:
            print("\n✗ Cannot start - Memory not initialized.")
            print("Please ensure all services are running:")
            print("  - Ollama: http://localhost:11434")
            print("  - PostgreSQL: localhost:8432")
            print("  - Neo4j: localhost:8687")
            return
        
        # print("\n🚀 Welcome to Memory Management System!")
        
        



if __name__ == "__main__":
    ui = MemoryUI(user_id="default_user",agent_id="chat_history_agent")
    ui.run()
    """Display main menu"""
    connection_status = "✓ Connected" if ui.connected else "✗ Disconnected"
    print("\n" + "="*50)
    print("      MEMORY MANAGEMENT SYSTEM")
    print("="*50)
    print(f"Current User ID: {ui.user_id}")
    print(f"Status: {connection_status}")
    print("-"*50)
    print("1.  Add Memory")
    print("2.  Get All Memories")
    print("3.  Get Specific Memory")
    print("4.  Update Memory")
    print("5.  Delete Memory")
    print("6.  Delete All Memories")
    print("7.  Search Memories")
    print("8.  Get Memory History")
    print("9.  Reset All Memories")
    print("10. Change User ID")
    print("0.  Exit")
    print("-"*50)
    menu_options = {
        "1": ui.add_memory,
        "2": ui.get_all_memories,
        "3": ui.get_memory,
        "4": ui.update_memory,
        "5": ui.delete_memory,
        "6": ui.delete_all_memories,
        "7": ui.search_memories,
        "8": ui.get_memory_history,
        "9": ui.reset_all_memories,
        # "10": ui.set_user_id,
    }
    while True:
        choice = input("Select an option (0-10): ").strip()
        
        if choice == "0":
            print("\n👋 Goodbye!")
            break
        elif choice in menu_options:
            try:
                menu_options[choice]()
            except KeyboardInterrupt:
                print("\n\nOperation cancelled.")
            except Exception as e:
                print(f"Unexpected error: {str(e)}")
        else:
            print("Invalid option. Please try again.")
    

