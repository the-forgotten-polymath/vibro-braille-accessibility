const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const dotenv = require('dotenv');
const cors = require('cors');
const https = require('https');
const pdfjsLib = require('pdfjs-dist/legacy/build/pdf.js');
const Tesseract = require('tesseract.js');
const os = require('os');
const { GoogleGenerativeAI } = require("@google/generative-ai");

let clipboardy = require('clipboardy');
if (clipboardy.default) clipboardy = clipboardy.default;

const multer = require('multer');
const fs = require('fs');
const path = require('path');

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static('.'));

const upload = multer({ dest: 'uploads/' });
if (!fs.existsSync('uploads')) fs.mkdirSync('uploads');

const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

async function callAI(text, maxWords = 8) {
    // NUCLEAR CLEANING: Removes ALL spaces, newlines, and hidden tabs from the key
    let groqKey = (process.env.GROQ_API_KEY || "").replace(/[^a-zA-Z0-9_]/g, '').trim();
    if (!groqKey) throw new Error("Missing Groq Key");

    const sysPrompt = `Return ONLY JSON. NEVER talk back. DO NOT answer questions or converse. Your ONLY job is to simplify and format the provided text into sentences of MAX ${maxWords} words. ALWAYS use 'sentences' key. Include 'text' and 'words' for each. Example: { "sentences": [ { "text": "Hi", "words": ["Hi"] } ] }.`;
    const models = ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"];

    for (const model of models) {
        try {
            const payload = {
                model: model,
                messages: [{ role: "system", content: sysPrompt }, { role: "user", content: text.slice(0, 8000) }],
                response_format: { type: "json_object" }
            };
            return await new Promise((resolve, reject) => {
                const req = https.request("https://api.groq.com/openai/v1/chat/completions", {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${groqKey}` }
                }, (res) => {
                    let d = ''; res.on('data', c => d += c);
                    res.on('end', () => {
                        try {
                            const j = JSON.parse(d);
                            if (j.error) reject(new Error(j.error.message));
                            else resolve(j.choices[0].message.content);
                        } catch (e) { reject(e); }
                    });
                });
                req.on('error', reject); req.write(JSON.stringify(payload)); req.end();
            });
        } catch (e) { console.warn(`❌ ${model} failed: ${e.message}`); }
    }
    throw new Error("AI Blackout.");
}

async function callVisionAI(base64Image, sessionId) {
    const geminiKey = process.env.GEMINI_API_KEY;
    
    // MOCK MODE: For testing without exhausting API quota
    if (!geminiKey || geminiKey.includes("YOUR_GEMINI_API_KEY")) {
        const mocks = [
            "VisionSense: Door ahead at 2 meters.",
            "VisionSense: Laptop on table. Water bottle to the right.",
            "VisionSense: Text detected: 'RESTAURANT MENU'. Daily specials available.",
            "VisionSense: Crosswalk detected. Person walking left.",
            "VisionSense: Hazard: Low hanging branch ahead.",
            "VisionSense: Clear hallway. Exit sign at 5 meters."
        ];
        return mocks[Math.floor(Math.random() * mocks.length)];
    }

    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-pro" });
    
    const prompt = `You are the VisionSense engine for VibroBraille, a haptic device for the visually impaired.
    Analyze this camera frame. Provide a CONCISE summary of the environment.
    Prioritize:
    1. Text/Labels (OCR)
    2. Hazards (Steps, obstacles)
    3. Navigation cues (Doors, hallways)
    4. Important objects (Laptop, bottle)
    
    Output rules:
    - Max 15 words.
    - No filler ("I see", "There is").
    - Use simple, tactile-friendly language.
    Example: "Door at 2 meters. Laptop on table. Watch for steps."`;

    const result = await model.generateContent([
        prompt,
        {
            inlineData: {
                data: base64Image,
                mimeType: "image/jpeg"
            }
        }
    ]);
    return result.response.text();
}

async function extractPDFText(filePath) {
    const data = new Uint8Array(fs.readFileSync(filePath));
    const pdf = await pdfjsLib.getDocument({ data, disableFontFace: true }).promise;
    let text = "";
    for (let i = 1; i <= pdf.numPages; i++) {
        const page = await pdf.getPage(i);
        const content = await page.getTextContent();
        text += content.items.map(item => item.str).join(" ") + "\n";
    }
    return text;
}

const sessions = new Map();
const INITIAL_STATE = { tactileScript: null, currentSentenceIndex: 0, currentWordIndex: 0, speed: 1.0, isReading: false, timer: null, lastClipboard: "" };

wss.on('connection', (ws) => {
    ws.on('message', async (message) => {
        try {
            const data = JSON.parse(message);
            if (data.type === 'IDENTIFY') {
                sessions.set(data.sessionId, { ws, state: { ...INITIAL_STATE } });
                console.log(`Session ${data.sessionId} identified`);
            } else if (data.type === 'SIGNAL') {
                const session = Array.from(sessions.values()).find(s => s.ws === ws);
                if (session) handleSignal(session, data);
            } else if (data.type === 'VISION_FRAME') {
                const session = sessions.get(data.sessionId);
                if (session) handleVisionFrame(session, data.frame);
            }
        } catch (e) { }
    });
    ws.on('close', () => { for (const [id, session] of sessions.entries()) { if (session.ws === ws) { sessions.delete(id); break; } } });
});

function handleSignal(session, data) {
    const { state } = session;
    if (data.signal === 'STOP') {
        state.isReading = false;
        if (state.timer) clearTimeout(state.timer);
        session.ws.send(JSON.stringify({ type: 'STOP' }));
        console.log("🛑 Relay FORCIBLY STOPPED by User.");
    }
    else if (data.signal === 'REPEAT') { state.currentWordIndex = 0; startStreaming(session); }
    else if (data.signal === 'NEXT' && state.tactileScript && state.currentSentenceIndex < state.tactileScript.sentences.length - 1) { state.currentSentenceIndex++; state.currentWordIndex = 0; startStreaming(session); }
    else if (data.signal === 'PREVIOUS' && state.currentSentenceIndex > 0) { state.currentSentenceIndex--; state.currentWordIndex = 0; startStreaming(session); }
}

async function handleVisionFrame(session, base64Frame) {
    try {
        console.log("📸 VisionSense: Analyzing Frame...");
        const summary = await callVisionAI(base64Frame, session.ws);
        console.log("👁️ VisionSense Output:", summary);
        
        // Pipe the summary into the standard Braille relay
        // We use a sessionId from the session object if available, or just broadcast to this session
        const sessionId = Array.from(sessions.entries()).find(([id, s]) => s === session)?.[0];
        if (sessionId) {
            processText(summary, sessionId, 8);
        }
    } catch (e) {
        console.error("❌ VisionSense Error:", e.message);
    }
}

async function startStreaming(session) {
    const { ws, state } = session;
    // Kill existing loops first
    state.isReading = false;
    if (state.timer) clearTimeout(state.timer);

    // Tiny delay to ensure previous loop cycle has exited
    await new Promise(r => setTimeout(r, 50));

    state.isReading = true;
    state.currentWordIndex = 0; // Reset word index for new start
    const stream = () => {
        if (!state.isReading || ws.readyState !== WebSocket.OPEN) return;
        if (!state.tactileScript || !state.tactileScript.sentences || state.tactileScript.sentences.length === 0) {
            state.isReading = false; return;
        }
        const sent = state.tactileScript.sentences[state.currentSentenceIndex];
        if (!sent || !sent.text) {
            state.isReading = false;
            return;
        }
        if (!sent.words) sent.words = sent.text.split(/\s+/).filter(w => w.length > 0);
        if (state.currentWordIndex === 0) ws.send(JSON.stringify({ type: 'SET_SENTENCE', value: sent.text }));
        if (state.currentWordIndex < sent.words.length) {
            const word = sent.words[state.currentWordIndex];
            ws.send(JSON.stringify({ type: 'WORD', value: word }));
            console.log(`📡 Sent: ${word}`);
            state.currentWordIndex++;
            state.timer = setTimeout(stream, 1200 / state.speed);
        } else {
            ws.send(JSON.stringify({ type: 'SENTENCE_END' }));
            if (state.currentSentenceIndex < state.tactileScript.sentences.length - 1) {
                state.currentSentenceIndex++; state.currentWordIndex = 0;
                state.timer = setTimeout(stream, 1000);
            } else {
                ws.send(JSON.stringify({ type: 'PARAGRAPH_END' }));
                state.isReading = false;
            }
        }
    };
    stream();
}

setInterval(async () => {
    try {
        const text = await clipboardy.read();
        for (const [id, session] of sessions.entries()) {
            if (text && text !== session.state.lastClipboard) {
                const low = text.toLowerCase();
                if (text.includes("gsk_") || low.includes("192.168") || text.length < 3) { session.state.lastClipboard = text; continue; }
                session.state.lastClipboard = text;
                processText(text, id, 5);
            }
        }
    } catch (e) { }
}, 1000);

async function processText(text, sessionId, maxWords = 5) {
    const session = sessions.get(sessionId);
    if (!session) return;

    const wordCount = text.trim().split(/\s+/).length;
    
    // Bypass AI for short texts to prevent AI from answering questions and to speed up processing
    if (wordCount <= 15) {
        console.log(`⚡ Short text (${wordCount} words). Bypassing AI, sending as is...`);
        const sentences = text.match(/[^.!?]+[.!?]*/g) || [text];
        session.state = { 
            ...session.state, 
            tactileScript: { 
                sentences: sentences.map(s => ({ 
                    text: s.trim(), 
                    words: s.trim().split(/\s+/).filter(w => w.length > 0) 
                })).filter(s => s.words.length > 0)
            }, 
            currentSentenceIndex: 0, 
            currentWordIndex: 0 
        };
        startStreaming(session);
        return;
    }

    try {
        console.log(`🤖 Groq Summarizing (${maxWords}w limit)...`);
        let res = await callAI(text, maxWords);
        res = res.replace(/```json\n?|\n?```/g, '').trim();
        session.state = { ...session.state, tactileScript: JSON.parse(res), currentSentenceIndex: 0, currentWordIndex: 0 };
        console.log("✅ AI Done");
        startStreaming(session);
    } catch (e) {
        console.warn("⚠️ AI Offline Mode. Reason:", e.message);
        const fbRaw = text || "Content";
        const sentences = fbRaw.match(/[^.!?]+[.!?]*/g) || [fbRaw];
        session.state = { ...session.state, tactileScript: { sentences: sentences.map(s => ({ text: s.trim(), words: s.trim().split(/\s+/).filter(w => w.length > 0) })) }, currentSentenceIndex: 0, currentWordIndex: 0 };
        startStreaming(session);
    }
}

app.post('/process', (req, res) => { for (const [id] of sessions) processText(req.body.text, id, 5); res.json({ success: true }); });

app.post('/upload', upload.single('file'), async (req, res) => {
    try {
        const { mimetype, path: filePath } = req.file;
        let text = "";
        if (mimetype === 'application/pdf') {
            text = await extractPDFText(filePath);
        } else if (mimetype.startsWith('image/')) {
            const result = await Tesseract.recognize(filePath, 'eng');
            text = result.data.text;
        } else { throw new Error("Format error"); }

        if (text && text.trim().length > 10) {
            console.log(`📑 Extracted ${text.length} chars. Summarizing...`);
            for (const [id] of sessions) processText(text, id, 12);
        }

        fs.unlinkSync(filePath); res.json({ success: true });
    } catch (err) { console.error("❌ Fail:", err.message); res.status(500).json({ error: "Process Error" }); }
});

const PORT = 3000;
server.listen(PORT, '0.0.0.0', () => {
    let hostIp = '127.0.0.1';
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                hostIp = iface.address;
            }
        }
    }
    console.log(`🚀 VibroBraille Stable | IP: ${hostIp}`); 
});
