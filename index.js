const express = require('express');
const redis = require('redis');
const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

const app = express();
const port = process.env.APP_PORT || 3000;

function readSecret(secretPath) {
    try {
        if (secretPath && fs.existsSync(secretPath)) {
            return fs.readFileSync(secretPath, 'utf8').trim();
        }
        return null;
    } catch (error) {
        console.log(`⚠️ Не удалось прочитать секрет ${secretPath}:`, error.message);
        return null;
    }
}

const DB_PASSWORD = readSecret(process.env.DB_PASSWORD_FILE) || process.env.DB_PASSWORD || 'secret123';
const API_KEY = readSecret(process.env.API_KEY_FILE) || process.env.API_KEY || 'default-key';

console.log('DB_PASSWORD_FILE:', process.env.DB_PASSWORD_FILE);
console.log('DB_PASSWORD загружен:', !!DB_PASSWORD);
console.log('API_KEY загружен:', !!API_KEY);

const redisClient = redis.createClient({
    socket: {
        host: process.env.REDIS_HOST || 'redis',
        port: parseInt(process.env.REDIS_PORT) || 6379
    }
});

redisClient.on('error', (err) => console.log('Redis Client Error', err));
redisClient.on('connect', () => console.log('Redis Connected'));

const pgPool = new Pool({
    user: process.env.DB_USER || 'admin',
    host: process.env.DB_HOST || 'postgres',
    database: process.env.DB_NAME || 'myapp',
    password: DB_PASSWORD,
    port: parseInt(process.env.DB_PORT) || 5432,
});

pgPool.on('error', (err) => console.log('PostgreSQL Client Error', err));
pgPool.on('connect', () => console.log('PostgreSQL Connected ✅'));

app.use(express.static(path.join(__dirname, 'public')));

app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/api/redis', async (req, res) => {
    try {
        if (!redisClient.isOpen) {
            await redisClient.connect();
        }
        await redisClient.set('health_check', Date.now().toString());
        const value = await redisClient.get('health_check');
        res.json({ connected: true, message: 'Redis работает', lastCheck: value });
    } catch (error) {
        res.json({ connected: false, message: 'Ошибка подключения к Redis', error: error.message });
    }
});

app.get('/api/postgres', async (req, res) => {
    try {
        const client = await pgPool.connect();
        const result = await client.query('SELECT NOW()');
        client.release();
        res.json({ connected: true, message: 'PostgreSQL работает', time: result.rows[0].now });
    } catch (error) {
        res.json({ connected: false, message: 'Ошибка подключения к PostgreSQL', error: error.message });
    }
});

app.get('/api/info', (req, res) => {
    res.json({
        service: 'Docker Compose Project',
        version: '1.0.0',
        nodeVersion: process.version,
        uptime: process.uptime(),
        environment: process.env.NODE_ENV,
        config: {
            redisHost: process.env.REDIS_HOST,
            dbHost: process.env.DB_HOST,
            dbName: process.env.DB_NAME,
            secretsLoaded: !!DB_PASSWORD && !!API_KEY
        }
    });
});

async function startServer() {
    try {
        await redisClient.connect();
        console.log('Redis подключён');
    } catch (err) {
        console.log('Redis недоступен при старте:', err.message);
    }

    try {
        const client = await pgPool.connect();
        await client.query('SELECT 1');
        client.release();
        console.log('PostgreSQL подключён');
    } catch (err) {
        console.log('PostgreSQL недоступен при старте:', err.message);
    }

    app.listen(port, '0.0.0.0', () => {
        console.log(`Сервер запущен на http://0.0.0.0:${port}/`);
        console.log(`Environment: ${process.env.NODE_ENV}`);
    });
}

startServer();
