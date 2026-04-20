const express = require('express');
const axios = require('axios');
const path = require('path');
const app = express();

const API_URL = process.env.API_BASE_URL || 'http://api:8000';
const HOST = process.env.FRONTEND_HOST || '0.0.0.0';
const PORT = Number(process.env.FRONTEND_PORT || 3000);

app.use(express.json());
app.use(express.static(path.join(__dirname, 'views')));

app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

app.get('/', (_req, res) => {
  res.sendFile(path.join(__dirname, 'views', 'index.html'));
});

app.post('/submit', async (req, res) => {
  try {
    const response = await axios.post(`${API_URL}/jobs`, {}, { timeout: 5000 });
    res.json(response.data);
  } catch (err) {
    const status = err.response?.status || 502;
    res.status(status).json({ error: 'job submission failed' });
  }
});

app.get('/status/:id', async (req, res) => {
  try {
    const response = await axios.get(`${API_URL}/jobs/${req.params.id}`, { timeout: 5000 });
    res.json(response.data);
  } catch (err) {
    const status = err.response?.status || 502;
    res.status(status).json({ error: 'job lookup failed' });
  }
});

app.listen(PORT, HOST, () => {
  console.log(`Frontend running on ${HOST}:${PORT}`);
});
