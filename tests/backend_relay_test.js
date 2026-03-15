/**
 * Backend Relay Smoke Test
 * 
 * Verifies that the server can receive a text processing request
 * and relay it to an active WebSocket session.
 */

const axios = require('axios'); // Note: User needs to install axios for this test script
const WebSocket = require('ws');

const SERVER_URL = 'http://localhost:3000';
const WS_URL = 'ws://localhost:3000';
const TEST_SESSION_ID = 'MOCK-SESSION-123';

async function runTest() {
    console.log("🚀 Starting Backend Relay Test...");
    
    // 1. Setup WebSocket listener (Simulating Mobile App)
    const ws = new WebSocket(WS_URL);
    
    ws.on('open', () => {
        console.log("✅ WebSocket Connected");
        ws.send(JSON.stringify({ type: 'IDENTIFY', sessionId: TEST_SESSION_ID }));
    });

    ws.on('message', (data) => {
        const message = JSON.parse(data);
        if (message.type === 'BRAILLE_TEXT') {
            console.log("✅ Received Relayed Text:", message.payload);
            console.log("🎉 Test Passed!");
            process.exit(0);
        }
    });

    // 2. Wait for connection, then trigger POST request (Simulating Dashboard)
    setTimeout(async () => {
        try {
            console.log("📡 Sending process request...");
            const response = await axios.post(`${SERVER_URL}/process`, {
                text: "This is a test sentence for the VibroBraille system.",
                sessionId: TEST_SESSION_ID
            });
            
            if (response.data.success) {
                console.log("✅ Server accepted request:", response.data.processed);
            }
        } catch (error) {
            console.error("❌ Request Failed:", error.message);
            process.exit(1);
        }
    }, 1000);
}

runTest().catch(err => {
    console.error("❌ Test Error:", err);
    process.exit(1);
});
