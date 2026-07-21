import { useState, useRef, useEffect } from "react";
import { Send, FileText, Loader2 } from "lucide-react";
import { askQuestion } from "../services/api";

export default function ChatBox() {
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const bottomRef = useRef(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const handleSend = async () => {
    const question = input.trim();
    if (!question || loading) return;

    setMessages((prev) => [...prev, { role: "user", text: question }]);
    setInput("");
    setLoading(true);

    try {
      const { data } = await askQuestion(question);
      setMessages((prev) => [...prev, { role: "assistant", ...data }]);
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        { role: "assistant", answer: "Something went wrong reaching the AI engine. Please try again.", confidence: 0, sources: [] },
      ]);
    } finally {
      setLoading(false);
    }
  };

  const confidenceColor = (score) => {
    if (score >= 0.75) return "text-emerald-600 bg-emerald-50";
    if (score >= 0.5) return "text-amber-600 bg-amber-50";
    return "text-red-600 bg-red-50";
  };

  return (
    <div className="flex flex-col h-[calc(100vh-4rem)]">
      <div className="flex-1 overflow-y-auto px-8 py-6 space-y-5">
        {messages.length === 0 && (
          <div className="text-center text-slate-400 mt-20">
            <p className="text-lg font-medium text-slate-500">Ask anything about your plant documents</p>
            <p className="text-sm mt-1">e.g. "How often should Pump P-102 be serviced?"</p>
          </div>
        )}

        {messages.map((msg, i) =>
          msg.role === "user" ? (
            <div key={i} className="flex justify-end">
              <div className="bg-emerald-600 text-white px-4 py-2.5 rounded-2xl rounded-br-sm max-w-xl text-sm">
                {msg.text}
              </div>
            </div>
          ) : (
            <div key={i} className="flex justify-start">
              <div className="bg-white border border-slate-200 rounded-2xl rounded-bl-sm max-w-2xl px-5 py-4 shadow-sm">
                <p className="text-slate-800 text-sm leading-relaxed whitespace-pre-wrap">{msg.answer}</p>

                {msg.confidence !== undefined && (
                  <span className={`inline-block mt-3 text-xs px-2 py-1 rounded-full font-medium ${confidenceColor(msg.confidence)}`}>
                    Confidence: {Math.round(msg.confidence * 100)}%
                  </span>
                )}

                {msg.sources?.length > 0 && (
                  <div className="mt-3 pt-3 border-t border-slate-100 space-y-2">
                    <p className="text-xs font-medium text-slate-500">Sources</p>
                    {msg.sources.map((s, j) => (
                      <div key={j} className="flex items-start gap-2 text-xs text-slate-500 bg-slate-50 rounded-lg px-3 py-2">
                        <FileText size={14} className="mt-0.5 shrink-0" />
                        <div>
                          <p className="text-slate-600">Doc #{s.document_id}{s.page_number ? `, page ${s.page_number}` : ""} · similarity {s.similarity}</p>
                          <p className="mt-0.5 italic text-slate-400">"{s.excerpt}..."</p>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )
        )}

        {loading && (
          <div className="flex items-center gap-2 text-slate-400 text-sm">
            <Loader2 size={16} className="animate-spin" /> PlantMind is thinking...
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      <div className="border-t border-slate-200 bg-white px-8 py-4">
        <div className="flex items-center gap-3 max-w-3xl mx-auto">
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleSend()}
            placeholder="Ask about SOPs, equipment, maintenance history..."
            className="flex-1 border border-slate-300 rounded-xl px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500/40 focus:border-emerald-500"
          />
          <button
            onClick={handleSend}
            disabled={loading}
            className="bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white rounded-xl p-3 transition-colors"
          >
            <Send size={18} />
          </button>
        </div>
      </div>
    </div>
  );
}
