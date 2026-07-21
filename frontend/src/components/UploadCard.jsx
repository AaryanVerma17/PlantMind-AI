import { useState, useRef } from "react";
import { UploadCloud, Loader2, CheckCircle2 } from "lucide-react";
import { uploadDocument } from "../services/api";

const CATEGORIES = ["SOP", "Manual", "Inspection Report", "Incident Report", "Audit", "Drawing", "Vendor Doc"];

export default function UploadCard({ onUploaded }) {
  const [dragActive, setDragActive] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [category, setCategory] = useState(CATEGORIES[0]);
  const [equipmentTag, setEquipmentTag] = useState("");
  const [success, setSuccess] = useState(false);
  const inputRef = useRef(null);

  const handleFile = async (file) => {
    if (!file) return;
    setUploading(true);
    setSuccess(false);
    try {
      await uploadDocument(file, category, equipmentTag);
      setSuccess(true);
      setEquipmentTag("");
      onUploaded?.();
    } catch (err) {
      alert(err.response?.data?.detail || "Upload failed.");
    } finally {
      setUploading(false);
      setTimeout(() => setSuccess(false), 2500);
    }
  };

  return (
    <div className="bg-white border border-slate-200 rounded-2xl p-6 shadow-sm">
      <h3 className="font-semibold text-slate-800 mb-4">Upload Document</h3>

      <div className="grid grid-cols-2 gap-3 mb-4">
        <select
          value={category}
          onChange={(e) => setCategory(e.target.value)}
          className="border border-slate-300 rounded-lg px-3 py-2 text-sm"
        >
          {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
        </select>
        <input
          value={equipmentTag}
          onChange={(e) => setEquipmentTag(e.target.value)}
          placeholder="Equipment tag (optional)"
          className="border border-slate-300 rounded-lg px-3 py-2 text-sm"
        />
      </div>

      <div
        onDragOver={(e) => { e.preventDefault(); setDragActive(true); }}
        onDragLeave={() => setDragActive(false)}
        onDrop={(e) => {
          e.preventDefault();
          setDragActive(false);
          handleFile(e.dataTransfer.files[0]);
        }}
        onClick={() => inputRef.current?.click()}
        className={`border-2 border-dashed rounded-xl py-10 flex flex-col items-center justify-center cursor-pointer transition-colors ${
          dragActive ? "border-emerald-500 bg-emerald-50" : "border-slate-300 hover:border-slate-400"
        }`}
      >
        <input
          ref={inputRef}
          type="file"
          hidden
          accept=".pdf,.docx,.txt,.csv,.xlsx,.png,.jpg,.jpeg"
          onChange={(e) => handleFile(e.target.files[0])}
        />
        {uploading ? (
          <Loader2 className="animate-spin text-emerald-600" size={28} />
        ) : success ? (
          <CheckCircle2 className="text-emerald-600" size={28} />
        ) : (
          <UploadCloud className="text-slate-400" size={28} />
        )}
        <p className="text-sm text-slate-500 mt-3">
          {uploading ? "Processing..." : success ? "Uploaded successfully" : "Drag & drop or click to upload"}
        </p>
        <p className="text-xs text-slate-400 mt-1">PDF, DOCX, TXT, CSV, XLSX, PNG, JPG</p>
      </div>
    </div>
  );
}
