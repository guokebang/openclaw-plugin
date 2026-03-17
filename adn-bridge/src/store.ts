import fs from "node:fs/promises";
import path from "node:path";

export interface TopicBinding {
  topicKey: string;   // "chatId:topicId"
  repo: string;       // "org/repo" or full git URL
  repoPath: string;   // local absolute path
  runtime: string;    // "claude" | "codex" | etc.
  boundAt: string;    // ISO timestamp
}

export class BindingStore {
  private filePath: string;
  private cache: Map<string, TopicBinding> | null = null;

  constructor(stateDir: string) {
    this.filePath = path.join(stateDir, "plugins", "adn-bridge", "bindings.json");
  }

  private async load(): Promise<Map<string, TopicBinding>> {
    if (this.cache) return this.cache;
    try {
      const raw = await fs.readFile(this.filePath, "utf8");
      const data = JSON.parse(raw) as Record<string, TopicBinding>;
      this.cache = new Map(Object.entries(data));
    } catch {
      this.cache = new Map();
    }
    return this.cache;
  }

  private async save(bindings: Map<string, TopicBinding>): Promise<void> {
    await fs.mkdir(path.dirname(this.filePath), { recursive: true });
    const obj = Object.fromEntries(bindings);
    await fs.writeFile(this.filePath, JSON.stringify(obj, null, 2) + "\n", "utf8");
    this.cache = bindings;
  }

  async get(topicKey: string): Promise<TopicBinding | null> {
    const bindings = await this.load();
    return bindings.get(topicKey) ?? null;
  }

  async set(binding: TopicBinding): Promise<void> {
    const bindings = await this.load();
    bindings.set(binding.topicKey, binding);
    await this.save(bindings);
  }

  async remove(topicKey: string): Promise<boolean> {
    const bindings = await this.load();
    const had = bindings.delete(topicKey);
    if (had) await this.save(bindings);
    return had;
  }

  async list(): Promise<TopicBinding[]> {
    const bindings = await this.load();
    return [...bindings.values()];
  }
}
