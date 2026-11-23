const app = require('./app');
const config = require('./config');

const server = app.listen(config.port, () => {
  console.log(`[Vita ResQ AI Backend] Service listening on port ${config.port}`);
  console.log(`[Vita ResQ AI Backend] Model: ${config.geminiModel}`);
  console.log(`[Vita ResQ AI Backend] Gemini API Key configured: ${Boolean(config.geminiApiKey)}`);
  console.log(`[Vita ResQ AI Backend] Health check available at: http://localhost:${config.port}/api/health`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('[Vita ResQ AI Backend] SIGTERM received. Closing server...');
  server.close(() => process.exit(0));
});

process.on('SIGINT', () => {
  console.log('[Vita ResQ AI Backend] SIGINT received. Closing server...');
  server.close(() => process.exit(0));
});
