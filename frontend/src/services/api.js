import axios from "axios";

const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:8000";

const api = axios.create({
  baseURL: API_BASE,
  headers: { "Content-Type": "application/json" },
});

export const uploadDocument = (file, category, equipmentTag) => {
  const formData = new FormData();
  formData.append("file", file);
  formData.append("category", category || "uncategorized");
  if (equipmentTag) formData.append("equipment_tag", equipmentTag);
  return api.post("/api/documents/upload", formData, {
    headers: { "Content-Type": "multipart/form-data" },
  });
};
export const listDocuments = () => api.get("/api/documents/");
export const deleteDocument = (id) => api.delete(`/api/documents/${id}`);

export const askQuestion = (question, topK = 5) =>
  api.post("/api/chat/query", { question, top_k: topK });

export const getHealthOverview = () => api.get("/api/maintenance/health-overview");
export const getPredictiveAlerts = (lookaheadDays = 30) =>
  api.get(`/api/maintenance/predictive-alerts?lookahead_days=${lookaheadDays}`);
export const getFailureTrends = (equipmentTag) =>
  api.get("/api/maintenance/failure-trends", { params: { equipment_tag: equipmentTag } });
export const runRootCauseAnalysis = (incidentDescription) =>
  api.post("/api/maintenance/root-cause-analysis", { incident_description: incidentDescription });

export const getComplianceDashboard = () => api.get("/api/compliance/dashboard");
export const getEquipmentCompliance = (equipmentTag, equipmentCategory) =>
  api.get(`/api/compliance/equipment/${equipmentTag}`, { params: { equipment_category: equipmentCategory } });

export const generateReport = (payload) => api.post("/api/reports/generate", payload);

export default api;
