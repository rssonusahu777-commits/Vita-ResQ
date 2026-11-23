const express = require('express');
const cors = require('cors');
const healthRoutes = require('./routes/health');
const aiRoutes = require('./routes/ai');
const voiceRoutes = require('./routes/voice');
const analyticsRoutes = require('./routes/analytics');

const app = express();

// Enable CORS for local Flutter web / emulator development
app.use(cors({
  origin: true,
  credentials: true,
}));

// Limit request payload size to 100kb to prevent payload abuse
app.use(express.json({ limit: '100kb' }));

// Mount API routes
app.use('/api', healthRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/voice', voiceRoutes);
app.use('/api/analytics', analyticsRoutes);

// 404 Catch-All
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'NOT_FOUND',
    message: `Route ${req.method} ${req.originalUrl} not found on this server.`,
  });
});

// Global Error Handler
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  const status = err.statusCode || 500;
  res.status(status).json({
    success: false,
    error: err.code || 'INTERNAL_SERVER_ERROR',
    message: err.message || 'An internal server error occurred.',
  });
});

module.exports = app;
