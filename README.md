# 🌿 PlantMind AI — AI-Powered Industrial Knowledge Intelligence Platform

> **ET GenAI Hackathon 2.0 Submission**

PlantMind AI is an AI-powered industrial engineering copilot designed to help manufacturing plants, process industries, and maintenance teams instantly retrieve knowledge from technical documents, perform maintenance intelligence, monitor compliance, and generate professional reports.

Instead of manually searching through hundreds of SOPs, maintenance manuals, inspection reports, and compliance documents, PlantMind AI provides engineers with a single intelligent interface capable of understanding natural language questions and delivering contextual, source-backed responses.

---

# 🌐 Live Deployment

| Service                   | URL                                                                              |
| ------------------------- | -------------------------------------------------------------------------------- |
| **Frontend**              | [https://plantmind-ai-1.onrender.com](https://plantmind-ai-1.onrender.com)       |
| **Backend API**           | [https://plantmind-ai.onrender.com](https://plantmind-ai.onrender.com)           |
| **Swagger Documentation** | [https://plantmind-ai.onrender.com/docs](https://plantmind-ai.onrender.com/docs) |
| **Health Check**          | [https://plantmind-ai.onrender.com](https://plantmind-ai.onrender.com)           |

> **Note:** The application is hosted on **Render Free Tier**. After approximately **15 minutes of inactivity**, the backend automatically sleeps. The first request after inactivity may take **30–60 seconds** while the server wakes up.

---

# 📖 Project Overview

Industrial organizations generate enormous volumes of technical documentation throughout the lifecycle of machinery and operations.

These documents include:

* Standard Operating Procedures (SOPs)
* Equipment Manuals
* Maintenance Logs
* Inspection Reports
* Compliance Certificates
* Audit Documents
* Incident Reports
* Engineering Documentation

Although this information is valuable, engineers often spend considerable time locating the correct document, searching through hundreds of pages, and identifying relevant maintenance procedures.

PlantMind AI solves this problem by combining **Document Intelligence**, **Retrieval-Augmented Generation (RAG)**, and **Generative AI** into a single intelligent platform.

The system extracts information from uploaded industrial documents, indexes them using semantic embeddings, and enables engineers to ask technical questions in natural language while receiving grounded responses supported by document references.

---

# 🎯 Problem Statement

Industrial plants face several recurring challenges:

* Large volumes of unstructured documentation
* Slow information retrieval during maintenance
* Knowledge loss due to retiring experts
* Difficulty maintaining compliance records
* Time-consuming report generation
* Limited accessibility of engineering knowledge

PlantMind AI addresses these challenges through AI-powered document understanding and engineering assistance.

---

# ✨ Key Features

## 📂 Document Management

* Upload industrial documents
* Support for multiple file formats

  * PDF
  * DOCX
  * TXT
  * CSV
  * XLSX
  * Images
* Automatic document parsing
* OCR support for scanned documents
* Chunking and semantic indexing
* Document deletion and management

---

## 🤖 AI Engineering Copilot

Ask questions in natural language such as:

* What is the shutdown procedure?
* How often should Pump P-102 be serviced?
* What PPE is required before maintenance?
* Explain the lubrication procedure.

The AI:

* Retrieves relevant document chunks
* Understands engineering context
* Generates grounded answers
* Returns confidence scores
* Displays supporting document excerpts

---

## 🔍 Retrieval-Augmented Generation (RAG)

The AI never relies solely on the language model.

Instead it:

1. Retrieves relevant document chunks
2. Builds contextual prompts
3. Uses an LLM to synthesize answers
4. Returns document-backed responses

This significantly reduces hallucinations and improves answer reliability.

---

## 🛠 Maintenance Intelligence

The maintenance module provides:

* Equipment health overview
* Predictive maintenance alerts
* Failure trend visualization
* Root Cause Analysis support

This allows engineers to monitor plant equipment proactively.

---

## 🛡 Compliance Intelligence

Monitor engineering compliance through:

* Missing documentation detection
* Expired certification alerts
* Equipment-wise compliance status
* Plant-wide compliance dashboard

---

## 📑 AI Report Generator

Automatically generate professional reports including:

* Maintenance Reports
* Incident Reports
* Executive Reports
* Equipment Reports
* Audit Reports

Supported export formats:

* PDF
* DOCX

---

## 📊 Analytics Dashboard

Centralized dashboard displaying:

* Uploaded documents
* Equipment statistics
* Compliance metrics
* Maintenance alerts
* AI activity summary

---

# 🧠 AI Workflow

```
User Uploads Document
           │
           ▼
Document Parsing
(PDF / DOCX / Images)
           │
           ▼
OCR (if required)
           │
           ▼
Text Chunking
           │
           ▼
Semantic Embeddings
           │
           ▼
FAISS Vector Database
           │
           ▼
User asks Question
           │
           ▼
Semantic Retrieval
           │
           ▼
LLM (Gemini/OpenAI Compatible)
           │
           ▼
Grounded Response + Confidence + Sources
```

---

# ⚙️ Technology Stack

## Frontend

* React.js
* Vite
* Tailwind CSS
* React Router
* Axios
* Recharts

---

## Backend

* FastAPI
* Python
* SQLAlchemy
* Pydantic
* Uvicorn

---

## AI & Machine Learning

* Google Gemini API
* FAISS Vector Search
* Retrieval-Augmented Generation (RAG)
* Semantic Embeddings

---

## Document Processing

* PyMuPDF
* python-docx
* Pandas
* OpenPyXL
* Pillow
* Tesseract OCR

---

## Database

Development:

* SQLite

Production:

* PostgreSQL

---

## Deployment

* Render Static Site
* Render Web Service

---

# 📁 Project Structure

```
PlantMind-AI
│
├── frontend
│   ├── public
│   └── src
│       ├── assets
│       ├── components
│       ├── pages
│       ├── services
│       └── App.jsx
│
├── backend
│   ├── app
│   │   ├── api
│   │   ├── database
│   │   ├── services
│   │   ├── models
│   │   ├── config.py
│   │   └── main.py
│   │
│   └── requirements.txt
│
├── data
│   ├── uploads
│   ├── vectorstore
│   └── reports
│
└── README.md
```

---

# 📡 REST API

## Document APIs

| Method | Endpoint                |
| ------ | ----------------------- |
| POST   | `/api/documents/upload` |
| GET    | `/api/documents`        |
| DELETE | `/api/documents/{id}`   |

---

## AI Copilot

| Method | Endpoint          |
| ------ | ----------------- |
| POST   | `/api/chat/query` |

---

## Maintenance

| Method | Endpoint                               |
| ------ | -------------------------------------- |
| GET    | `/api/maintenance/health-overview`     |
| GET    | `/api/maintenance/predictive-alerts`   |
| GET    | `/api/maintenance/failure-trends`      |
| POST   | `/api/maintenance/root-cause-analysis` |

---

## Compliance

| Method | Endpoint                          |
| ------ | --------------------------------- |
| GET    | `/api/compliance/dashboard`       |
| GET    | `/api/compliance/equipment/{tag}` |

---

## Reports

| Method | Endpoint                           |
| ------ | ---------------------------------- |
| POST   | `/api/reports/generate`            |
| GET    | `/api/reports/download/{filename}` |

---

# 🚀 Local Installation

## Backend

```bash
cd backend

python -m venv venv

pip install -r requirements.txt

uvicorn app.main:app --reload
```

---

## Frontend

```bash
cd frontend

npm install

npm run dev
```

---

# 📌 Demo Workflow

### Step 1

Open the application.

---

### Step 2

Navigate to **Documents**.

Upload one or more industrial documents.

Supported formats:

* PDF
* DOCX
* TXT
* CSV
* XLSX
* Images

---

### Step 3

Wait until processing completes.

The backend:

* extracts text
* performs OCR (if required)
* creates semantic chunks
* stores embeddings
* indexes documents

---

### Step 4

Navigate to **AI Copilot**.

Ask engineering questions like:

> What is the startup procedure?

> How often should Pump P-102 be serviced?

> What PPE is required?

---

### Step 5

Explore **Maintenance Intelligence**.

View:

* Equipment health
* Maintenance alerts
* Failure trends
* Root Cause Analysis

---

### Step 6

Visit **Compliance Dashboard**.

Review:

* Compliance status
* Missing documentation
* Equipment certifications

---

### Step 7

Generate engineering reports.

Download:

* PDF
* DOCX

---

# 🔒 Reliability

PlantMind AI is designed to minimize AI hallucinations by using a Retrieval-Augmented Generation (RAG) pipeline. Instead of generating answers from model memory alone, it retrieves the most relevant document chunks from the indexed knowledge base and uses them as context for the language model. Every response is accompanied by a confidence score and supporting document excerpts, making the system more transparent and suitable for engineering use cases.

---

# 🌟 Future Enhancements

* Voice-enabled engineering assistant
* Multi-language document understanding
* IoT sensor integration
* Digital Twin integration
* ERP/CMMS connectivity (SAP PM, IBM Maximo)
* Knowledge graph visualization
* Mobile application
* Role-Based Access Control (RBAC)
* Real-time predictive maintenance
* Edge AI deployment

---

# 👨‍💻 Developed By

**Aaryan Verma**

**ET GenAI Hackathon 2.0 Submission**

GitHub: [https://github.com/AaryanVerma17](https://github.com/AaryanVerma17)

LinkedIn: [https://www.linkedin.com/in/aaryanverma2007](https://www.linkedin.com/in/aaryanverma2007)

---

# 📌 Note for Evaluators

This project demonstrates an end-to-end AI-powered industrial knowledge platform integrating document intelligence, semantic search, Retrieval-Augmented Generation (RAG), maintenance analytics, compliance monitoring, and automated report generation. The application is deployed on Render's free tier; therefore, the first request after a period of inactivity may take up to a minute while the backend service wakes up. Subsequent interactions are significantly faster.
