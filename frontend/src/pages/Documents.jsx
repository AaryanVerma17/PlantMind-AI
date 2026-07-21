import { useEffect, useState } from "react";
import Navbar from "../components/Navbar";
import UploadCard from "../components/UploadCard";
import { listDocuments, deleteDocument } from "../services/api";
import { Trash2, FileText, RefreshCw } from "lucide-react";

const statusStyles = {
  ready: "bg-emerald-50 text-emerald-700",
  processing: "bg-amber-50 text-amber-700",
  failed: "bg-red-50 text-red-700",
};

export default function Documents() {
  const [docs, setDocs] = useState([]);
  const [loading, setLoading] = useState(true);

  const fetchDocs = async () => {
    setLoading(true);
    try {
      const { data } = await listDocuments();
      setDocs(data);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchDocs();
    const interval = setInterval(fetchDocs, 5000);
    return () => clearInterval(interval);
  }, []);

  const handleDelete = async (id) => {
    if (!confirm("Delete this document and its indexed chunks?")) return;
    await deleteDocument(id);
    fetchDocs();
  };

  return (
    <div>
      <Navbar title="Document Management" />
      <div className="p-8 grid grid-cols-3 gap-6">
        <div className="col-span-1">
          <UploadCard onUploaded={fetchDocs} />
        </div>

        <div className="col-span-2 bg-white border border-slate-200 rounded-2xl shadow-sm">
          <div className="flex items-center justify-between px-6 py-4 border-b border-slate-100">
            <h3 className="font-semibold text-slate-800">All Documents ({docs.length})</h3>
            <button onClick={fetchDocs} className="text-slate-400 hover:text-slate-600">
              <RefreshCw size={16} className={loading ? "animate-spin" : ""} />
            </button>
          </div>

          <div className="divide-y divide-slate-100 max-h-[600px] overflow-y-auto">
            {docs.length === 0 && !loading && (
              <p className="text-sm text-slate-400 text-center py-10">No documents uploaded yet.</p>
            )}
            {docs.map((doc) => (
              <div key={doc.id} className="flex items-center justify-between px-6 py-3.5">
                <div className="flex items-center gap-3 min-w-0">
                  <FileText size={18} className="text-slate-400 shrink-0" />
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-slate-800 truncate">{doc.name}</p>
                    <p className="text-xs text-slate-400">
                      {doc.category} {doc.equipment_tag && `· ${doc.equipment_tag}`} · {doc.chunks} chunks
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-3 shrink-0">
                  <span className={`text-xs px-2 py-1 rounded-full font-medium ${statusStyles[doc.status]}`}>
                    {doc.status}
                  </span>
                  <button onClick={() => handleDelete(doc.id)} className="text-slate-400 hover:text-red-500">
                    <Trash2 size={16} />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
